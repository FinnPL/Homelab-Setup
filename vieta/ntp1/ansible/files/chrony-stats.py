"""chrony's NTP server statistics as node_exporter textfile metrics.

chrony answers `serverstats` and `clients` only on its Unix socket, which only root and
_chrony can open, so this runs as _chrony, apart from gpsdo. Clients inside the site network
get one series each (named from the inventory); everyone else is summed, so a public server
cannot grow a series per address. To still see a single abuser, every client, site or not, is
ranked by its requests over the last five minutes, and the busiest few get a series by address.
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
    """(address, ntp packets, ntp dropped, log2 interval, seconds since the last request)."""
    rows = []
    for line in chronyc("-c", "clients").splitlines():
        f = line.split(",")
        if len(f) >= 6 and f[1].isdigit() and int(f[1]) > 0:
            rows.append((f[0], int(f[1]), int(f[2]), int(f[3]), int(f[5])))
    return rows


class TopTalkers:
    """Requests per client over the last TOP_WINDOW_S, from deltas of chrony's per-client counters.

    The first run only takes a baseline. A record chrony evicted and recreated (counter went
    down) counts from zero again.
    """

    def __init__(self):
        self.last, self.last_time = None, None
        self.window = collections.deque()  # (start, end, {address: (packets, dropped)})

    def update(self, rows, now):
        current = {address: (packets, dropped) for address, packets, dropped, _, _ in rows}
        if self.last is not None:
            delta = {}
            for address, (packets, dropped) in current.items():
                p0, d0 = self.last.get(address, (0, 0))
                if packets < p0:
                    p0, d0 = 0, 0
                if packets > p0:
                    delta[address] = (packets - p0, max(0, dropped - d0))
            self.window.append((self.last_time, now, delta))
        self.last, self.last_time = current, now
        while self.window and now - self.window[0][1] > TOP_WINDOW_S:
            self.window.popleft()

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


def render(stats, rows, top, site, names, now):
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
    active = {"site": 0, "other": 0}
    other_packets = other_dropped = other_records = 0
    for address, packets, dropped, interval, ago in rows:
        try:
            in_site = ipaddress.ip_address(address) in site
        except ValueError:
            continue
        seen = ago != NEVER
        if seen and ago < ACTIVE_S:
            active["site" if in_site else "other"] += 1
        if not in_site:
            other_packets, other_dropped, other_records = other_packets + packets, other_dropped + dropped, other_records + 1
            continue
        labels = f'client="{address}"' + (f',name="{label_value(names[address])}"' if address in names else "")
        series["chrony_client_ntp_packets_total"].append(f"{{{labels}}} {packets}")
        series["chrony_client_ntp_dropped_total"].append(f"{{{labels}}} {dropped}")
        if interval != NO_INTERVAL:
            series["chrony_client_request_interval_seconds"].append(f"{{{labels}}} {2.0 ** interval:g}")
        if seen:
            series["chrony_client_last_request_timestamp_seconds"].append(f"{{{labels}}} {now - ago:.0f}")
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
    lines += [f'chrony_clients_active{{scope="{scope}"}} {n}' for scope, n in active.items()]
    lines += ["# HELP chrony_other_clients_records Client log records of clients outside the site network.",
              "# TYPE chrony_other_clients_records gauge", f"chrony_other_clients_records {other_records}",
              "# HELP chrony_other_clients_ntp_packets Requests held in those records (records age out, so not a counter).",
              "# TYPE chrony_other_clients_ntp_packets gauge", f"chrony_other_clients_ntp_packets {other_packets}",
              "# TYPE chrony_other_clients_ntp_dropped gauge", f"chrony_other_clients_ntp_dropped {other_dropped}"]
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
    talkers = TopTalkers()
    while True:
        now = time.time()
        try:
            rows = clients()
            talkers.update(rows, now)
            lines = render(serverstats(), rows, talkers.top(), site, names, now)
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
