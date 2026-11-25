"""chrony's NTP server statistics as node_exporter textfile metrics.

chrony answers `serverstats` and `clients` only on its Unix socket, which only root and
_chrony can open, so this runs as _chrony, apart from gpsdo. Clients inside the site network
get one series each (named from the inventory); everyone else is summed, so a public server
cannot grow a series per address. To still see a single abuser, every client, site or not, is
ranked by its requests over the last five minutes, and the busiest few get a series by address.

Each run asks chrony only for the clients that sent something since the last run and resets
their counters (`clients -r -p 1`, filtered inside chronyd), so every row is a delta and the
totals live here. A full dump of the client log cost showed up as noise in the clock.
"""

import collections
import ipaddress
import json
import os
import subprocess
import time

CONFIG = "/etc/ntp1/chrony-stats.json"
METRICS = "/run/ntp1-chrony-stats/chrony-server.prom"
INTERVAL_S = 15
NEVER = 4294967295                      # chrony's "no request yet" for the last-request age
NO_INTERVAL = 127                       # chrony's "unknown" for the log2 request interval
ACTIVE_S = 3600                         # a client counts as active for an hour after its last request
TOP_N = 10                              # busiest clients exported by address
TOP_WINDOW_S = 300

COUNTERS = {
    "NTP packets received": "chrony_server_ntp_packets_received_total",
    "NTP packets dropped": "chrony_server_ntp_packets_dropped_total",
    "Command packets received": "chrony_server_command_packets_received_total",
    "Command packets dropped": "chrony_server_command_packets_dropped_total",
    "Client log records dropped": "chrony_server_client_log_records_dropped_total",
    "Interleaved NTP packets": "chrony_server_interleaved_ntp_packets_total",
}
TIMESTAMPS = {                          # label -> (metric, source)
    f"NTP {source} {d} timestamps": (f"chrony_server_{d.lower()}_timestamps_total", source)
    for source in ("daemon", "kernel", "hardware") for d in ("RX", "TX")
}


def chronyc(*args):
    return subprocess.run(["chronyc", "-n", *args], capture_output=True, text=True,
                          timeout=5, check=True).stdout


def serverstats():
    values = {}
    for line in chronyc("serverstats").splitlines():
        label, _, value = line.partition(":")
        if value.strip().isdigit():
            values[label.strip()] = int(value)
    return values


def clients():
    """Clients with requests since the last call, counters reset by it:
    (address, ntp packets, ntp dropped, log2 interval, seconds since the last request)."""
    rows = []
    for line in chronyc("-c", "clients", "-r", "-p", "1").splitlines():
        f = line.split(",")
        if len(f) >= 6 and f[1].isdigit() and int(f[1]) > 0:
            rows.append((f[0], int(f[1]), int(f[2]), int(f[3]), int(f[5])))
    return rows


class Totals:
    """What the reset counters add up to: per site client, the rest summed, and when each was last seen.

    The first run returns everything chrony counted before (since its start, or since the last
    reset of an earlier run), so it seeds the totals but not the request rates.
    """

    def __init__(self, site):
        self.site = site
        self.first = True
        self.last_time = None
        self.window = collections.deque()  # (start, end, {address: (packets, dropped)})
        self.site_clients = {}             # address -> [packets, dropped, log2 interval, last request]
        self.other = [0, 0]
        self.seen = {}                     # address -> (in site, last request)

    def update(self, rows, now):
        delta = {}
        for address, packets, dropped, interval, ago in rows:
            try:
                in_site = ipaddress.ip_address(address) in self.site
            except ValueError:
                continue
            last = now - ago if ago != NEVER else None
            if in_site:
                c = self.site_clients.setdefault(address, [0, 0, NO_INTERVAL, None])
                c[0] += packets
                c[1] += dropped
                c[2] = interval
                c[3] = last if last is not None else c[3]
            else:
                self.other[0] += packets
                self.other[1] += dropped
            if last is not None:
                self.seen[address] = (in_site, last)
            delta[address] = (packets, dropped)
        if not self.first:
            self.window.append((self.last_time, now, delta))
        self.first, self.last_time = False, now
        while self.window and now - self.window[0][1] > TOP_WINDOW_S:
            self.window.popleft()
        self.seen = {a: v for a, v in self.seen.items() if now - v[1] < ACTIVE_S}

    def active(self):
        n = {"site": 0, "other": 0}
        for in_site, _ in self.seen.values():
            n["site" if in_site else "other"] += 1
        return n

    def top(self):
        """[(address, requests per minute, dropped per minute)] of the TOP_N busiest clients."""
        if not self.window:
            return []
        span = self.window[-1][1] - self.window[0][0]
        sums = collections.defaultdict(lambda: [0, 0])
        for _, _, delta in self.window:
            for address, (packets, dropped) in delta.items():
                sums[address][0] += packets
                sums[address][1] += dropped
        ranked = sorted(sums.items(), key=lambda item: item[1][0], reverse=True)[:TOP_N]
        return [(address, p * 60 / span, d * 60 / span) for address, (p, d) in ranked]


def label_value(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def client_labels(address, site, names):
    try:
        scope = "site" if ipaddress.ip_address(address) in site else "other"
    except ValueError:
        scope = "other"
    labels = f'client="{label_value(address)}",scope="{scope}"'
    return labels + (f',name="{label_value(names[address])}"' if address in names else "")


def render(stats, totals, top, site, names):
    lines = []
    for label, name in COUNTERS.items():
        if label in stats:
            lines += [f"# TYPE {name} counter", f"{name} {stats[label]}"]
    for name in sorted({m for m, _ in TIMESTAMPS.values()}):
        lines.append(f"# TYPE {name} counter")
        lines += [f'{name}{{source="{source}"}} {stats[label]}'
                  for label, (m, source) in TIMESTAMPS.items() if m == name and label in stats]

    per_client = {"chrony_client_ntp_packets_total": "counter", "chrony_client_ntp_dropped_total": "counter",
                  "chrony_client_request_interval_seconds": "gauge",
                  "chrony_client_last_request_timestamp_seconds": "gauge"}
    series = {name: [] for name in per_client}
    for address, (packets, dropped, interval, last) in sorted(totals.site_clients.items()):
        labels = f'client="{address}"' + (f',name="{label_value(names[address])}"' if address in names else "")
        series["chrony_client_ntp_packets_total"].append(f"{{{labels}}} {packets}")
        series["chrony_client_ntp_dropped_total"].append(f"{{{labels}}} {dropped}")
        if interval != NO_INTERVAL:
            series["chrony_client_request_interval_seconds"].append(f"{{{labels}}} {2.0 ** interval:g}")
        if last is not None:
            series["chrony_client_last_request_timestamp_seconds"].append(f"{{{labels}}} {last:.0f}")
    for name, kind in per_client.items():
        if series[name]:
            lines.append(f"# TYPE {name} {kind}")
            lines += [name + s for s in series[name]]

    lines += ["# HELP chrony_top_client_requests_per_minute NTP requests per minute over the last 5 minutes, busiest clients only.",
              "# TYPE chrony_top_client_requests_per_minute gauge"]
    lines += [f"chrony_top_client_requests_per_minute{{{client_labels(a, site, names)}}} {rate:.2f}" for a, rate, _ in top]
    lines += ["# TYPE chrony_top_client_dropped_per_minute gauge"]
    lines += [f"chrony_top_client_dropped_per_minute{{{client_labels(a, site, names)}}} {rate:.2f}" for a, _, rate in top]

    lines += ["# HELP chrony_clients_active Clients with a request in the last hour.",
              "# TYPE chrony_clients_active gauge"]
    lines += [f'chrony_clients_active{{scope="{scope}"}} {n}' for scope, n in totals.active().items()]
    lines += ["# HELP chrony_other_clients_ntp_packets_total Requests from clients outside the site network.",
              "# TYPE chrony_other_clients_ntp_packets_total counter", f"chrony_other_clients_ntp_packets_total {totals.other[0]}",
              "# TYPE chrony_other_clients_ntp_dropped_total counter", f"chrony_other_clients_ntp_dropped_total {totals.other[1]}"]
    return lines


def write(lines):
    tmp = METRICS + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, METRICS)


def main():
    with open(CONFIG) as f:
        config = json.load(f)
    site = ipaddress.ip_network(config["site_network"])
    names = config["names"]
    totals = Totals(site)
    while True:
        now = time.time()
        try:
            totals.update(clients(), now)
            lines = render(serverstats(), totals, totals.top(), site, names)
            ok = 1
        except (subprocess.SubprocessError, OSError) as e:
            print(f"chronyc: {e}", flush=True)
            lines, ok = [], 0
        lines += ["# TYPE chrony_stats_up gauge", f"chrony_stats_up {ok}",
                  "# TYPE chrony_stats_last_run_timestamp_seconds gauge",
                  f"chrony_stats_last_run_timestamp_seconds {now:.0f}"]
        write(lines)
        time.sleep(INTERVAL_S)


if __name__ == "__main__":
    main()
