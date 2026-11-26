#!/usr/bin/env python3
"""Checks inventory/*.json numbering.

"""

import base64
import ipaddress
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
errors = []


def fail(where, message):
    errors.append(f"{where}: {message}")


def load(name):
    data = json.loads((ROOT / name).read_text())
    return data["inventory"][name.removesuffix(".json")]


def net(where, value, version, length=None):
    try:
        n = ipaddress.ip_network(value)
    except ValueError as e:
        return fail(where, f"{value!r} is not a network ({e})")
    if n.version != version:
        return fail(where, f"{value} is not IPv{version}")
    if length is not None and n.prefixlen != length:
        return fail(where, f"{value} is not a /{length}")
    return n


def addr(where, value, version):
    try:
        a = ipaddress.ip_address(value)
    except ValueError as e:
        return fail(where, f"{value!r} is not an address ({e})")
    if a.version != version:
        return fail(where, f"{value} is not IPv{version}")
    return a


def iface(where, value, version):
    """An interface address with its prefix length, as networkd takes it."""
    if "/" not in str(value):
        return fail(where, f"{value!r} needs a prefix length")
    try:
        i = ipaddress.ip_interface(value)
    except ValueError as e:
        return fail(where, f"{value!r} is not an interface address ({e})")
    if i.version != version:
        return fail(where, f"{value} is not IPv{version}")
    if i.ip == i.network.network_address and i.network.prefixlen < (31 if version == 4 else 127):
        fail(where, f"{value} is the network address")
    return i


def check_fplnet(fp, vieta):
    p = fp["prefixes"]
    aggregate = net("prefixes.aggregate", p["aggregate"], 6, 44)
    edges = net("prefixes.edges", p["edges"], 6, 46)
    site_anycast = net("prefixes.siteAnycast", p["siteAnycast"], 6, 48)
    edge_anycast = net("prefixes.edgeAnycast", p["edgeAnycast"], 6, 48)
    vieta_prefix = net("vieta.prefix", vieta["prefix"], 6, 48)
    if None in (aggregate, edges, site_anycast, edge_anycast, vieta_prefix):
        return
    for name, n in [("edges", edges), ("siteAnycast", site_anycast), ("edgeAnycast", edge_anycast), ("vieta.prefix", vieta_prefix)]:
        if not n.subnet_of(aggregate):
            fail(f"prefixes.{name}", f"{n} is outside {aggregate}")
    a = addr("edgeAnycastAddress", fp["edgeAnycastAddress"], 6)
    if a and a not in edge_anycast:
        fail("edgeAnycastAddress", f"{a} is outside {edge_anycast}")
    ports = fp["exporterPorts"]
    if not all(isinstance(v, int) and 1024 <= v <= 65535 for v in ports.values()) or len(set(ports.values())) != len(ports):
        fail("exporterPorts", f"{ports} are not distinct unprivileged ports")

    routers = fp["routers"]
    seen = {}
    keys = {}
    for name, r in routers.items():
        w = f"routers.{name}"
        if not re.fullmatch(r"(er|gw)\d+-[a-z]{3}\d+", name):
            fail(w, "name is not <role><n>-<site><n> (er1-dus1, gw1-aah1)")
        edge = name.startswith("er")

        own = set()
        loopback = addr(f"{w}.loopback", r["loopback"], 6)
        if edge:
            prefix = net(f"{w}.prefix", r.get("prefix"), 6, 48)
            if prefix and not prefix.subnet_of(edges):
                fail(f"{w}.prefix", f"{prefix} is outside {edges}")
        else:
            prefix = vieta_prefix if name == "gw1-aah1" else None
            if "prefix" in r:
                fail(f"{w}.prefix", "only edges own a /48")
        if loopback and prefix and loopback != prefix.network_address + 1:
            fail(f"{w}.loopback", f"{loopback} is not ::1 of {prefix}")
        # Each edge maps every IPv4 client into its own /96 when it translates a host's service to IPv6;
        # gw1 routes the replies back by it.
        if edge:
            siit = net(f"{w}.siit", r.get("siit"), 6, 96)
            if siit and prefix:
                backbone = ipaddress.ip_network((int(prefix.network_address) + (0x1000 << 64), 52))
                if not siit.subnet_of(prefix):
                    fail(f"{w}.siit", f"{siit} is outside {prefix}")
                elif siit.subnet_of(backbone) or (loopback and loopback in siit):
                    fail(f"{w}.siit", f"{siit} overlaps the backbone block or the loopback")
        elif "siit" in r:
            fail(f"{w}.siit", "only edges translate")
        if loopback:
            own.add(loopback)

        if edge:
            for k in ("city", "provider"):
                if not isinstance(r.get(k), str) or not r[k]:
                    fail(f"{w}.{k}", "every edge names its city and provider (homepage)")

        up = r["uplink"]
        if not re.fullmatch(r"[a-z][a-z0-9-]*", up.get("interface", "")):
            fail(f"{w}.uplink.interface", f"{up.get('interface')!r} is not an interface name")
        if "mac" in up and not re.fullmatch(r"([0-9a-f]{2}:){5}[0-9a-f]{2}", up["mac"]):
            fail(f"{w}.uplink.mac", f"{up['mac']!r} is not a lower-case MAC address")
        for family, version in [("v4", 4), ("v6", 6)]:
            i = iface(f"{w}.uplink.{family}", up[family], version)
            if i:
                own.add(i.ip)
        for ifname, i in r["interfaces"].items():
            if ifname == up["interface"]:
                fail(f"{w}.interfaces.{ifname}", "is the uplink")
            for family, version in [("v4", 4), ("v6", 6)]:
                if family in i:
                    x = iface(f"{w}.interfaces.{ifname}.{family}", i[family], version)
                    if x:
                        own.add(x.ip)

        for a in own:
            if a in seen:
                fail(w, f"{a} is also an address of {seen[a]}")
            seen[a] = name

        key = r["wireguard"]
        try:
            if len(base64.b64decode(key, validate=True)) != 32:
                raise ValueError
        except ValueError:
            fail(f"{w}.wireguard", f"{key!r} is not a WireGuard public key")
        if key in keys:
            fail(f"{w}.wireguard", f"same key as {keys[key]}")
        keys[key] = name

        try:
            ssh = ipaddress.ip_address(r["ssh"])
        except ValueError:
            ssh = fail(f"{w}.ssh", f"{r['ssh']!r} is not an address")
        if ssh and ssh not in own:
            fail(f"{w}.ssh", f"{ssh} is none of the router's addresses")
        dotted = name.replace("-", ".") + ".fplnet.net"
        principals = r["principals"]
        for want in [r["ssh"], name, dotted]:
            if want not in principals:
                fail(f"{w}.principals", f"missing {want}")
        for pr in principals:
            try:
                a = ipaddress.ip_address(pr)
            except ValueError:
                if pr not in (name, dotted):
                    fail(f"{w}.principals", f"{pr} is neither the router's name nor {dotted}")
                continue
            if a not in own:
                fail(f"{w}.principals", f"{pr} is none of the router's addresses")
        if len(set(principals)) != len(principals):
            fail(f"{w}.principals", "has duplicates")

    ports = {}
    for key, link in fp["links"].items():
        w = f"links.{key}"
        ends = key.split("/")
        if len(ends) != 2 or not all(e in routers for e in ends):
            fail(w, "key is not <router>/<router>")
            continue
        a, b = ends
        if not a.startswith("er"):
            fail(w, f"{a} owns no /48; the link's addresses come from the first router's")
            continue
        if sorted(link["addresses"]) != sorted(ends):
            fail(f"{w}.addresses", f"needs exactly {a} and {b}")
            continue
        port = link["port"]
        if not isinstance(port, int) or not 1024 <= port <= 65535:
            fail(f"{w}.port", f"{port!r} is not a port")
        for end in ends:
            if end.startswith("er"):
                if port in ports.get(end, {}):
                    fail(f"{w}.port", f"{end} already listens on {port} for {ports[end][port]}")
                ports.setdefault(end, {})[port] = key
        if b.startswith("gw"):
            gport = link.get("gatewayPort")
            if not isinstance(gport, int) or not 1024 <= gport <= 65535:
                fail(f"{w}.gatewayPort", f"{gport!r} is not a port")
            elif gport in ports.get(b, {}):
                fail(f"{w}.gatewayPort", f"{b} already listens on {gport} for {ports[b][gport]}")
            else:
                ports.setdefault(b, {})[gport] = key
        elif "gatewayPort" in link:
            fail(f"{w}.gatewayPort", "only a link to a gateway has one")
        prefix = ipaddress.ip_network(routers[a]["prefix"])
        # :1000::/52 of the owning edge's /48
        backbone = ipaddress.ip_network((int(prefix.network_address) + (0x1000 << 64), 52))
        x, y = addr(f"{w}.addresses.{a}", link["addresses"][a], 6), addr(f"{w}.addresses.{b}", link["addresses"][b], 6)
        if not (x and y):
            continue
        n = ipaddress.ip_network((x, 64), strict=False)
        if x != n.network_address or y != x + 1:
            fail(w, f"{a} takes ::, {b} ::1 of one /64 (got {x}, {y})")
        if n.network_address not in backbone:
            fail(w, f"{n} is outside {a}'s backbone block {backbone}")
        if b.startswith("gw") and n.network_address != backbone.network_address:
            fail(w, f"a gateway link is {backbone.network_address}/64")
        if b.startswith("er") and n.network_address == backbone.network_address:
            fail(w, f"{backbone.network_address}/64 is the gateway link")
        for e, v in [(a, x), (b, y)]:
            if v in seen:
                fail(w, f"{v} is also an address of {seen[v]}")
            seen[v] = e

    pool = net("vieta.publicServicePool", vieta["publicServicePool"], 6, 64)
    nodes = net("vieta.nodeNetwork", vieta["nodeNetwork"], 6, 64)
    host_udp = {}
    for name, s in fp["siteServices"].items():
        w = f"siteServices.{name}"
        a = addr(f"{w}.address", s["address"], 6)
        if "host" in s:
            h = vieta["hosts"].get(s["host"])
            if not name.endswith(".fplnet.net"):
                fail(w, "a host's service is named in fplnet.net")
            if h is None:
                fail(f"{w}.host", f"{s['host']!r} is not in vieta.hosts")
            elif a and nodes and a != nodes.network_address + int(h["ipv4"].split(".")[3], 16):
                fail(f"{w}.address", f"{s['host']} is at {nodes.network_address}{h['ipv4'].split('.')[3]}")
        else:
            if not name.endswith(".lippok.dev"):
                fail(w, "only lippok.dev names")
            if a and not (a in site_anycast or (pool and a in pool)):
                fail(f"{w}.address", f"{a} is in neither {site_anycast} nor {pool}")
        tcp, udp = s.get("tcp", []), s.get("udp", [])
        if not tcp and not udp:
            fail(w, "needs tcp or udp ports")
        for proto, ports in (("tcp", tcp), ("udp", udp)):
            if not all(isinstance(t, int) and 0 < t < 65536 for t in ports):
                fail(f"{w}.{proto}", f"{ports!r} is not a list of ports")
        if "proxyPort" in s and not (isinstance(s["proxyPort"], int) and s["proxyPort"] not in tcp):
            fail(f"{w}.proxyPort", "must be a port not already in tcp")
        # The edges forward a host's UDP port on their own IPv4, so two hosts cannot share one,
        # and none may take a port the edge uses itself: HTTP/3 on 443, the backbone's WireGuard.
        if "host" in s:
            edge_udp = {443} | {link["port"] for link in fp["links"].values() if "port" in link}
            for port in udp:
                if port in edge_udp:
                    fail(f"{w}.udp", f"{port} is used by the edges themselves")
                if port in host_udp:
                    fail(f"{w}.udp", f"{port} is already forwarded to {host_udp[port]}")
                host_udp[port] = name


def check_vieta(vieta):
    nodes = net("vieta.nodeNetwork", vieta["nodeNetwork"], 6, 64)
    pods = net("vieta.podNetwork", vieta["podNetwork"], 6, 56)
    prefix = net("vieta.prefix", vieta["prefix"], 6, 48)
    pool = net("vieta.publicServicePool", vieta["publicServicePool"], 6, 64)
    for name, n in [("nodeNetwork", nodes), ("podNetwork", pods), ("publicServicePool", pool)]:
        if n and prefix and not n.subnet_of(prefix):
            fail(f"vieta.{name}", f"{n} is outside {prefix}")
    asn = vieta["clusterAsn"]
    if not 4200000000 <= asn <= 4294967294:
        fail("vieta.clusterAsn", f"{asn} is not a private 32-bit ASN")

    addr("vieta.unifiController", vieta["unifiController"], 4)

    site = net("vieta.network", vieta["network"], 4)
    lan = vieta["lan"]
    network = net("vieta.lan.network", lan["network"], 4)
    if site and network and not network.subnet_of(site):
        fail("vieta.lan.network", f"{network} is outside {site}")
    vlan = lan["vlan"]
    if not (isinstance(vlan, int) and 1 <= vlan <= 4094):
        fail("vieta.lan.vlan", f"{vlan!r} is not a VLAN id")
    gateway = addr("vieta.lan.gateway", lan["gateway"], 4)
    lbs = net("vieta.lan.loadBalancers", lan["loadBalancers"], 4)
    if network and gateway and gateway not in network:
        fail("vieta.lan.gateway", f"{gateway} is outside {network}")
    if network and lbs and not lbs.subnet_of(network):
        fail("vieta.lan.loadBalancers", f"{lbs} is outside {network}")
    used = {}
    claim(used, gateway, "vieta.lan.gateway")
    for name, ip in lan["loadBalancerIPs"].items():
        w = f"vieta.lan.loadBalancerIPs.{name}"
        a = addr(w, ip, 4)
        if a and lbs and a not in lbs:
            fail(w, f"{a} is outside {lbs}")
        claim(used, a, w)

    macs, names = {}, {}
    for name, h in vieta["hosts"].items():
        w = f"vieta.hosts.{name}"
        # A Talos node's key is its name in the fplnet.net zone (<key>.k8s.aah1), its v4 octet its v6 address.
        k8s = "k8sNode" in h
        if not re.fullmatch(r"[a-z]+\d+" if k8s else r"[a-z][a-z0-9-]*", name):
            fail(w, "a Talos node is <role><n> (cp1, pi1), another host a lower-case name")
        if k8s and not re.fullmatch(r"talos-[a-z0-9]{3}-[a-z0-9]{3}", h["k8sNode"]):
            fail(f"{w}.k8sNode", f"{h['k8sNode']!r} is not a Talos node name")
        a = addr(f"{w}.ipv4", h["ipv4"], 4)
        if a and network and (a not in network or a in (network.network_address, network.broadcast_address)):
            fail(f"{w}.ipv4", f"{a} is not a host address in {network}")
        if a and lbs and a in lbs:
            fail(f"{w}.ipv4", f"{a} is in the LoadBalancer range {lbs}")
        claim(used, a, w)
        mac = h["mac"]
        if not re.fullmatch(r"([0-9a-f]{2}:){5}[0-9a-f]{2}", mac):
            fail(f"{w}.mac", f"{mac!r} is not a lower-case MAC address")
        elif mac in macs:
            fail(f"{w}.mac", f"same MAC as {macs[mac]}")
        macs[mac] = w
        dns = h["dns"]
        if not re.fullmatch(r"[a-z0-9-]+\.athena", dns):
            fail(f"{w}.dns", f"{dns!r} is not a <name>.athena name")
        elif dns in names:
            fail(f"{w}.dns", f"same name as {names[dns]}")
        names[dns] = w
    return network, used


def claim(used, a, where):
    """One owner per fixed address on the Athena LAN."""
    if not a:
        return
    if a in used:
        fail(where, f"{a} is also {used[a]}")
    used[a] = where


def check_lan(network, used, fp, m):
    """Other sites' fixed addresses on the Athena LAN: gw1-aah1, and Minerva until it moves."""
    if not network:
        return
    # Malformed values were reported by the per-site checks already.
    try:
        for name, r in fp["routers"].items():
            i = ipaddress.ip_interface(r["uplink"]["v4"])
            if i.ip in network:
                if i.network != network:
                    fail(f"routers.{name}.uplink.v4", f"{i} is not on {network}")
                claim(used, i.ip, f"routers.{name}.uplink.v4")
        if ipaddress.ip_network(m["lan"]["network"]) == network:
            claim(used, ipaddress.ip_address(m["pve"]), "minerva.pve")
            claim(used, ipaddress.ip_interface(m["nas"]).ip, "minerva.nas")
    except ValueError:
        pass


def check_minerva(m):
    lan = net("minerva.lan.network", m["lan"]["network"], 4)
    for k in ("gateway", "dns"):
        a = addr(f"minerva.lan.{k}", m["lan"][k], 4)
        if a and lan and a not in lan:
            fail(f"minerva.lan.{k}", f"{a} is outside {lan}")
    pve = addr("minerva.pve", m["pve"], 4)
    nas = iface("minerva.nas", m["nas"], 4)
    for name, a in [("pve", pve), ("nas", nas and nas.ip)]:
        if a and lan and a not in lan:
            fail(f"minerva.{name}", f"{a} is outside {lan}")
    if nas and lan and nas.network != lan:
        fail("minerva.nas", f"{m['nas']} is not on {lan}")
    if pve and nas and pve == nas.ip:
        fail("minerva.nas", "same address as the host")

    # network and hosts: the site LAN in Freiburg; lan, pve and nas: where the box is, Vieta's LAN until the move.
    site = net("minerva.network", m["network"], 4)
    addr("minerva.unifiController", m["unifiController"], 4)
    addr("minerva.fritzbox", m["fritzbox"], 4)
    seen = {}
    for name, h in m["hosts"].items():
        w = f"minerva.hosts.{name}"
        if not re.fullmatch(r"[a-z][a-z0-9-]*", name):
            fail(w, "not a lower-case name")
        a = addr(f"{w}.ipv4", h["ipv4"], 4)
        if a and site and a not in site:
            fail(f"{w}.ipv4", f"{a} is outside {site}")
        if a in seen:
            fail(f"{w}.ipv4", f"{a} is also {seen[a]}")
        seen[a] = w
        if not re.fullmatch(r"[a-z0-9-]+\.athena", h["dns"]):
            fail(f"{w}.dns", f"{h['dns']!r} is not a <name>.athena name")


def check_prefixes(fp, vieta, m):
    """No two of our blocks overlap; the rest of each block's shape is checked with its site."""
    def quiet(v):
        try:
            return ipaddress.ip_network(v)
        except ValueError:
            return None
    p = fp["prefixes"]
    aggregate = quiet(p["aggregate"])
    minerva = net("minerva.prefix", m["prefix"], 6, 48)
    if minerva and aggregate and not minerva.subnet_of(aggregate):
        fail("minerva.prefix", f"{minerva} is outside {aggregate}")
    blocks = [(f"prefixes.{k}", quiet(p[k])) for k in ("edges", "edgeAnycast", "siteAnycast")]
    blocks += [("vieta.prefix", quiet(vieta["prefix"])), ("minerva.prefix", minerva)]
    blocks = [(k, b) for k, b in blocks if b]
    for i, (k, b) in enumerate(blocks):
        for k2, b2 in blocks[i + 1:]:
            if b.overlaps(b2):
                fail(k, f"{b} overlaps {k2} {b2}")


def main():
    try:
        fp, vieta, minerva = load("fplnet.json"), load("vieta.json"), load("minerva.json")
        network, used = check_vieta(vieta)
        check_fplnet(fp, vieta)
        check_minerva(minerva)
        check_prefixes(fp, vieta, minerva)
        check_lan(network, used, fp, minerva)
    except (KeyError, TypeError, AttributeError, json.JSONDecodeError) as e:
        fail("inventory", f"malformed: {type(e).__name__} {e}")
    for e in errors:
        print(e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
