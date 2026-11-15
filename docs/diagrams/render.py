#!/usr/bin/env python3
"""Draw the README diagrams from the repo's own data.

    python3 docs/diagrams/render.py

Every diagram is written twice, <name>-light.svg and <name>-dark.svg, and the README picks one
per GitHub theme with <picture>. The traffic diagram is also written into fplnet.net's web root,
in that site's colours. Routers, prefixes, links and cluster nodes come from
inventory/, the Vieta apps from vieta/apps/. Minerva is drawn as built: its
gateway, cluster and deploy rows do not wait for the inventory. Stdlib only, so CI needs nothing but python3.
"""

from __future__ import annotations

import json
import math
import pathlib
import re
from xml.sax.saxutils import escape

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]

# ---------------------------------------------------------------- theme

SANS = '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif'
MONO = 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace'

# ink/rule/bg follow GitHub's own light and dark themes; the role colours follow lippok.dev.
THEMES = {
    "light": {
        "bg": "#ffffff", "ink": "#1f2328", "ink2": "#59636e", "ink3": "#818b98",
        "rule": "#d1d9e0", "surface": "#f6f8fa",
        "fplnet": "#2f5597", "fplnet_tint": "#eef3fb",
        "vieta": "#2c7a4b", "vieta_tint": "#edf6f0",
        "minerva": "#7b4fae", "minerva_tint": "#f5f0fa",
        "vault": "#9a6700", "vault_tint": "#fdf6e3",
    },
    "dark": {
        "bg": "#0d1117", "ink": "#e6edf3", "ink2": "#9198a1", "ink3": "#6e7681",
        "rule": "#3d444d", "surface": "#151b23",
        "fplnet": "#8fabe6", "fplnet_tint": "#121a29",
        "vieta": "#7cc39a", "vieta_tint": "#101f17",
        "minerva": "#c3a3ea", "minerva_tint": "#1b1526",
        "vault": "#d9ab68", "vault_tint": "#1f1a10",
    },
}
# fplnet.net's own tokens (fplnet/nixos/web/fplnet.net/style.css), for the copies served there.
FPLNET_NET = {
    "light": {
        "bg": "#fbfbf9", "ink": "#1d1d1b", "ink2": "#66665f", "ink3": "#8f8f87",
        "rule": "#deded8", "surface": "#f3f3ef",
        "fplnet": "#1f5fbf", "fplnet_tint": "#edf2fb",
        "vieta": "#1e7a3c", "vieta_tint": "#ecf5ef",
        "minerva": "#7b4fae", "minerva_tint": "#f5f0fa",
        "vault": "#9a6200", "vault_tint": "#fbf4e4",
    },
    "dark": {
        "bg": "#141413", "ink": "#e8e8e3", "ink2": "#9b9b93", "ink3": "#6f6f68",
        "rule": "#3a3a36", "surface": "#1b1b1a",
        "fplnet": "#7aa7ff", "fplnet_tint": "#161c28",
        "vieta": "#5cc27d", "vieta_tint": "#142119",
        "minerva": "#c3a3ea", "minerva_tint": "#1d1726",
        "vault": "#e0a640", "vault_tint": "#221c10",
    },
}
ROLES = ("fplnet", "vieta", "minerva", "vault")


def stylesheet(p: dict) -> str:
    out = [
        f"text{{font-family:{SANS};font-size:13.5px;fill:{p['ink']}}}",
        f".mono{{font-family:{MONO}}}",
        ".b{font-weight:600}",
        ".xs{font-size:11px}.s{font-size:12px}.l{font-size:15.5px}.xl{font-size:17px}",
        ".up{letter-spacing:.08em}",
        f".i2{{fill:{p['ink2']}}}.i3{{fill:{p['ink3']}}}",
        f".node{{fill:{p['bg']};stroke:{p['rule']};stroke-width:1}}",
        f".chip{{fill:{p['surface']};stroke:{p['rule']};stroke-width:1}}",
        f".panel{{fill:{p['surface']};stroke:{p['rule']};stroke-width:1}}",
        f".pill{{fill:{p['bg']}}}",
        f".ln{{fill:none;stroke:{p['ink3']};stroke-width:1.4}}",
        f".mk{{fill:{p['ink3']}}}",
        ".dash{stroke-dasharray:5 4}",
        ".thick{stroke-width:2.2}",
        f".lead{{fill:none;stroke:{p['rule']};stroke-width:1;stroke-dasharray:2 4}}",
        f".tree{{fill:none;stroke:{p['ink3']};stroke-width:1.2}}",
        f".ghost{{fill:none;stroke:{p['rule']};stroke-width:1.2;stroke-dasharray:5 4}}",
    ]
    for r in ROLES:
        c, t = p[r], p[f"{r}_tint"]
        out += [
            f".t-{r}{{fill:{c}}}",
            f".panel-{r}{{fill:{t};stroke:{c};stroke-opacity:.45;stroke-width:1}}",
            f".node-{r}{{fill:{p['bg']};stroke:{c};stroke-width:1.3}}",
            f".chip-{r}{{fill:{t};stroke:{c};stroke-opacity:.6;stroke-width:1}}",
            f".pill-{r}{{fill:{t}}}",
            f".ln-{r}{{fill:none;stroke:{c};stroke-width:1.6}}",
            f".mk-{r}{{fill:{c}}}",
            f".dot-{r}{{fill:{c}}}",
        ]
    return "".join(out)


# ---------------------------------------------------------------- text metrics

# Helvetica advance widths (1/1000 em), close enough to the system UI fonts GitHub uses.
_ADV = dict(zip(
    " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",
    [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278]
    + [556] * 10
    + [278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667,
       556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278,
       469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
       556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584],
))
_ADV.update({"·": 278, "→": 1000, "×": 584, "ü": 556, "≤": 584, "…": 1000})


def tw(s: str, size: float = 13, mono: bool = False, bold: bool = False) -> float:
    if mono:
        return len(s) * size * 0.602
    w = sum(_ADV.get(c, 600) for c in s) * size / 1000 * 1.04
    return w * 1.06 if bold else w


# ---------------------------------------------------------------- drawing

class Svg:
    def __init__(self, w: float, h: float, title: str):
        self.w, self.h, self.title, self.parts = w, h, title, []

    def raw(self, s: str) -> None:
        self.parts.append(s)

    def rect(self, x, y, w, h, cls, rx=8):
        self.raw(f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{rx:g}" class="{cls}"/>')

    def text(self, x, y, s, cls="", anchor="start"):
        a = "" if anchor == "start" else f' text-anchor="{anchor}"'
        self.raw(f'<text x="{x:g}" y="{y:g}" class="{cls}"{a}>{escape(s)}</text>')

    def runs(self, x, y, runs, anchor="start"):
        """One line of mixed styles: runs = [(text, cls), ...]."""
        a = "" if anchor == "start" else f' text-anchor="{anchor}"'
        body = "".join(f'<tspan class="{c}">{escape(t)}</tspan>' for t, c in runs)
        self.raw(f'<text x="{x:g}" y="{y:g}" xml:space="preserve"{a}>{body}</text>')

    def path(self, d, cls="ln", arrow: str | None = None):
        m = f' marker-end="url(#ah-{arrow})"' if arrow else ""
        self.raw(f'<path d="{d}" class="{cls}"{m}/>')

    def circle(self, x, y, r, cls):
        self.raw(f'<circle cx="{x:g}" cy="{y:g}" r="{r:g}" class="{cls}"/>')

    def render(self, p: dict, inline: bool = False) -> str:
        marks = "".join(
            f'<marker id="ah-{k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
            f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="{c}"/></marker>'
            for k, c in [("n", "mk")] + [(r, f"mk-{r}") for r in ROLES]
        )
        svg = (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w:g} {self.h:g}" '
            f'width="{self.w:g}" height="{self.h:g}" role="img">'
            f"<title>{escape(self.title)}</title>"
            f"<style>{stylesheet(p)}</style><defs>{marks}</defs>"
            # own background, so a viewer that ignores <picture> still shows readable text
            f'<rect width="100%" height="100%" rx="12" fill="{p["bg"]}"/>'
            + "".join(self.parts)
            + "</svg>\n"
        )
        return inline_styles(svg) if inline else svg


def inline_styles(svg: str) -> str:
    """Turn the <style> rules into presentation attributes.

    fplnet.net sends style-src 'self' on every response, which may also apply to an SVG's own
    <style>; attributes are not styles, so the CSP cannot touch them.
    """
    css = re.search(r"<style>(.*?)</style>", svg, re.S).group(1)
    rules = [(sel.strip(), dict(d.split(":", 1) for d in body.split(";") if d))
             for sel, body in re.findall(r"([^{}]+)\{([^}]*)\}", css)]
    base = dict(rules[0][1])                       # the `text` rule, inherited from the root
    rules = rules[1:]

    def attrs(m: re.Match) -> str:
        names = set(m.group(1).split())
        props: dict[str, str] = {}
        for sel, body in rules:                    # stylesheet order decides, as in CSS
            if sel[1:] in names:
                props.update(body)
        return " ".join(f'{k}="{escape(v, {chr(34): "&quot;"})}"' for k, v in props.items())

    svg = svg.replace(f"<style>{css}</style>", "")
    svg = re.sub(r'class="([^"]*)"', attrs, svg)
    root = " ".join(f'{k}="{escape(v, {chr(34): "&quot;"})}"' for k, v in base.items())
    return svg.replace('role="img">', f'role="img" {root}>', 1)


def ortho(pts, r=8.0) -> str:
    """Polyline through pts with rounded corners."""
    d = f"M{pts[0][0]:g},{pts[0][1]:g}"
    for (x0, y0), (x1, y1), (x2, y2) in zip(pts, pts[1:], pts[2:]):
        def toward(bx, by):
            n = math.hypot(bx - x1, by - y1)
            k = min(r, n / 2) / n if n else 0
            return x1 + (bx - x1) * k, y1 + (by - y1) * k
        ax, ay = toward(x0, y0)
        bx, by = toward(x2, y2)
        d += f" L{ax:g},{ay:g} Q{x1:g},{y1:g} {bx:g},{by:g}"
    return d + f" L{pts[-1][0]:g},{pts[-1][1]:g}"


def chip(s: Svg, x, y, label, cls="chip", tcls="mono s", h=24, pad=9, size=12, mono=True,
         anchor="start", w=None) -> float:
    w = w or tw(label, size, mono, "b" in tcls.split()) + 2 * pad
    if anchor == "middle":
        x -= w / 2
    s.rect(x, y, w, h, cls, rx=6)
    s.text(x + w / 2, y + h / 2 + size * 0.36, label, tcls, "middle")
    return w


def node(s: Svg, cx, y, w, h, lines, cls="node"):
    """A box with centred lines: [(text, cls, size), ...], spaced to fill the box."""
    s.rect(cx - w / 2, y, w, h, cls)
    total = sum(sz * 1.45 for _, _, sz in lines)
    yy = y + (h - total) / 2
    for t, c, sz in lines:
        yy += sz * 1.45
        s.text(cx, yy - sz * 0.38, t, c, "middle")


def pill(s: Svg, cx, cy, label, cls="pill", tcls="s i2", size=12, mono=False):
    w = tw(label, size, mono) + 12
    s.rect(cx - w / 2, cy - 9, w, 18, cls, rx=9)
    s.text(cx, cy + size * 0.36, label, tcls, "middle")


def harrow(s: Svg, x0, x1, y, cls="ln", arrow="n"):
    s.path(f"M{x0:g},{y:g} L{x1 - 1:g},{y:g}", cls, arrow)


# ---------------------------------------------------------------- data

def inventory(name: str) -> dict:
    return json.loads((ROOT / "inventory" / f"{name}.json").read_text())["inventory"][name]


FPLNET = inventory("fplnet")
VIETA = inventory("vieta")
MINERVA = inventory("minerva")

# Not in the inventory: which exchanges each edge sits on.
EDGE_IX = {"er1-dus1": "LocIX", "er1-ams1": "InterIX"}

# Both sites as built: a gateway into the backbone, a Talos cluster, and Minerva's NAS.
# Cluster nodes are the inventory hosts carrying k8sNode.
SITES = [
    {"name": "Vieta", "city": "Aachen", "role": "vieta", "dir": "vieta/", "gw": "gw1-aah1", "hosts": VIETA["hosts"]},
    {"name": "Minerva", "city": "Freiburg", "role": "minerva", "dir": "minerva/", "gw": "gw1-fbg1", "hosts": MINERVA["hosts"],
     "hw": "Ryzen 5 5600GT, 32 GB"},
]


def edges() -> list[tuple[str, dict]]:
    return sorted((n, r) for n, r in FPLNET["routers"].items() if n.startswith("er1-"))


def short_v6(prefix: str) -> str:
    return prefix.replace("2a0c:b641:", "")


def apps() -> list[str]:
    return sorted(p.stem for p in (ROOT / "vieta" / "apps").glob("*.yaml"))


# ---------------------------------------------------------------- 1. sites

def sites() -> Svg:
    W, H = 960, 624
    s = Svg(W, H, "FPLNET edge routers and the two sites, Vieta and Minerva")
    es = edges()
    n = len(es)

    # FPLNET panel
    s.rect(16, 16, W - 32, 214, "panel-fplnet", rx=12)
    s.runs(34, 46, [("FPLNET", "b l t-fplnet"), ("   AS" + str(FPLNET["asn"]) + "   ", "i2"),
                    (FPLNET["prefixes"]["aggregate"], "mono s i2")])
    s.text(W - 34, 46, "fplnet/nixos", "mono s i3", "end")

    nw, nh, ny = 206, 104, 98
    cx = [16 + (W - 32) * (2 * i + 1) / (2 * n) for i in range(n)]
    pos = {name: x for (name, _), x in zip(es, cx)}

    # backbone: neighbours straight, the rest arched over the top
    order = [name for name, _ in es]
    arcs = []
    for key in FPLNET["links"]:
        a, b = key.split("/")
        if a not in pos or b not in pos:
            continue
        ia, ib = sorted((order.index(a), order.index(b)))
        xa, xb = cx[ia], cx[ib]
        if ib - ia == 1:
            s.path(f"M{xa + nw / 2:g},{ny + nh / 2:g} L{xb - nw / 2:g},{ny + nh / 2:g}", "ln-fplnet thick")
        else:
            lift = 42 + 10 * (ib - ia)
            s.path(f"M{xa:g},{ny:g} C{xa:g},{ny - lift:g} {xb:g},{ny - lift:g} {xb:g},{ny:g}", "ln-fplnet thick")
            arcs.append(((xa + xb) / 2, ny - lift * 0.75))
    for x, y in arcs[:1]:
        pill(s, x, y, "WireGuard backbone, iBGP and BFD", "pill-fplnet", "s t-fplnet")

    for (name, r), x in zip(es, cx):
        sub = r["provider"] + (", " + EDGE_IX[name] if name in EDGE_IX else "")
        node(s, x, ny, nw, nh, [
            (name, "mono b l", 15),
            (r["city"], "i2", 13.5),
            (r["prefix"], "mono s i3", 12),
            (sub, "s i2", 12),
        ], "node-fplnet")

    # site panels, mirrored: each gateway sits on its panel's top edge, Apollo and the NAS face each other
    top, ph = 352, 256
    pw = (W - 32 - 16) / 2
    gw_w = 170
    ry = top + 50
    ky = top + 130
    gws = []
    for k, site in enumerate(SITES):
        x0 = 16 + k * (pw + 16)
        role = site["role"]
        s.rect(x0, top, pw, ph, f"panel-{role}", rx=12)
        gx = x0 + 20 + gw_w / 2 if k == 0 else x0 + pw - 20 - gw_w / 2
        gws.append(gx)
        if k == 0:
            s.runs(gx + gw_w / 2 + 18, top + 30, [(site["name"], f"b l t-{role}"), ("   " + site["city"], "i2")])
            s.text(x0 + pw - 18, top + 30, site["dir"], "mono s i3", "end")
        else:
            s.runs(x0 + 18, top + 30, [(site["name"], f"b l t-{role}"), ("   " + site["city"], "i2")])
            s.text(gx - gw_w / 2 - 18, top + 30, site["dir"], "mono s i3", "end")
        s.path(f"M{gx:g},{top + 28:g} L{gx:g},{ky - 1:g}", f"ln-{role}", role)
        s.text(gx + 8, ky - 12, "eBGP", "s i2")

        bx, bw = x0 + 20, pw - 40
        s.rect(bx, ky, bw, 106, f"node-{role}", rx=10)
        knodes = sorted((h for h, v in site["hosts"].items() if "k8sNode" in v), key=lambda h: (h.startswith("pi"), h))
        s.runs(bx + 16, ky + 24, [("Kubernetes", "b"), ("   Talos, Cilium, ArgoCD", "s i2")])
        if knodes:
            s.text(bx + bw - 14, ky + 24, f"{len(knodes)} nodes", "s i3", "end")
            cw, gap = 72, 8
            x = bx + 12
            for h in knodes:
                s.rect(x, ky + 40, cw, 50, f"chip-{role}", rx=7)
                s.text(x + cw / 2, ky + 61, h, "mono b", "middle")
                s.text(x + cw / 2, ky + 78, "Pi 4" if h.startswith("pi") else "NUC VM", "xs i2", "middle")
                x += cw + gap
        else:
            s.text(bx + bw / 2, ky + 64, "Talos VMs on Proxmox", "s i2", "middle")
            s.text(bx + bw / 2, ky + 82, site.get("hw", ""), "xs i3", "middle")

    vx = 16 + pw - 20 - 75
    node(s, vx, ry, 150, 56, [("apollo", "mono b", 13.5), ("Synology NAS", "s i2", 12)], "node")
    nx = 16 + pw + 16 + 20 + 85
    node(s, nx, ry, 170, 56, [("nas", "mono b", 13.5), ("NixOS VM, ZFS mirror", "s i2", 12)], "node-minerva")
    harrow(s, vx + 75, nx - 85, ry + 28, "ln-minerva", "minerva")
    s.text((vx + 75 + nx - 85) / 2, ry + 20, "pull", "s t-minerva", "middle")

    # every gateway has a tunnel to every edge
    gy = top - 28
    for gx in gws:
        for i, x0 in enumerate(cx):
            tx = gx + (i - (n - 1) / 2) * 26
            s.path(f"M{x0:g},{ny + nh:g} C{x0:g},{ny + nh + 90:g} {tx:g},{gy - 80:g} {tx:g},{gy - 1:g}", "ln-fplnet", "fplnet")
    for site, gx in zip(SITES, gws):
        node(s, gx, gy, gw_w, 56, [(site["gw"], "mono b", 13.5), ("NixOS, BIRD", "s i2", 12)], "node-fplnet")
    pill(s, W / 2, (ny + nh + gy) / 2 + 4, "WireGuard tunnels, iBGP", "pill", "s t-fplnet")
    return s


# ---------------------------------------------------------------- 2. delivery

# (group, role, rows); a row is (changed path, workflow, role, steps, lands on).
# Neighbouring rows with the same workflow share one workflow chip.
DELIVERY = [
    ("SITES", None, [
        ("vieta/0{1,2,3}-*", "vieta-deploy", "vieta", ["01 network", "02 infra", "03 services"], "UniFi, Proxmox, Talos"),
        ("minerva/0{2,3}-*", "minerva-deploy", "minerva", ["02 infra", "03 services"], "Proxmox, Talos"),
        ("charts/ + */apps/", "ArgoCD, per site", None, ["ApplicationSet", "sync, prune, self-heal"], "both clusters"),
        ("minerva/nixos", "deploy.sh, by hand", "minerva", ["deploy-rs", "YubiKey login"], "the NAS"),
    ]),
    ("FPLNET", "fplnet", [
        ("fplnet/nixos", "fplnet-deploy", "fplnet", ["lint + eval", "deploy-rs per router", "wait for BGP"], "edges + gateways"),
        ("homepage/", "fplnet-deploy", "fplnet", ["astro build", "rsync to edges", "swap current"], "lippok.dev"),
        ("fplnet/terraform", "fplnet-deploy", "fplnet", ["terraform"], "fplnet.net DNS"),
    ]),
    ("PLATFORM", "vault", [
        ("vault/", "vault-deploy", "vault", ["terraform"], "Vault"),
        ("tailscale/", "tailscale-deploy", None, ["policy tests", "terraform"], "tailnet"),
        ("state-bucket/", "state-bucket-deploy", None, ["terraform"], "S3 state"),
        ("every Monday", "ssh-cert-converge", "vault", ["sign host certs", "assert expiry"], "every SSH host"),
    ]),
]
PR_CHECKS = ["pre-commit", "Trivy", "tflint", "kubeconform + Kyverno", "plan → PR comment", "nix eval"]


def delivery() -> Svg:
    W = 960
    rh, gap = 40, 14
    y0 = 150
    rows = sum(len(r) for _, _, r in DELIVERY)
    H = y0 + rows * rh + (len(DELIVERY) - 1) * gap + 70
    s = Svg(W, H, "From a pull request to the running infrastructure")

    # PR lane
    s.rect(16, 16, W - 32, 62, "panel", rx=12)
    s.text(34, 40, "pull request", "b")
    s.text(34, 58, "plans only", "s i3")
    x = 140
    harrow(s, 122, x - 4, 45)
    for c in PR_CHECKS:
        x += chip(s, x, 33, c) + 8

    # merge
    s.path(f"M70,78 L70,{y0 - 41:g}", "ln thick", "n")
    s.text(80, 104, "merge to main", "s i2")

    cols = {"path": 60, "wf": 240, "steps": 412, "target": 790}
    for k, label in [("path", "CHANGED"), ("wf", "RUNS"), ("steps", "STEPS"), ("target", "LANDS ON")]:
        s.text(cols[k], y0 - 18, label, "xs i3 b up")

    y = y0
    for group, grole, items in DELIVERY:
        gh = len(items) * rh
        s.rect(44, y - 6, W - 60, gh + 4, f"panel-{grole}" if grole == "fplnet" else "panel", rx=10)
        cy = y - 6 + (gh + 4) / 2
        s.raw(f'<text transform="translate(31 {cy:g}) rotate(-90)" text-anchor="middle" '
              f'class="xs b up {f"t-{grole}" if grole else "i2"}">{group}</text>')

        # runs of one workflow share a chip
        spans, i = [], 0
        while i < len(items):
            j = i
            while j + 1 < len(items) and items[j + 1][1] == items[i][1]:
                j += 1
            spans.append((i, j))
            i = j + 1

        for i0, i1 in spans:
            _, wf, role, _, _ = items[i0]
            top, bot = y + i0 * rh + 3, y + i1 * rh + 3 + 24
            w = tw(wf, 12, True, True) + 18
            s.rect(cols["wf"], top, w, bot - top, f"chip-{role}" if role else "chip", rx=6)
            s.text(cols["wf"] + w / 2, (top + bot) / 2 + 4.3, wf, f"mono s b t-{role}" if role else "mono s b", "middle")
            for k in range(i0, i1 + 1):
                my = y + k * rh + 15
                path, _, _, steps, target = items[k]
                ghost = path.startswith("every")
                pw = chip(s, cols["path"], my - 12, path, "ghost" if ghost else "chip", "s i2" if ghost else "mono s", mono=not ghost)
                harrow(s, cols["path"] + pw + 4, cols["wf"] - 4, my)
                harrow(s, cols["wf"] + w + 4, cols["steps"] - 4, my)
                x = cols["steps"]
                for n, st in enumerate(steps):
                    x += chip(s, x, my - 12, st, "node", "s", mono=False)
                    if n < len(steps) - 1:
                        harrow(s, x + 3, x + 17, my)
                        x += 20
                s.path(f"M{x + 8:g},{my:g} L{cols['target'] - 10:g},{my:g}", "lead")
                s.text(cols["target"], my + 4, target, f"b t-{role}" if role else "b")
        y += gh + gap

    fy = y - gap + 14
    s.rect(16, fy, W - 32, 44, "panel-vault", rx=10)
    s.runs(34, fy + 27, [("every deploy job", "b t-vault"),
                         ("   GitHub OIDC token → Vault role bound to main → 20 min token → short-lived certs and keys & Tailscale into the LAN", "s i2")])
    return s


# ---------------------------------------------------------------- 3. traffic

def traffic() -> Svg:
    W = 960
    L = 52
    # three classes of traffic, one label row each, then their lanes
    groups = [
        ("EDGE ANYCAST", "fplnet", short_v6(FPLNET["edgeAnycastAddress"]), 3),
        ("SITE ANYCAST", "vieta", "*.relay.lippok.dev", 2),
        ("LAN", None, "*.lippok.dev", 1),
    ]
    tops, labels, y = [], [], 70
    for name, role, sub, n in groups:
        labels.append((y, name, role, sub))
        y += 18
        for _ in range(n):
            tops.append(y)
            y += L
        y += 8
    H = y + 6
    s = Svg(W, H, "How requests reach the edges and the sites")

    def top(i):
        return tops[i]

    def mid(i):
        return tops[i] + 20

    s.text(20, 40, "INTERNET", "xs b up i3")
    s.rect(270, 16, 430, H - 32, "panel-fplnet", rx=12)
    s.text(286, 40, "FPLNET AS" + str(FPLNET["asn"]), "xs b up t-fplnet")
    s.rect(708, 16, 236, H - 32, "panel-vieta", rx=12)
    s.text(724, 40, "SITES", "xs b up t-vieta")
    for yy, name, role, sub in labels:
        s.runs(24, yy + 6, [(name, f"xs b up t-{role}" if role else "xs b up i2"), ("   " + sub, "mono xs i2")])

    def box(x, w, i0, i1, lines, cls="node", stack=False):
        """A box spanning lanes i0..i1; lines = [(text, cls), ...] centred."""
        y, h = top(i0), top(i1) + 40 - top(i0)
        if stack:  # one per edge
            for k in (2, 1):
                s.rect(x + 4 * k, y - 4 * k, w, h, cls, rx=7)
        s.rect(x, y, w, h, cls, rx=7)
        yy = y + h / 2 - (len(lines) - 1) * 7.5 + 4
        for t, c in lines:
            s.text(x + w / 2, yy, t, c, "middle")
            yy += 15

    anycast = short_v6(FPLNET["prefixes"]["siteAnycast"])
    clients = [
        ("fplnet.net", "HTTP/3 over UDP"),
        ("fplnet.net", "HTTPS over TCP"),
        ("lippok.dev", "HTTPS"),
        ("*.relay", "IPv4 to any edge"),
        ("*.relay", f"IPv6 to {anycast}"),
        ("*.lippok.dev", "on the LAN"),
    ]
    for i, (name, sub) in enumerate(clients):
        box(24, 118, i, i, [(name, "mono s b"), (sub, "xs i2")])

    relays = [n.replace(".lippok.dev", "") for n in sorted(FPLNET["siteServices"])]
    box(160, 94, 2, 2, [("Cloudflare", "s b"), ("proxy and cache", "xs i2")])
    box(290, 88, 1, 3, [("HAProxy", "s b"), ("TCP 443", "xs i2"), ("routes by SNI", "xs i2")], "node-fplnet", True)
    box(404, 88, 0, 2, [("nginx", "s b"), ("TLS, HTTP/3", "xs i2"), ("static sites", "xs i2")], "node-fplnet", True)
    box(518, 166, 1, 1, [("looking glass", "s b"), ("bird-lg-go, BIRD", "xs i2")], "node-fplnet", True)
    box(518, 74, 3, 4, [("WireGuard", "s b"), ("backbone", "xs i2")])
    box(610, 76, 3, 4, [("gw1-aah1", "mono xs b"), ("gw1-fbg1", "mono xs b"), ("port allowlist", "xs i2")], "node-fplnet")
    box(722, 210, 3, 4, [("relay services", "s b")] + [(r, "mono xs") for r in relays] + [("Cilium BGP, one /128 each", "xs i2")], "node-vieta")
    box(722, 210, 5, 5, [("Gateway (Envoy)", "s b"), ("LAN VIP, HTTPRoute", "xs i2")], "node-vieta")

    f = ("ln-fplnet", "fplnet")
    harrow(s, 142, 403, mid(0), *f)
    pill(s, 216, mid(0), "UDP 443", "pill", "xs i2")
    harrow(s, 142, 289, mid(1), *f)
    harrow(s, 388, 403, mid(1))
    harrow(s, 502, 517, mid(1))
    harrow(s, 142, 159, mid(2))
    harrow(s, 254, 289, mid(2), *f)
    harrow(s, 388, 403, mid(2))
    harrow(s, 142, 289, mid(3), *f)
    harrow(s, 388, 517, mid(3))
    pill(s, 452, mid(3), "PROXY v2", "pill-fplnet", "xs i2")
    harrow(s, 142, 517, mid(4), *f)
    m34 = (mid(3) + mid(4)) / 2
    harrow(s, 592, 609, m34)
    harrow(s, 686, 721, m34, "ln-vieta", "vieta")
    s.path(f"M142,{mid(5):g} L721,{mid(5):g}", "ln-vieta dash", "vieta")
    pill(s, 440, mid(5), "Cilium L2 on the LAN, no edge", "pill", "xs i2")
    return s


# ---------------------------------------------------------------- 4. Vieta stack

APP_GROUPS = [
    ("GitOps", ["argocd", "namespaces"]),
    ("Platform", ["cnpg", "crossplane", "local-path-provisioner"]),
    ("Security", ["network-policies", "kyverno-operator", "kyverno", "tetragon"]),
    ("Network", ["dns", "gateway-external-routes", "site-data", "tailscale"]),
    ("Observability", ["kube-prometheus-stack", "loki", "alloy"]),
    ("Apps", ["authentik", "gatus", "it-tools"]),
]

STACK = [
    ("vieta/03-services", "terraform + helm",
     ["Cilium", "Gateway API", "cert-manager", "csi-driver-nfs", "External Secrets", "ArgoCD", "Cloudflare DNS"]),
    ("vieta/02-infrastructure", "terraform + ansible",
     ["Talos control plane (VM)", "Talos DB worker (VM)", "3 × Talos on Pi 4", "gw1-aah1 (LXC)", "nfs (LXC)", "win (VM)"]),
    ("vieta/01-network", "terraform",
     ["VLAN 20 Athena", "zone firewall", "DHCP + local DNS"]),
    ("vieta/physical-setup.md", "hardware",
     ["Intel NUC (Proxmox)", "3 × Raspberry Pi 4", "UCG Ultra", "USW Flex 2.5G", "USW Ultra", "JetKVM"]),
]


def stack() -> Svg:
    W = 960
    have = set(apps())
    groups = [(g, [a for a in names if a in have]) for g, names in APP_GROUPS]
    known = {a for _, names in groups for a in names}
    if have - known:
        groups.append(("Other", sorted(have - known)))
    groups = [(g, names) for g, names in groups if names]

    gx, bx = 16, 222
    ah = 30 * len(groups) + 30
    H = 16 + ah + 12 + len(STACK) * 58 + 16
    s = Svg(W, H, "Vieta from hardware to applications")

    # apps band
    y = 16
    s.rect(bx, y, W - 16 - bx, ah, "panel-vieta", rx=12)
    s.text(gx, y + 26, "charts/", "mono b t-vieta")
    s.text(gx, y + 44, "+ vieta/apps/", "mono s t-vieta")
    s.text(gx, y + 62, f"ArgoCD, {len(have)} apps", "s i2")
    yy = y + 16
    for g, names in groups:
        s.text(bx + 18, yy + 16, g, "s b i2")
        x = bx + 112
        for a in names:
            x += chip(s, x, yy + 1, a, "node", "mono s", pad=8) + 5
        yy += 30
    # hand-off
    hy = y + ah
    s.path(f"M{bx + 60:g},{hy + 12:g} L{bx + 60:g},{hy + 1:g}", "ln-vieta", "vieta")
    s.text(bx + 70, hy + 10, "root app hands off to GitOps", "xs i2")

    y = hy + 12
    for k, (owner, tool, items) in enumerate(STACK):
        y += 6
        hw = owner.endswith(".md")
        s.rect(bx, y, W - 16 - bx, 46, "panel" if not hw else "ghost", rx=10)
        s.text(gx, y + 20, owner, "mono s b" + ("" if not hw else " i2"))
        s.text(gx, y + 37, tool, "s i3")
        x = bx + 16
        for it in items:
            x += chip(s, x, y + 11, it, "node", "s", mono=False) + 8
        if k < len(STACK) - 1:
            s.path(f"M{bx + 60:g},{y + 58:g} L{bx + 60:g},{y + 47:g}", "ln", "n")
        y += 52
    return s


# ---------------------------------------------------------------- 5. trust

def trust() -> Svg:
    W, H = 960, 330
    s = Svg(W, H, "Where credentials come from")

    def ident(y, t1, t2, role=None):
        s.rect(16, y, 210, 54, f"node-{role}" if role else "node", rx=8)
        s.text(32, y + 23, t1, "b")
        s.text(32, y + 41, t2, "s i2")

    ident(30, "GitHub Actions job", "OIDC: repo, workflow, ref")
    ident(110, "External Secrets", "ServiceAccount token")
    ident(246, "Admin", "YubiKey, FIDO2", "minerva")

    vx, vy, vw, vh = 300, 22, 250, 176
    s.rect(vx, vy, vw, vh, "panel-vault", rx=12)
    s.text(vx + 18, vy + 28, "Vault", "b l t-vault")
    s.text(vx + vw - 18, vy + 28, "vault/", "mono s i3", "end")
    s.text(vx + 18, vy + 58, "github-actions", "mono s b")
    s.text(vx + 18, vy + 76, "deploy roles: main only", "s i2")
    s.text(vx + 18, vy + 92, "plan roles: any ref, read only", "s i2")
    s.text(vx + 18, vy + 124, "<site>-cluster", "mono s b")
    s.text(vx + 18, vy + 142, "one mount per cluster", "s i2")

    s.path(ortho([(226, 57), (262, 57), (262, 76), (vx - 1, 76)]), "ln-vault", "vault")
    s.text(236, 50, "20 min", "xs i2")
    s.path(ortho([(226, 137), (262, 137), (262, 142), (vx - 1, 142)]), "ln-vault", "vault")

    issued = [
        ("ssh-client-signer", "SSH client cert per run"),
        ("ssh-host-signer", "host certs, checked by CI"),
        ("pki-talos, pki-k8s", "cluster client certs, hours"),
        ("aws", "STS keys for Terraform state"),
        ("kv", "secrets, synced by ESO"),
    ]
    ix = 620
    for i, (mount, what) in enumerate(issued):
        y = 22 + i * 36
        w = chip(s, ix, y + 2, mount, "chip-vault", "mono s b")
        s.text(ix + w + 10, y + 18, what, "s i2")
        s.path(ortho([(vx + vw, vy + vh / 2), (590, vy + vh / 2), (590, y + 14), (ix - 1, y + 14)], 6), "ln-vault", "vault")

    # the NAS sits outside Vault on purpose
    s.rect(ix, 246, 324, 54, "node-minerva", rx=8)
    s.text(ix + 16, 269, "nas", "mono b")
    s.text(ix + 16, 287, "YubiKey-only SSH", "s i2")
    s.path(f"M226,273 L{ix - 1:g},273", "ln-minerva", "minerva")
    pill(s, 430, 273, "the key never leaves the YubiKey", "pill", "s i2")
    return s


# ---------------------------------------------------------------- 6. repository

# (group, role, entries); an entry is (name, role, description, children). Same groups as delivery.
REPO = [
    ("SHARED", None, [
        ("inventory/", None, "addresses, keys and names that Terraform, Nix, Helm and CI all read", []),
    ]),
    ("SITES", None, [
        ("vieta/", "vieta", "Site in Aachen", [
            ("01-network/", "UniFi VLANs, zone firewall, local DNS"),
            ("02-infrastructure/", "Proxmox VMs and LXCs, Talos bootstrap and upgrades"),
            ("03-services/", "Cilium, Gateway API, cert-manager, External Secrets, ArgoCD"),
            ("root/", "the ApplicationSet: one Application per apps/*.yaml"),
            ("apps/", "the charts this site runs"),
        ]),
        ("minerva/", "minerva", "Site in Freiburg", [
            ("02-*/ 03-*/ root/ apps/", "same as vieta/"),
            ("nas-infrastructure/", "the NAS VM, applied by hand with a YubiKey"),
            ("nixos/", "NixOS VMs: the NAS and the router"),
        ]),
        ("charts/", None, "wrapper charts for both sites: a pinned upstream chart + values-<site>.yaml", []),
    ]),
    ("FPLNET", "fplnet", [
        ("fplnet/", "fplnet", "AS" + str(FPLNET["asn"]), [
            ("nixos/", "one flake for the edge routers and gw1-aah1: BIRD, WireGuard, HAProxy, nginx"),
            ("terraform/", "fplnet.net zone and forward-confirmed reverse DNS"),
            ("scripts/", "deploy-rs rollout with BGP session checks"),
        ]),
        ("homepage/", "fplnet", "lippok.dev (Astro), built in CI and served by the edges", []),
    ]),
    ("PLATFORM", "vault", [
        ("vault/", "vault", "Vault auth methods, roles, policies, secret engines", []),
        ("tailscale/", None, "tailnet policy and federated CI identities", []),
        ("state-bucket/", None, "the S3 bucket behind every Terraform state", []),
    ]),
]


def repo() -> Svg:
    W = 960
    rh, pad, gap = 26, 8, 8
    trunk, kid = 30, 58          # x of the root and second-level tree lines
    name_x, kid_x, desc_x = 46, 74, 330

    rows = sum(1 + len(c) for _, _, es in REPO for _, _, _, c in es)
    H = 58 + rows * rh + len(REPO) * (2 * pad + gap) + 6
    s = Svg(W, H, "The repository as a tree")

    s.text(18, 32, "Homelab-Setup/", "mono b")
    y = 52
    tops = []          # (mid y of every top-level entry)
    for group, grole, entries in REPO:
        n = sum(1 + len(c) for _, _, _, c in entries)
        s.rect(16, y, W - 32, n * rh + 2 * pad, "panel-fplnet" if grole == "fplnet" else "panel", rx=10)
        s.text(W - 30, y + pad + 17, group, f"xs b up t-{grole}" if grole else "xs b up i3", "end")
        y += pad
        for name, role, desc, children in entries:
            mid = y + rh / 2
            tops.append(mid)
            s.text(name_x, mid + 4.5, name, f"mono s b t-{role}" if role else "mono s b")
            end = name_x + tw(name, 12, True, True)
            s.path(f"M{end + 10:g},{mid:g} L{desc_x - 10:g},{mid:g}", "lead")
            s.text(desc_x, mid + 4.5, desc, "s i2")
            y += rh
            kids = []
            for cname, cdesc in children:
                cm = y + rh / 2
                kids.append(cm)
                s.text(kid_x, cm + 4.5, cname, "mono s")
                cend = kid_x + tw(cname, 12, True)
                s.path(f"M{cend + 10:g},{cm:g} L{desc_x - 10:g},{cm:g}", "lead")
                s.text(desc_x, cm + 4.5, cdesc, "s i2")
                y += rh
            if kids:
                s.path(f"M{kid:g},{mid + 9:g} L{kid:g},{kids[-1] - 6:g}", "tree")
                for cm in kids:
                    s.path(f"M{kid:g},{cm - 6:g} Q{kid:g},{cm:g} {kid + 6:g},{cm:g} L{kid_x - 5:g},{cm:g}", "tree")
        y += pad + gap

    s.path(f"M{trunk:g},40 L{trunk:g},{tops[-1] - 6:g}", "tree")
    for m in tops:
        s.path(f"M{trunk:g},{m - 6:g} Q{trunk:g},{m:g} {trunk + 6:g},{m:g} L{name_x - 5:g},{m:g}", "tree")
    return s


# ---------------------------------------------------------------- main

DIAGRAMS = {"sites": sites, "delivery": delivery, "repo": repo, "traffic": traffic, "stack": stack, "trust": trust}


# Diagrams also served elsewhere: name -> (directory, palette).
SERVED = {"traffic": (ROOT / "fplnet" / "nixos" / "web" / "fplnet.net", FPLNET_NET)}


def main() -> None:
    for name, build in DIAGRAMS.items():
        svg = build()
        for theme, p in THEMES.items():
            (HERE / f"{name}-{theme}.svg").write_text(svg.render(p))
        if name in SERVED:
            where, palette = SERVED[name]
            for theme, p in palette.items():
                (where / f"{name}-{theme}.svg").write_text(svg.render(p, inline=True))


if __name__ == "__main__":
    main()
