"""Set the system clock from the GPSDO's PPS before chrony starts.

chrony's PHC refclock needs `width` because the i210 timestamps both edges of
the 48 us pulse, and with `width` it accepts a pulse only when the lock source
(GPSS, whole seconds from the serial line) agrees with it to within width/2.
GPSS cannot carry a sub-second phase, so after a cold boot chrony would drop
every pulse. This step pairs the edges itself (rising = first of a pair),
takes the second number from the UCCM, corrects the kernel frequency (the
CM4's undisciplined clock runs tens of ppm off, enough to leave the window
within a second) and steps the clock to within a few microseconds, then hands
the PHC to chrony, which starts from that frequency.

It waits, without a timeout, until the UCCM gives plausible time and pulses:
serving no time is better than serving a wrong one.
"""

import ctypes
import glob
import os
import select
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uccm import PORT, UCCM, label_plausible, parse_status  # noqa: E402

PHC = "/dev/ptp-ntp0"
PIN, CHANNEL = 0, 0                     # SDP0 -> external timestamp channel 0
PAIR_MAX_NS = 200_000                   # the falling edge follows 48 us after the rising one
EVENT = struct.Struct("<qIIII8x")       # struct ptp_extts_event: sec, nsec, rsv, index, flags
TOLERANCE_NS = 5_000
RATE_SECONDS = 10
RATE_TOLERANCE_PPM = 0.1
ADJ_FREQUENCY = 0x0002


class Timex(ctypes.Structure):
    _fields_ = [
        ("modes", ctypes.c_uint), ("offset", ctypes.c_long), ("freq", ctypes.c_long),
        ("maxerror", ctypes.c_long), ("esterror", ctypes.c_long), ("status", ctypes.c_int),
        ("constant", ctypes.c_long), ("precision", ctypes.c_long), ("tolerance", ctypes.c_long),
        ("time_sec", ctypes.c_long), ("time_usec", ctypes.c_long), ("tick", ctypes.c_long),
        ("ppsfreq", ctypes.c_long), ("jitter", ctypes.c_long), ("shift", ctypes.c_int),
        ("stabil", ctypes.c_long), ("jitcnt", ctypes.c_long), ("calcnt", ctypes.c_long),
        ("errcnt", ctypes.c_long), ("stbcnt", ctypes.c_long), ("tai", ctypes.c_int),
        ("padding", ctypes.c_int * 11),
    ]


LIBC = ctypes.CDLL(None, use_errno=True)


def adjust_frequency(error_ppm):
    """Correct the kernel clock frequency by -error_ppm (freq is ppm << 16, positive = faster)."""
    tx = Timex()
    if LIBC.adjtimex(ctypes.byref(tx)) < 0:
        raise OSError(ctypes.get_errno(), "adjtimex read")
    old = tx.freq / 65536
    new = max(-500.0, min(500.0, old - error_ppm))
    tx = Timex(modes=ADJ_FREQUENCY, freq=int(new * 65536))
    if LIBC.adjtimex(ctypes.byref(tx)) < 0:
        raise OSError(ctypes.get_errno(), "adjtimex set")
    log(f"kernel frequency {old:+.3f} -> {new:+.3f} ppm")


def log(msg):
    print(msg, flush=True)


def wait_for(path):
    while not glob.glob(path):
        log(f"waiting for {path}")
        time.sleep(5)


def sysfs():
    return "/sys/class/ptp/" + os.path.basename(os.path.realpath(PHC))


def extts(enable):
    base = sysfs()
    if enable:
        with open(f"{base}/pins/SDP{PIN}", "w") as f:
            f.write(f"1 {CHANNEL}\n")
    with open(f"{base}/extts_enable", "w") as f:
        f.write(f"{CHANNEL} {1 if enable else 0}\n")


def phc_to_sys(clockid):
    """System minus PHC time in ns, from the tightest of several sandwiched reads."""
    best = None
    for _ in range(20):
        a = time.clock_gettime_ns(time.CLOCK_REALTIME)
        p = time.clock_gettime_ns(clockid)
        b = time.clock_gettime_ns(time.CLOCK_REALTIME)
        if best is None or b - a < best[0]:
            best = (b - a, (a + b) // 2 - p)
    return best[1]


def rising_edges(fd, clockid, count, timeout_s):
    """System times (ns) of `count` rising edges, mapped right after each read."""
    edges, prev, deadline = [], None, time.monotonic() + timeout_s
    while len(edges) < count and time.monotonic() < deadline:
        r, _, _ = select.select([fd], [], [], 0.5)
        if not r:
            continue
        data = os.read(fd, EVENT.size * 8)
        offset = phc_to_sys(clockid)
        for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
            sec, nsec, _, index, _ = EVENT.unpack_from(data, i)
            if index != CHANNEL:
                continue
            t = sec * 1_000_000_000 + nsec
            if prev is not None and t - prev[0] <= PAIR_MAX_NS:
                edges.append(prev[0] + prev[1])
                prev = None
            else:
                prev = (t, offset)
    return edges


def one_second_apart(edges):
    return len(edges) >= 2 and all(
        abs((b - a) - 1_000_000_000) < 1_000_000 for a, b in zip(edges, edges[1:]))


def attempt(gps, fd, clockid):
    edges = rising_edges(fd, clockid, RATE_SECONDS + 1, RATE_SECONDS + 4)
    if len(edges) < RATE_SECONDS + 1 or not one_second_apart(edges):
        log(f"no steady PPS yet ({len(edges)} paired edges)")
        return False
    span = edges[-1] - edges[0]
    true = (len(edges) - 1) * 1_000_000_000
    error_ppm = (span - true) / true * 1e6
    if abs(error_ppm) > RATE_TOLERANCE_PPM:
        adjust_frequency(error_ppm)
        return False
    last = edges[-1]
    # Ask in the middle of the second that started with the last edge: the label
    # is that second, truncated, so half a second of margin on either side.
    target = last + 500_000_000
    while time.clock_gettime_ns(time.CLOCK_REALTIME) < target:
        time.sleep(0.005)
    status = parse_status(gps.query("SYST:STAT?"))
    if not label_plausible(status):
        log(f"UCCM time not plausible yet: {status}")
        return False
    if time.clock_gettime_ns(time.CLOCK_REALTIME) - last > 1_400_000_000:
        log("serial answer came too late to pair with the edge, retrying")
        return False
    step = status["utc"] * 1_000_000_000 - last
    if abs(step) > TOLERANCE_NS:
        now = time.clock_gettime_ns(time.CLOCK_REALTIME)
        time.clock_settime_ns(time.CLOCK_REALTIME, now + step)
        log(f"stepped the clock by {step / 1e9:+.9f} s ({status.get('status')}, 1PPS {status.get('pps')})")
    # Confirm on the next edges: each must now fall on a whole second.
    edges = rising_edges(fd, clockid, 2, 4)
    if not one_second_apart(edges):
        return False
    residual = max(abs(((e + 500_000_000) % 1_000_000_000) - 500_000_000) for e in edges)
    log(f"edges now within {residual / 1000:.1f} us of the second")
    return residual < TOLERANCE_NS


def main():
    wait_for(PHC)
    wait_for(PORT)
    gps = UCCM()
    fd = os.open(PHC, os.O_RDWR)
    clockid = ((~fd) << 3) | 3
    try:
        extts(True)
        while not attempt(gps, fd, clockid):
            time.sleep(2)
    finally:
        extts(False)
        os.close(fd)
        gps.close()


if __name__ == "__main__":
    main()
