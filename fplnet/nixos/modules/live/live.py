"""Writes this edge's live state to a JSON file every second; nginx serves it as /live.json.

Sources are the exporters on the loopback.
smokeping_prober pings every target once a second, bird_exporter has the BGP sessions.
"""

import collections
import json
import os
import re
import time
import urllib.request

LOOPBACK = os.environ["LIVE_LOOPBACK"]
OUT = os.environ["LIVE_OUT"]
EDGE = os.environ["LIVE_EDGE"]
SMOKEPING = f"http://[{LOOPBACK}]:9374/metrics"
BIRD = f"http://[{LOOPBACK}]:9324/metrics"

SESSION_EVERY = 10
WINDOW = 60
KIND = {"from_transit": "transit", "from_route_server": "route server", "from_peer": "peer"}
LINE = re.compile(r'^(\w+)\{([^}]*)\} (\S+)$')
LABEL = re.compile(r'(\w+)="([^"]*)"')


def fetch(url):
    with urllib.request.urlopen(url, timeout=2) as r:
        return r.read().decode()


def scrape(url):
    """Prometheus text as (name, labels, value) tuples."""
    for line in fetch(url).splitlines():
        m = LINE.match(line)
        if m:
            yield m.group(1), dict(LABEL.findall(m.group(2))), float(m.group(3))


def target_label(host):
    # The far end of a backbone tunnel is named wg-<this edge>.<peer>.fplnet.net (dns.tf).
    if host.startswith("wg-") and host.endswith(".fplnet.net"):
        return "backbone", host.split(".", 1)[1].removesuffix(".fplnet.net")
    return "neighbour", host


def pings():
    totals = collections.defaultdict(lambda: [0.0, 0.0, 0.0])
    for name, labels, value in scrape(SMOKEPING):
        i = {"smokeping_requests_total": 0,
             "smokeping_response_duration_seconds_count": 1,
             "smokeping_response_duration_seconds_sum": 2}.get(name)
        if i is not None:
            totals[labels["host"]][i] += value
    return totals


def sessions():
    """One bird_exporter scrape; every scrape makes it query BIRD."""
    up, counts = [], {}
    for name, labels, value in scrape(BIRD):
        if labels.get("proto") != "BGP":
            continue
        if name == "bird_protocol_up":
            session = labels["name"]
            kind = "backbone" if session.startswith("ibgp_") else KIND.get(labels.get("import_filter"), "other")
            up.append({"name": session, "kind": kind, "state": labels.get("state"), "up": value == 1})
        elif name == "bird_protocol_prefix_import_count":
            counts[labels["name"]] = int(value)
    for s in up:
        s["prefixes"] = counts.get(s["name"])
    return sorted(up, key=lambda s: (s["kind"], s["name"]))


def interfaces():
    result = {}
    try:
        names = os.listdir("/sys/class/net")
    except OSError:
        return result
    for iface in names:
        if iface == "lo":
            continue
        stats = f"/sys/class/net/{iface}/statistics"
        try:
            with open(f"{stats}/rx_bytes") as rx, open(f"{stats}/tx_bytes") as tx:
                result[iface] = (int(rx.read()), int(tx.read()))
        except OSError:
            pass
    return result


def write(state):
    tmp = f"{OUT}.tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, separators=(",", ":"))
    os.chmod(tmp, 0o644)
    os.replace(tmp, OUT)


def main():
    last_pings, last_ifaces, last_time = {}, {}, None
    window = collections.defaultdict(lambda: collections.deque(maxlen=WINDOW))
    links = {}
    bgp, bgp_at = [], 0.0
    while True:
        started = time.monotonic()
        now = time.time()

        try:
            current = pings()
        except OSError:
            current = {}
        for host, (sent, answered, seconds) in current.items():
            if host in last_pings:
                d_sent = sent - last_pings[host][0]
                d_answered = answered - last_pings[host][1]
                d_seconds = seconds - last_pings[host][2]
                if d_sent > 0:
                    window[host].append((d_sent, d_answered))
                    kind, label = target_label(host)
                    sent_w = sum(s for s, _ in window[host])
                    answered_w = sum(a for _, a in window[host])
                    links[host] = {
                        "target": label,
                        "kind": kind,
                        "rtt_ms": round(d_seconds / d_answered * 1000, 2) if d_answered > 0 else None,
                        "loss_60s": round(1 - answered_w / sent_w, 4) if sent_w else None,
                    }
        last_pings = current

        ifaces = interfaces()
        rates = []
        if last_time is not None:
            dt = now - last_time
            for iface, (rx, tx) in sorted(ifaces.items()):
                if iface in last_ifaces and dt > 0:
                    rates.append({
                        "name": iface,
                        "rx_bps": round((rx - last_ifaces[iface][0]) * 8 / dt),
                        "tx_bps": round((tx - last_ifaces[iface][1]) * 8 / dt),
                    })
        last_ifaces, last_time = ifaces, now

        if started - bgp_at >= SESSION_EVERY:
            try:
                bgp = sessions()
            except OSError:
                pass
            bgp_at = started

        write({
            "edge": EDGE,
            "time": round(now, 3),
            "links": sorted(links.values(), key=lambda link: (link["kind"], link["target"])),
            "interfaces": rates,
            "sessions": bgp,
        })
        time.sleep(max(0.0, 1.0 - (time.monotonic() - started)))


main()
