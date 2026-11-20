"""UCCM GPSDO daemon on ntp1-aah1.

- Polls the UCCM over serial at the system's mid-second and sends chrony a
  GPSS sample (whole seconds) on its SOCK refclock; the PPS refclock locks to it.
- Draws the status on the SSD1322 OLED: local time and a status word always, below
  them a rotating page (text pages, satellite signal bars, history graphs).
- Writes node_exporter textfile metrics for the UCCM and chrony.
"""

import collections
import datetime
import math
import os
import socket
import struct
import subprocess
import sys
import threading
import time
import zoneinfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uccm import UCCM, label_plausible, parse_status  # noqa: E402

CHRONY_SOCK = "/run/chrony.gpsdo.sock"
METRICS = "/run/gpsdo/gpsdo.prom"
POLL_S = 4
SLOW_EVERY = 8                          # polls between the EFC, output and lock LED reads
SOCK_MAGIC = 0x534F434B
SOCK_SAMPLE = struct.Struct("qqdiiii")  # struct timeval, offset, pulse, leap, _pad, magic
CPU_TEMP = "/sys/class/thermal/thermal_zone0/temp"
NIC_STATS = "/sys/class/net/ntp0/statistics/{}_packets"

# OLED: SSD1322 on SPI0 CE0. DC and RES are wired to GPIO24 and GPIO25.
OLED = {"port": 0, "device": 0, "gpio_DC": 24, "gpio_RST": 25, "bus_speed_hz": 8_000_000}
LOCAL_TZ = zoneinfo.ZoneInfo("Europe/Berlin")
NIGHT = (22, 7)                         # local hours with the display dimmed
CONTRAST_DAY, CONTRAST_NIGHT = 128, 16
PAGE_SECONDS = 8
FONT_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_MONO_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
# OLED burn-in: the whole layout creeps 1 px every 30 s along a snake through x 0-6, y 0-3 and back
# (27 min per round), so no pixel stays lit in the same place; everything fits 256 x 64 at (6, 3).
_SNAKE = [(x, y) for y in range(4) for x in (range(7) if y % 2 == 0 else range(6, -1, -1))]
SHIFTS = _SNAKE + _SNAKE[-2:0:-1]
SHIFT_SECONDS = 30

# History for the graphs: every poll for an hour, every minute for a day.
FAST = collections.deque(maxlen=3600 // POLL_S)
SLOW = collections.deque(maxlen=24 * 60)

state = {"uccm": {}, "uccm_time": 0.0, "efc": None, "outp": None, "led": None,
         "chrony": {}, "pps": {}, "sock_sent": 0, "rates": (None, None)}
lock = threading.Lock()


def log(msg):
    print(msg, flush=True)


def read_float(path, scale=1.0):
    try:
        with open(path) as f:
            return float(f.read().split()[0]) * scale
    except (OSError, ValueError, IndexError):
        return None


def send_gpss(sock, t_query, utc):
    """At system time floor(t_query) true UTC is `utc`: offset = utc - floor(t_query)."""
    sec = math.floor(t_query)
    sock.sendto(SOCK_SAMPLE.pack(sec, 0, float(utc - sec), 0, 0, 0, SOCK_MAGIC), CHRONY_SOCK)


def chronyc(*args):
    try:
        out = subprocess.run(["chronyc", "-c", "-n", *args], capture_output=True,
                             text=True, timeout=3, check=True).stdout
    except (subprocess.SubprocessError, OSError):
        return []
    return [line.split(",") for line in out.strip().split("\n") if line]


def chrony_status():
    tracking, pps = {}, {}
    rows = chronyc("tracking")
    if rows and len(rows[0]) >= 14:
        t = rows[0]
        tracking = {
            "refid": t[1], "stratum": int(t[2]), "offset": float(t[4]), "last_offset": float(t[5]),
            "rms_offset": float(t[6]), "freq_ppm": float(t[7]), "skew_ppm": float(t[9]),
            "root_delay": float(t[10]), "root_dispersion": float(t[11]), "leap": t[13],
        }
    for row in chronyc("sources"):
        if len(row) >= 10 and row[2] == "PPS":
            pps["reach"] = bin(int(row[5], 8)).count("1")
            pps["selected"] = row[1] == "*"
    for row in chronyc("sourcestats"):
        if len(row) >= 8 and row[0] == "PPS":
            pps["samples"], pps["stddev"] = int(row[1]), float(row[7])
    return tracking, pps


def nic_rates(history):
    """Packets per minute on ntp0 over the last minute of samples."""
    now = time.monotonic()
    rx, tx = read_float(NIC_STATS.format("rx")), read_float(NIC_STATS.format("tx"))
    if rx is None or tx is None:
        return None, None
    history.append((now, rx, tx))
    while len(history) > 2 and now - history[0][0] > 60:
        history.popleft()
    t0, rx0, tx0 = history[0]
    if now - t0 < 10:
        return None, None
    return (rx - rx0) * 60 / (now - t0), (tx - tx0) * 60 / (now - t0)


def poller():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    gps, n, last_slow, nic = None, 0, 0.0, collections.deque()
    while True:
        try:
            if gps is None:
                gps = UCCM()
            # Query at the middle of the system second, so the truncated label is unambiguous.
            now = time.time()
            time.sleep((math.floor(now) + 1.5 - now) % 1.0 or 1.0)
            t_query = time.time()
            s = parse_status(gps.query("SYST:STAT?"))
            if label_plausible(s):
                try:
                    send_gpss(sock, t_query, s["utc"])
                    with lock:
                        state["sock_sent"] += 1
                except OSError as e:
                    log(f"chrony SOCK: {e}")
            slow = {}
            if n % SLOW_EVERY == 0:
                try:
                    slow["efc"] = float(gps.query("DIAG:ROSC:EFC:REL?", 1.5).split()[-1])
                except (ValueError, IndexError):
                    pass
                for key, cmd in (("outp", "OUTP:STAT?"), ("led", "LED:GPSL?")):
                    answer = gps.query(cmd, 1.5).strip()
                    if answer and " " not in answer and len(answer) <= 16:
                        slow[key] = answer
            tracking, pps = chrony_status()
            rates = nic_rates(nic)
            with lock:
                state.update(slow)
                state["uccm"], state["uccm_time"] = s, time.time()
                state["chrony"], state["pps"], state["rates"] = tracking, pps, rates
                FAST.append({"t": t_query, "offset": tracking.get("offset"), "phase": s.get("phase")})
                if t_query - last_slow >= 60:
                    last_slow = t_query
                    SLOW.append({"t": t_query, "efc": state["efc"], "freq": tracking.get("freq_ppm"),
                                 "temp": s.get("temp"), "cpu": read_float(CPU_TEMP, 0.001),
                                 "tracked": s.get("tracked")})
            write_metrics()
            n += 1
        except OSError as e:
            log(f"serial: {e}")
            if gps is not None:
                gps.close()
            gps = None
            time.sleep(5)
            continue
        time.sleep(max(0.0, POLL_S - 1.5))


def write_metrics():
    with lock:
        s, t, c, p = dict(state["uccm"]), state["uccm_time"], dict(state["chrony"]), dict(state["pps"])
        efc, outp, led, sent = state["efc"], state["outp"], state["led"], state["sock_sent"]
    lines = [
        "# HELP gpsdo_last_poll_timestamp_seconds Time of the last UCCM status read.",
        "# TYPE gpsdo_last_poll_timestamp_seconds gauge",
        f"gpsdo_last_poll_timestamp_seconds {t:.3f}",
        "# TYPE gpsdo_gpss_samples_total counter",
        f"gpsdo_gpss_samples_total {sent}",
    ]
    tracked = [x for x in s.get("sats", []) if x["tracked"]]
    gauges = {
        "gpsdo_pps_valid": 1 if s.get("pps") == "Valid" else 0 if "pps" in s else None,
        "gpsdo_tfom": s.get("tfom"), "gpsdo_ffom": s.get("ffom"),
        "gpsdo_satellites_tracked": s.get("tracked"), "gpsdo_satellites_untracked": s.get("untracked"),
        "gpsdo_cno_mean_dbhz": round(sum(x["cno"] for x in tracked) / len(tracked), 2) if tracked else None,
        "gpsdo_phase_seconds": s.get("phase"), "gpsdo_temperature_celsius": s.get("temp"),
        "gpsdo_antenna_volts": s.get("ant_v"), "gpsdo_antenna_milliamps": s.get("ant_ma"),
        "gpsdo_efc_relative": efc,
        "chrony_tracking_stratum": c.get("stratum"),
        "chrony_tracking_system_offset_seconds": c.get("offset"),
        "chrony_tracking_last_offset_seconds": c.get("last_offset"),
        "chrony_tracking_rms_offset_seconds": c.get("rms_offset"),
        "chrony_tracking_frequency_ppm": c.get("freq_ppm"),
        "chrony_tracking_skew_ppm": c.get("skew_ppm"),
        "chrony_tracking_root_delay_seconds": c.get("root_delay"),
        "chrony_tracking_root_dispersion_seconds": c.get("root_dispersion"),
        "chrony_pps_reach": p.get("reach"),
        "chrony_pps_selected": (1 if p["selected"] else 0) if "selected" in p else None,
        "chrony_pps_samples": p.get("samples"),
        "chrony_pps_stddev_seconds": p.get("stddev"),
    }
    for name, value in gauges.items():
        if value is not None:
            lines += [f"# TYPE {name} gauge", f"{name} {value}"]
    if tracked:
        lines.append("# TYPE gpsdo_satellite_cno_dbhz gauge")
        lines += [f'gpsdo_satellite_cno_dbhz{{prn="{x["prn"]}"}} {x["cno"]}' for x in tracked]
        lines.append("# TYPE gpsdo_satellite_elevation_degrees gauge")
        lines += [f'gpsdo_satellite_elevation_degrees{{prn="{x["prn"]}"}} {x["el"]}' for x in tracked]
    for name, label, value in (("gpsdo_status_info", "status", s.get("status")),
                               ("gpsdo_output_info", "state", outp), ("gpsdo_lock_info", "state", led)):
        if value:
            lines += [f"# TYPE {name} gauge", f'{name}{{{label}="{value}"}} 1']
    if c:
        lines += ["# TYPE chrony_tracking_info gauge",
                  f'chrony_tracking_info{{refid="{c["refid"]}",leap="{c["leap"]}"}} 1']
    tmp = METRICS + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, METRICS)


# Every formatter returns a fixed width, so a value changing length never moves the text after it.

def fmt_ns(seconds):
    """8 characters."""
    if seconds is None:
        return f"{'-':>8}"
    value = seconds * 1e9
    for unit in ("ns", "us", "ms"):
        if abs(value) < 9999.5:
            return f"{value:+5.0f} {unit}"
        value /= 1000
    return f"{value:+5.0f}  s"


def fmt(value, spec, width):
    return f"{'-':>{width}}" if value is None else f"{value:{spec}}"[:width].rjust(width)


def short_status(s, c, age):
    if age > 30 or not s:
        return "!UCCM"
    if c.get("refid") != "PPS":
        return "!SYNC"
    status = s.get("status", "?")
    for word, short in (("Holdover", "Hold"), ("Warm", "Warmup"), ("Master", "Master")):
        if word in status:
            return short
    return status[:6]


def page_gpsdo(d, x, y, f, data):
    s = data["s"]
    status = "Holdover" if "Holdover" in s.get("status", "") else s.get("status", "?")[:8]
    pps = "ok" if s.get("pps") == "Valid" else s.get("pps", "?").lower()[:7]
    tr, un = s.get("tracked"), s.get("untracked")
    seen = None if tr is None or un is None else tr + un
    d.text((x, y), f"{status:<8}  PPS {pps:<7}  sats {fmt(tr, 'd', 2)}/{fmt(seen, 'd', 2)}", font=f, fill="white")
    d.text((x, y + 14), f"TFOM {fmt(s.get('tfom'), 'd', 1)}  FFOM {fmt(s.get('ffom'), 'd', 1)}  "
                        f"phase {fmt_ns(s.get('phase'))}", font=f, fill="white")


def page_chrony(d, x, y, f, data):
    c, p = data["c"], data["p"]
    if not c:
        d.text((x, y), "chrony: no data", font=f, fill="white")
        return
    d.text((x, y), f"{c['refid']:<4} s{c['stratum']:<2}  off {fmt_ns(c['offset'])}  rms {fmt_ns(c['rms_offset'])}",
           font=f, fill="white")
    d.text((x, y + 14), f"freq {fmt(c['freq_ppm'], '+.3f', 8)} ppm  PPS sd {fmt_ns(p.get('stddev'))}",
           font=f, fill="white")


def page_oscillator(d, x, y, f, data):
    s = data["s"]
    d.text((x, y), f"EFC {fmt(data['efc'], '+.3f', 7)}  UCCM {fmt(s.get('temp'), '.1f', 5)} C  "
                   f"CM4 {fmt(data['cpu'], '.1f', 5)} C", font=f, fill="white")
    d.text((x, y + 14), f"ant {fmt(s.get('ant_v'), '.2f', 4)} V {fmt(s.get('ant_ma'), '.2f', 5)} mA  "
                        f"{(data['led'] or '-'):<8} {(data['outp'] or '-')[:8]}", font=f, fill="white")


def page_network(d, x, y, f, data):
    rx, tx = data["rates"]
    up = read_float("/proc/uptime") or 0
    d.text((x, y), f"ntp0 rx {fmt(rx, '.0f', 6)}/min  tx {fmt(tx, '.0f', 6)}/min", font=f, fill="white")
    d.text((x, y + 14), f"up {int(up // 86400):>3}d {int(up % 86400 // 3600):02d}h  "
                        f"GPSS {data['sent']:>7}", font=f, fill="white")


def page_satellites(d, x, y, f, tiny, data):
    sats = sorted((s for s in data["s"].get("sats", []) if s["tracked"]), key=lambda s: s["prn"])[:12]
    seen = len(data["s"].get("sats", []))
    d.text((x, y), "sats", font=tiny, fill="white")
    d.text((x, y + 8), f"{len(sats):>2}/{seen:<2}", font=tiny, fill="white")
    d.text((x, y + 16), "dBHz", font=tiny, fill="white")
    for i, sat in enumerate(sats):
        bx = x + 44 + i * 16
        h = max(1, min(16, round((sat["cno"] - 20) * 16 / 30)))  # 20-50 dB-Hz
        d.rectangle((bx, y + 15 - h, bx + 9, y + 15), fill="white")
        d.text((bx - 1, y + 16), f"{sat['prn']:>2}", font=tiny, fill="white")


def page_graph(d, x, y, tiny, rows, key, label, formatter, seconds):
    t_end = time.time()
    points = [(r["t"], r[key]) for r in rows if r.get(key) is not None and r["t"] >= t_end - seconds]
    d.text((x, y), label, font=tiny, fill="white")
    if len(points) < 2:
        d.text((x, y + 8), "no data", font=tiny, fill="white")
        return
    lo, hi = min(v for _, v in points), max(v for _, v in points)
    d.text((x, y + 8), formatter(hi), font=tiny, fill="white")
    d.text((x, y + 16), formatter(lo), font=tiny, fill="white")
    gx, gw, gy, gh = x + 60, 186, y + 1, 23
    d.rectangle((gx - 1, gy - 1, gx + gw, gy + gh), outline=64)
    span = (hi - lo) or 1.0
    columns = {}
    for t, v in points:
        col = int((t - (t_end - seconds)) / seconds * (gw - 1))
        a, b = columns.get(col, (v, v))
        columns[col] = (min(a, v), max(b, v))
    for col, (a, b) in columns.items():
        top = gy + gh - 1 - round((b - lo) / span * (gh - 1))
        bottom = gy + gh - 1 - round((a - lo) / span * (gh - 1))
        d.line((gx + col, top, gx + col, bottom), fill="white")


def display():
    from luma.core.interface.serial import spi
    from luma.core.render import canvas
    from luma.oled.device import ssd1322
    from PIL import ImageFont

    dev = ssd1322(spi(**OLED), width=256, height=64)
    big = ImageFont.truetype(FONT_MONO_BOLD, 30)
    small = ImageFont.truetype(FONT_MONO, 10)
    tiny = ImageFont.truetype(FONT_MONO, 9)
    pages = [
        lambda d, x, y, data: page_gpsdo(d, x, y, small, data),
        lambda d, x, y, data: page_chrony(d, x, y, small, data),
        lambda d, x, y, data: page_oscillator(d, x, y, small, data),
        lambda d, x, y, data: page_satellites(d, x, y, small, tiny, data),
        lambda d, x, y, data: page_graph(d, x, y, tiny, data["fast"], "offset", "offset 1h", fmt_ns, 3600),
        lambda d, x, y, data: page_graph(d, x, y, tiny, data["fast"], "phase", "UCCM ph 1h", fmt_ns, 3600),
        lambda d, x, y, data: page_graph(d, x, y, tiny, data["slow"], "efc", "EFC 24h", lambda v: fmt(v, "+.3f", 8), 86400),
        lambda d, x, y, data: page_graph(d, x, y, tiny, data["slow"], "freq", "CM4 ppm 24h", lambda v: fmt(v, "+.3f", 8), 86400),
        lambda d, x, y, data: page_graph(d, x, y, tiny, data["slow"], "temp", "UCCM C 24h", lambda v: fmt(v, ".1f", 8), 86400),
        lambda d, x, y, data: page_graph(d, x, y, tiny, data["slow"], "tracked", "sats 24h", lambda v: fmt(v, ".0f", 8), 86400),
        lambda d, x, y, data: page_network(d, x, y, small, data),
    ]
    contrast = None
    while True:
        now = time.time()
        time.sleep(math.floor(now) + 1.002 - now)
        utc = datetime.datetime.now(datetime.timezone.utc)
        local = utc.astimezone(LOCAL_TZ)
        hour = local.hour
        want = CONTRAST_NIGHT if hour >= NIGHT[0] or hour < NIGHT[1] else CONTRAST_DAY
        if want != contrast:
            dev.contrast(want)
            contrast = want
        with lock:
            data = {"s": dict(state["uccm"]), "c": dict(state["chrony"]), "p": dict(state["pps"]),
                    "efc": state["efc"], "led": state["led"], "outp": state["outp"],
                    "sent": state["sock_sent"], "rates": state["rates"],
                    "fast": list(FAST), "slow": list(SLOW)}
            age = time.time() - state["uccm_time"]
        data["cpu"] = read_float(CPU_TEMP, 0.001)
        x, y = SHIFTS[int(utc.timestamp()) // SHIFT_SECONDS % len(SHIFTS)]
        page = pages[int(utc.timestamp()) // PAGE_SECONDS % len(pages)]
        with canvas(dev) as d:
            d.text((x, y - 4), local.strftime("%H:%M:%S"), font=big, fill="white")
            d.text((x + 152, y + 2), local.strftime("%d %b %Y"), font=small, fill="white")
            d.text((x + 152, y + 14), f"{local.strftime('%Z'):<4} {short_status(data['s'], data['c'], age):<6}",
                   font=small, fill="white")
            try:
                page(d, x, y + 34, data)
            except Exception as e:  # a page bug must not stop the clock
                d.text((x, y + 34), f"page: {type(e).__name__}", font=small, fill="white")


def main():
    threading.Thread(target=poller, daemon=True).start()
    display()


if __name__ == "__main__":
    main()
