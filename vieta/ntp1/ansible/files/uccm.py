"""Serial access to the Samsung UCCM-LP GPSDO (SCPI over RS-232, 57600 8N1).

Shared by clock-bootstrap.py and gpsdo.py. The UCCM echoes input and prints a
"UCCM>" prompt; the port is opened raw (no tty echo) and without becoming the
controlling terminal, or the echo feeds back and reads stop on SIGTTIN.
"""

import datetime
import os
import re
import select
import termios
import time

PORT = "/dev/serial/by-id/usb-1a86_USB2.0-Ser_-if00-port0"

# The UCCM's time label is GPS time although it says "Synchronized to UTC".
# GPS - UTC = TAI - UTC - 19 s, from the same leap second list chrony uses (tzdata keeps it current).
LEAP_LIST = "/usr/share/zoneinfo/leap-seconds.list"
NTP_TO_UNIX = 2_208_988_800
_leap_cache = {}

MONTHS = {m: i for i, m in enumerate(
    ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"], 1)}

PATTERNS = {
    "label": re.compile(r"GPS\s+(\d\d):(\d\d):(\d\d)\s+(\d{1,2}) ([A-Z]{3}) (\d{4})"),
    "status": re.compile(r"UCCM [AB] Status\[([^\]]+)\]"),
    "merit": re.compile(r"TFOM\s+(\d+)\s+FFOM\s+(\d+)"),
    "pps": re.compile(r"\[ GPS 1PPS (\w+) \]"),
    "tracking": re.compile(r"Tracking:\s+(\d+)\D+Not Tracking:\s+(\d+)"),
    "phase": re.compile(r"phase : ([+-]?[\d.]+E[+-]?\d+)"),
    "temp": re.compile(r"Temp = ([\d.]+)"),
    "antenna": re.compile(r"ANT V=([\d.]+)V, I=([\d.]+)mA"),
}


def gps_utc_offset(unix_time):
    """GPS - UTC at unix_time, or None without a readable leap second list."""
    try:
        mtime = os.stat(LEAP_LIST).st_mtime
        if _leap_cache.get("mtime") != mtime:
            entries = []
            with open(LEAP_LIST) as f:
                for line in f:
                    fields = line.split()
                    if len(fields) >= 2 and not line.startswith("#"):
                        entries.append((int(fields[0]) - NTP_TO_UNIX, int(fields[1])))
            _leap_cache.update(mtime=mtime, entries=entries)
    except (OSError, ValueError):
        return None
    tai_utc = None
    for since, offset in _leap_cache["entries"]:
        if since <= unix_time:
            tai_utc = offset
    return None if tai_utc is None else tai_utc - 19


class UCCM:
    def __init__(self, port=PORT):
        self.fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        a = termios.tcgetattr(self.fd)
        a[0] = a[1] = a[3] = 0
        a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        a[4] = a[5] = termios.B57600
        termios.tcsetattr(self.fd, termios.TCSANOW, a)
        termios.tcflush(self.fd, termios.TCIOFLUSH)

    def close(self):
        os.close(self.fd)

    def query(self, cmd, timeout=3.0):
        """Send one command, return its answer without the echo and the prompt.

        The answer ends with a prompt after the echo of this command; prompts that
        arrive late from the previous answer must not end it early. After that prompt
        the line has to stay quiet for 100 ms, so nothing leaks into the next answer.
        """
        termios.tcflush(self.fd, termios.TCIFLUSH)
        os.write(self.fd, (cmd + "\r\n").encode())
        echo = cmd.encode()
        buf, end, done = b"", time.monotonic() + timeout, False
        while time.monotonic() < end:
            r, _, _ = select.select([self.fd], [], [], 0.1)
            if r:
                buf += os.read(self.fd, 4096)
                i = buf.find(echo)
                done = i >= 0 and b"UCCM>" in buf[i + len(echo):]
            elif done:
                break
        i = buf.find(echo)
        text = buf[i + len(echo):] if i >= 0 else b""
        lines = [ln for ln in text.decode(errors="replace").replace("\r", "").split("\n")
                 if ln.strip() and "UCCM>" not in ln and "Command Complete" not in ln]
        return "\n".join(lines)


def parse_status(text):
    """Fields of a SYST:STAT? answer; missing fields are left out."""
    s = {}
    m = PATTERNS["label"].search(text)
    if m:
        hh, mm, ss, day, mon, year = m.groups()
        if mon in MONTHS:
            gps = int(datetime.datetime(int(year), MONTHS[mon], int(day), int(hh), int(mm), int(ss),
                                        tzinfo=datetime.timezone.utc).timestamp())
            offset = gps_utc_offset(gps)
            if offset is not None:
                s["utc"] = gps - offset
            s["year"] = int(year)
    for key in ("status", "pps"):
        m = PATTERNS[key].search(text)
        if m:
            s[key] = m.group(1).strip()
    m = PATTERNS["merit"].search(text)
    if m:
        s["tfom"], s["ffom"] = int(m.group(1)), int(m.group(2))
    m = PATTERNS["tracking"].search(text)
    if m:
        s["tracked"], s["untracked"] = int(m.group(1)), int(m.group(2))
    m = PATTERNS["phase"].search(text)
    if m:
        s["phase"] = float(m.group(1))
    m = PATTERNS["temp"].search(text)
    if m:
        s["temp"] = float(m.group(1))
    m = PATTERNS["antenna"].search(text)
    if m:
        s["ant_v"], s["ant_ma"] = float(m.group(1)), float(m.group(2))
    s["sats"] = parse_satellites(text)
    return s


def parse_satellites(text):
    """The table under 'PRN El AZ CNO PRN El Az': tracked satellites left (with CNO), untracked right."""
    sats, split = [], None
    for line in text.split("\n"):
        if split is None:
            if line.startswith("PRN") and line.count("PRN") >= 2:
                split = line.index("PRN", 3)
            continue
        if not line.strip() or not line[:1].isspace():
            break
        left, right = line[:split].split(), line[split:split + 14].split()
        if len(left) == 4 and all(v.isdigit() for v in left):
            sats.append({"prn": int(left[0]), "el": int(left[1]), "az": int(left[2]), "cno": int(left[3]), "tracked": True})
        if len(right) == 3 and all(v.isdigit() for v in right):
            sats.append({"prn": int(right[0]), "el": int(right[1]), "az": int(right[2]), "tracked": False})
    return sats


def label_plausible(s):
    """A cold UCCM reports 1980 until GPS has given it the date."""
    return "utc" in s and s.get("year", 0) >= 2026
