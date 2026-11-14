// The live network map on the home page. Everything it shows comes from the edges' live.json and
// the sites' site.json; parts that do not exist yet are drawn dashed and say so.
import { EDGES, EDGE_IDS, GW1_AAH1_PREFERENCE, isBackboneIface, isNeighbourSession, networkOf, type EdgeId } from "../lib/net";
import { state, on, want, fresh, sessionTotals, uplinkTotals, fmtRate, fmtNum, esc, NB, NO_DATA, type Live } from "./feed";

const NS = "http://www.w3.org/2000/svg";
const $ = (id: string) => document.getElementById(id)!;
function el(tag: string, attrs: Record<string, string | number> = {}, parent?: Element) {
  const e = document.createElementNS(NS, tag) as SVGGraphicsElement;
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
  if (parent) parent.appendChild(e);
  return e;
}
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

type NodeId = EdgeId | "aah1" | "fbg1" | "vk8s" | "mk8s" | "nas";
const NODES: Record<NodeId, { x: number; y: number; kind: string; name: string; sub: string; planned?: boolean }> = {
  ams1: { x: 170, y: 170, kind: "edge", name: EDGES.ams1.name, sub: EDGES.ams1.city },
  dus1: { x: 500, y: 170, kind: "edge", name: EDGES.dus1.name, sub: EDGES.dus1.city },
  fra1: { x: 830, y: 170, kind: "edge", name: EDGES.fra1.name, sub: EDGES.fra1.city },
  aah1: { x: 300, y: 455, kind: "gateway", name: "gw1.aah1", sub: "Aachen" },
  fbg1: { x: 700, y: 455, kind: "gateway", name: "gw1.fbg1", sub: "Freiburg", planned: true },
  vk8s: { x: 300, y: 570, kind: "cluster", name: "k8s", sub: "" },
  mk8s: { x: 625, y: 570, kind: "cluster", name: "k8s", sub: "", planned: true },
  nas: { x: 785, y: 570, kind: "nas", name: "nas", sub: "ZFS" },
};

const curve = (a: NodeId, b: NodeId) => {
  const A = NODES[a], B = NODES[b], m = (A.y + B.y) / 2;
  return `M${A.x},${A.y} C${A.x},${m} ${B.x},${m} ${B.x},${B.y}`;
};

type Link = { a: NodeId; b: NodeId; d?: string; at?: number; label?: string; local?: boolean; lan?: boolean; planned?: boolean };
const LINKS: Link[] = [
  { a: "ams1", b: "dus1" },
  { a: "dus1", b: "fra1" },
  { a: "ams1", b: "fra1", d: "M170,170 C300,95 700,95 830,170", at: 0.22 },
  ...EDGE_IDS.map((e): Link => ({ a: e, b: "aah1", d: curve(e, "aah1"), at: 0.27 })),
  ...EDGE_IDS.map((e): Link => ({ a: e, b: "fbg1", d: curve(e, "fbg1"), at: 0.27, planned: true })),
  { a: "aah1", b: "fbg1", planned: true },
  { a: "aah1", b: "vk8s", label: "eBGP", local: true },
  { a: "fbg1", b: "mk8s", local: true, planned: true },
  { a: "fbg1", b: "nas", local: true, planned: true },
];
const linkId = (l: Link) => l.a + "-" + l.b;
const isEdge = (id: string): id is EdgeId => id in EDGES;

const gSites = $("g-sites"), gLinks = $("g-links"), gLabels = $("g-labels"), gPkts = $("g-pkts"), gNodes = $("g-nodes");

for (const [x, y, w, h, label, href] of [[180, 395, 240, 212, "Vieta", "/vieta"], [540, 395, 330, 212, "Minerva", "/minerva"]] as const) {
  const g = el("g", { class: "site" }, gSites);
  el("rect", { x, y, width: w, height: h, rx: 10 }, g);
  const a = el("a", { href }, g);
  el("text", { x: x + 2, y: y - 8 }, a).textContent = label;
}

// ---- links
type LinkEl = {
  l: Link; path: SVGGeometryElement; len: number; mid: DOMPoint;
  g?: SVGGElement; rect?: SVGRectElement; text?: SVGTextContentElement;
  pkts: { c: SVGCircleElement; p: number; fwd: boolean; speed: number }[]; acc: number; rate: number; bias: number;
};
const linkEls: Record<string, LinkEl> = {};

function sizeLabel(L: LinkEl) {
  if (!L.text || !L.rect) return;
  const w = Math.max(30, L.text.getComputedTextLength() + 14);
  L.rect.setAttribute("width", String(w));
  L.rect.setAttribute("x", String(L.mid.x - w / 2));
}

for (const l of LINKS) {
  const A = NODES[l.a], B = NODES[l.b];
  const d = l.d ?? `M${A.x},${A.y} L${B.x},${B.y}`;
  const path = el("path", { d, class: "lnk" + (l.planned ? " planned" : "") }, gLinks) as SVGGeometryElement;
  const len = path.getTotalLength();
  const mid = path.getPointAtLength(len * (l.at ?? 0.5));
  const L: LinkEl = { l, path, len, mid, pkts: [], acc: 0, rate: 0, bias: 0.5 };
  if (!l.planned) {
    L.g = el("g", { class: "lbl" }, gLabels) as SVGGElement;
    L.rect = el("rect", { rx: 4, height: 20, y: mid.y - 10 }, L.g) as SVGRectElement;
    L.text = el("text", { x: mid.x, y: mid.y + 4.5, "text-anchor": "middle" }, L.g) as SVGTextContentElement;
    L.text.textContent = l.label ?? "";
  }
  if (!l.local && !l.planned) {
    const hit = el("path", { d, class: "lnk-hit" }, gLinks);
    hit.addEventListener("click", () => select({ link: linkId(l) }));
    L.g!.addEventListener("click", () => select({ link: linkId(l) }));
    L.g!.style.cursor = "pointer";
  }
  linkEls[linkId(l)] = L;
  sizeLabel(L);
}

// ---- nodes
const nodeEls = {} as Record<NodeId, { g: SVGGElement; sub: SVGTextElement; rate: SVGTextElement; third: SVGTextElement }>;
for (const [id, n] of Object.entries(NODES) as [NodeId, (typeof NODES)[NodeId]][]) {
  const big = n.kind === "edge" || n.kind === "gateway";
  const w = big ? 180 : 156, h = big ? 70 : 52;
  const g = el("g", {
    class: "node" + (n.planned ? " planned" : ""), tabindex: 0, role: "button", "aria-label": n.name,
    transform: `translate(${n.x - w / 2},${n.y - h / 2})`,
  }, gNodes) as SVGGElement;
  el("rect", { class: "box", width: w, height: h, rx: 8 }, g);
  el("text", { class: "name", x: 12, y: 21 }, g).textContent = n.name;
  const sub = el("text", { class: "sub", x: w - 12, y: 21, "text-anchor": "end" }, g) as SVGTextElement;
  sub.textContent = n.sub;
  const rate = el("text", { class: "rate", x: 12, y: 40 }, g) as SVGTextElement;
  const third = el("text", { class: "rate dimmed", x: 12, y: 58 }, g) as SVGTextElement;
  if (n.planned) rate.textContent = "not built yet";
  nodeEls[id] = { g, sub, rate, third };
  const act = () => select({ node: id });
  g.addEventListener("click", act);
  g.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); act(); } });
}

// ---- neighbour chips: one per network an edge has external sessions with
const chipRows: Partial<Record<EdgeId, { key: string; g: SVGGElement; chips: { d: SVGCircleElement; sessions: string[] }[] }>> = {};
function neighbours(s: Live) {
  const by = new Map<string, string[]>();
  for (const x of s.sessions.filter(isNeighbourSession)) {
    const n = networkOf(x.name);
    by.set(n, [...(by.get(n) ?? []), x.name]);
  }
  return [...by.entries()];
}
function drawChips(edge: EdgeId, s: Live) {
  const groups = neighbours(s);
  const key = groups.map(([n, ss]) => n + ss.join()).join("|");
  if (chipRows[edge]?.key === key) return chipRows[edge]!;
  chipRows[edge]?.g.remove();
  const E = NODES[edge];
  const g = el("g", { class: "chips-row" }, gNodes) as SVGGElement;
  if (!chipRows[edge]) el("line", { x1: E.x, y1: 70, x2: E.x, y2: E.y - 35, class: "lnk conn" }, gLinks);
  const widths = groups.map(([n]) => n.length * 6.9 + 26);
  const total = widths.reduce((a, b) => a + b, 0) + (groups.length - 1) * 6;
  let x = E.x - total / 2;
  const chips = groups.map(([n, sessions], i) => {
    const c = el("g", { class: "chip", transform: `translate(${x},48)` }, g);
    el("rect", { width: widths[i], height: 22, rx: 5 }, c);
    const d = el("circle", { cx: 10, cy: 11, r: 3.5, class: "st" }, c) as SVGCircleElement;
    el("text", { x: 19, y: 15 }, c).textContent = n;
    c.addEventListener("click", () => select({ node: edge }));
    x += widths[i] + 6;
    return { d, sessions };
  });
  return (chipRows[edge] = { key, g, chips });
}

// ---- measurements
const sessionUp = (edge: EdgeId, name: string) => fresh(edge)?.sessions.find((x) => x.name === name)?.up;
const target = (id: NodeId) => (isEdge(id) ? EDGES[id].name : NODES[id].name);
const sessionFor = (id: NodeId) => (isEdge(id) ? "ibgp_" + id : "ibgp_gw1_" + id);
const ifaceFor = (id: NodeId) => (isEdge(id) ? "wg-er1-" + id : "wg-gw1-" + id);

function measure(a: NodeId, b: NodeId) {
  const out: { from: EdgeId; rtt: number | null; loss: number | null }[] = [];
  for (const [from, to] of [[a, b], [b, a]] as const) {
    if (!isEdge(from)) continue;
    const x = fresh(from)?.links.find((l) => l.target === target(to));
    if (x) out.push({ from, rtt: x.rtt_ms, loss: x.loss_60s });
  }
  return out;
}

const edgeUplinks = (s: Live) => s.interfaces.filter((i) => !isBackboneIface(i.name));
const sum = (xs: { rx_bps: number; tx_bps: number }[]) => xs.reduce((a, i) => ({ rx: a.rx + i.rx_bps, tx: a.tx + i.tx_bps }), { rx: 0, tx: 0 });
const mbit = (v: number) => (v / 1e6).toFixed(v < 1e7 ? 2 : 1);

function gatewayDefault() {
  return GW1_AAH1_PREFERENCE.find((e) => sessionUp(e, "ibgp_gw1_aah1"));
}

const vieta = () => (state.site.ok ? state.site.data?.sites.vieta : undefined);
const minerva = () => (state.site.ok ? state.site.data?.sites.minerva : undefined);
const pct = (f: number) => (f * 100).toFixed(0) + " %";
const tb = (b: number) => (b / 1e12).toFixed(2) + " TB";

// ---- selection and the details card
let selected: { node?: NodeId; link?: string } | null = null;
function select(s: { node?: NodeId; link?: string } | null) {
  const same = s && selected && selected.node === s.node && selected.link === s.link;
  selected = !s || same ? null : s;
  for (const [id, n] of Object.entries(nodeEls)) n.g.classList.toggle("sel", selected?.node === id);
  for (const [id, L] of Object.entries(linkEls)) L.path.classList.toggle("sel", selected?.link === id);
  renderSide(true);
}

const dot = (up: boolean | undefined) => `<span class="dot${up ? "" : " down"}"></span>`;
const ms = (v: number | null | undefined, d = 1) => (v == null ? "" : v.toFixed(d) + " ms");
const lossPct = (v: number | null | undefined) => (v == null ? "" : (v * 100).toFixed(1) + " %");

function edgePanel(id: EdgeId) {
  const n = EDGES[id], s = fresh(id);
  const head = `<h3>${n.name}</h3><div class="sub">${n.city}, ${n.provider}</div>`;
  if (!s) return head + `<p>${NO_DATA}</p>`;
  const up = sum(edgeUplinks(s));
  const sess = s.sessions
    .map((x) => `<tr><td>${dot(x.up)}${esc(x.name)}<br><span class="k">${esc(x.kind)}</span></td><td class="num">${x.prefixes ? fmtNum(x.prefixes) : ""}</td></tr>`)
    .join("");
  const row = (x: Live["links"][number]) => `<tr><td>${esc(x.target)}</td><td class="num">${ms(x.rtt_ms)}</td><td class="num">${lossPct(x.loss_60s)}</td></tr>`;
  const bb = s.links.filter((x) => x.kind === "backbone").map(row).join("");
  const nb = s.links.filter((x) => x.kind !== "backbone").map(row).join("");
  return head + `
    <div class="grp2"><dl class="kv"><dt>announces</dt><dd>${n.prefix}</dd><dt>uplinks in</dt><dd>${fmtRate(up.rx)}</dd><dt>uplinks out</dt><dd>${fmtRate(up.tx)}</dd></dl></div>
    <div class="grp2"><table><thead><tr><th>BGP session</th><th class="num">prefixes</th></tr></thead><tbody>${sess}</tbody></table></div>
    <div class="grp2"><table><thead><tr><th>backbone</th><th class="num">rtt</th><th class="num">loss 60 s</th></tr></thead><tbody>${bb}</tbody></table></div>
    ${nb ? `<div class="grp2"><table><thead><tr><th>neighbour</th><th class="num">rtt</th><th class="num">loss 60 s</th></tr></thead><tbody>${nb}</tbody></table></div>` : ""}`;
}

function linkPanel(L: LinkEl) {
  const m = measure(L.l.a, L.l.b);
  const rows = m.map((x) => `<tr><td>${EDGES[x.from].name}</td><td class="num">${ms(x.rtt, 2)}</td><td class="num">${lossPct(x.loss)}</td></tr>`).join("");
  return `
    <h3>${target(L.l.a)} ↔ ${target(L.l.b)}</h3>
    <div class="sub">WireGuard, iBGP, BFD</div>
    <div class="grp2">${rows ? `<table><thead><tr><th>measured from</th><th class="num">rtt</th><th class="num">loss 60 s</th></tr></thead><tbody>${rows}</tbody></table>` : `<p>${NO_DATA}</p>`}</div>
    <div class="grp2"><dl class="kv"><dt>traffic</dt><dd>${m.length ? fmtRate(L.rate) : NO_DATA}</dd></dl></div>`;
}

function vietaPanel() {
  const v = vieta();
  const via = gatewayDefault();
  const rows = EDGE_IDS.map((e) => {
    const r = measure(e, "aah1")[0];
    return `<tr><td>${dot(sessionUp(e, "ibgp_gw1_aah1"))}${EDGES[e].name}</td><td class="num">${r ? ms(r.rtt) : ""}</td></tr>`;
  }).join("");
  const site = v
    ? `<dt>nodes</dt><dd>${v.nodes_ready}/${v.nodes} ready</dd>
       <dt>apps</dt><dd>${v.apps_synced}/${v.apps} synced, ${v.apps_healthy}/${v.apps} healthy</dd>
       <dt>pods</dt><dd>${v.pods_running} running</dd>
       <dt>cpu</dt><dd>${pct(v.cpu_used)}</dd>
       <dt>memory</dt><dd>${pct(v.memory_used)}</dd>`
    : `<dt>cluster</dt><dd>${NO_DATA}</dd>`;
  return `
    <h3>Vieta<a href="/vieta">site →</a></h3>
    <div class="sub">Aachen, gw1.aah1</div>
    <div class="grp2"><dl class="kv">
      <dt>prefix</dt><dd>2a0c:b641:f94::/48</dd>
      <dt>default via</dt><dd>${via ? EDGES[via].name : NO_DATA}</dd>
      ${site}
    </dl></div>
    <div class="grp2"><table><thead><tr><th>iBGP + BFD to</th><th class="num">rtt</th></tr></thead><tbody>${rows}
      <tr><td>gw1.fbg1<br><span class="k">site link</span></td><td class="num">${NB}</td></tr></tbody></table></div>`;
}

function nasPanel() {
  const m = minerva();
  return `
    <h3>nas<a href="/minerva#backups">backups →</a></h3>
    <div class="sub">Minerva</div>
    <div class="grp2"><dl class="kv">
      <dt>pool</dt><dd>${m?.nas_pool_online == null ? NO_DATA : m.nas_pool_online ? "nas, online" : "nas, not online"}</dd>
      <dt>layout</dt><dd>mirror, 2 × 8 TB SAS</dd>
      <dt>free</dt><dd>${m?.nas_free_bytes == null ? NO_DATA : tb(m.nas_free_bytes)}</dd>
      <dt>pulls</dt><dd>${NB}</dd>
    </dl></div>`;
}

const plannedPanel = (id: NodeId) => `<h3>${NODES[id].name}</h3><div class="sub">Minerva</div><p>${NB}</p>`;

function renderSide(reset: boolean) {
  const box = $("side-scroll"), panel = box.parentElement!;
  if (!selected) { panel.classList.remove("open"); box.innerHTML = ""; return; }
  const at = selected.node
    ? NODES[selected.node].x
    : (NODES[linkEls[selected.link!].l.a].x + NODES[linkEls[selected.link!].l.b].x) / 2;
  panel.classList.add("open");
  panel.classList.toggle("left", at > 500);
  const keep = reset ? 0 : box.scrollTop;
  const id = selected.node;
  box.innerHTML = selected.link
    ? linkPanel(linkEls[selected.link])
    : id && isEdge(id) ? edgePanel(id)
    : id === "aah1" || id === "vk8s" ? vietaPanel()
    : id === "nas" ? nasPanel()
    : plannedPanel(id!);
  box.scrollTop = keep;
  box.insertAdjacentHTML("afterbegin", `<button class="close" type="button" aria-label="Close">×</button>`);
  box.querySelector(".close")!.addEventListener("click", () => select(null));
}

// ---- drawing the state
function renderMap() {
  for (const id of EDGE_IDS) {
    const s = fresh(id), N = nodeEls[id];
    if (!s) { N.rate.textContent = "no data"; N.third.textContent = ""; continue; }
    const u = sum(edgeUplinks(s));
    N.rate.textContent = `↓ ${mbit(u.rx)}  ↑ ${mbit(u.tx)} Mbit/s`;
    N.third.textContent = `BGP ${s.sessions.filter((x) => x.up).length}/${s.sessions.length}`;
    for (const c of drawChips(id, s).chips) {
      const ok = c.sessions.every((n) => s.sessions.find((x) => x.name === n)?.up);
      c.d.setAttribute("class", "st" + (ok ? "" : " down"));
    }
  }

  // gw1.aah1 is seen from the edges' ends of its tunnels
  {
    const N = nodeEls.aah1;
    let rx = 0, tx = 0, up = 0, seen = 0;
    for (const e of EDGE_IDS) {
      const s = fresh(e);
      if (!s) continue;
      seen++;
      const i = s.interfaces.find((x) => x.name === "wg-gw1-aah1");
      if (i) { rx += i.tx_bps; tx += i.rx_bps; }
      if (sessionUp(e, "ibgp_gw1_aah1")) up++;
    }
    N.rate.textContent = seen ? `↓ ${mbit(rx)}  ↑ ${mbit(tx)} Mbit/s` : "no data";
    N.third.textContent = seen ? `iBGP ${up}/${EDGE_IDS.length}` : "";
  }

  const v = vieta();
  nodeEls.vk8s.sub.textContent = v ? `${v.nodes_ready}/${v.nodes} nodes` : "";
  nodeEls.vk8s.rate.textContent = v ? `${v.apps_synced}/${v.apps} apps synced` : "no data";
  const m = minerva();
  nodeEls.nas.rate.textContent =
    m?.nas_pool_online == null ? "no data"
    : (m.nas_pool_online ? "online" : "not online") + (m.nas_free_bytes == null ? "" : `, ${tb(m.nas_free_bytes)} free`);

  for (const [id, L] of Object.entries(linkEls)) {
    const { a, b, local, planned } = L.l;
    if (planned) continue;
    if (local) continue;
    const m2 = measure(a, b);
    const ends = [a, b].filter(isEdge).filter((e) => fresh(e));
    const up = ends.length ? ends.every((e) => sessionUp(e, sessionFor(e === a ? b : a))) : undefined;
    const rtt = m2.find((x) => x.rtt != null)?.rtt;
    const loss = Math.max(0, ...m2.map((x) => x.loss ?? 0));
    const cls = up === undefined ? "planned" : !up ? "down" : loss > 0 ? "warn" : "";
    L.path.setAttribute("class", "lnk" + (cls ? " " + cls : "") + (selected?.link === id ? " sel" : ""));
    L.g!.setAttribute("class", "lbl" + (cls === "planned" ? "" : cls ? " " + cls : ""));
    L.text!.textContent = up === undefined ? "no data" : !up ? "down" : rtt == null ? "" : rtt.toFixed(1) + " ms";
    sizeLabel(L);
    const from = isEdge(a) ? a : (b as EdgeId);
    const i = fresh(from)?.interfaces.find((x) => x.name === ifaceFor(from === a ? b : a));
    L.rate = up && i ? i.rx_bps + i.tx_bps : 0;
    L.bias = i ? (from === a ? i.tx_bps : i.rx_bps) / Math.max(1, i.rx_bps + i.tx_bps) : 0.5;
  }

  const ss = sessionTotals(), t = uplinkTotals();
  const any = EDGE_IDS.some((e) => fresh(e));
  $("nh-stats").innerHTML = any
    ? `<span><span class="dot${ss.up < ss.all ? " warn" : ""}"></span>${ss.up}/${ss.all} BGP sessions</span><span>↓ ${fmtRate(t.rx)}</span><span>↑ ${fmtRate(t.tx)}</span>`
    : `<span>${NO_DATA}</span>`;
}

// Packets are drawn at a rate that grows with the measured traffic on the link, on a log scale:
// backbone traffic ranges from a few kbit/s of BFD to many Mbit/s.
let last = performance.now();
function animate(now: number) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  for (const L of Object.values(linkEls)) {
    const perSec = L.rate > 0 ? Math.min(14, 2.2 * Math.log10(1 + L.rate / 1e3)) : 0;
    L.acc += perSec * dt;
    while (L.acc >= 1) {
      L.acc -= 1;
      L.pkts.push({ c: el("circle", { r: 2.4, class: "pkt" }, gPkts) as SVGCircleElement, p: 0, fwd: Math.random() < L.bias, speed: 170 + Math.random() * 40 });
    }
    L.pkts = L.pkts.filter((k) => {
      k.p += k.speed * dt;
      if (k.p >= L.len) { k.c.remove(); return false; }
      const pt = L.path.getPointAtLength(k.fwd ? k.p : L.len - k.p);
      k.c.setAttribute("cx", String(pt.x));
      k.c.setAttribute("cy", String(pt.y));
      k.c.setAttribute("opacity", Math.min(1, Math.min(k.p, L.len - k.p) / 30).toFixed(2));
      return true;
    });
  }
  requestAnimationFrame(animate);
}

document.addEventListener("keydown", (e) => { if (e.key === "Escape" && selected) select(null); });
on(() => { renderMap(); renderSide(false); });
want("edges", 1000);
want("site", 15_000);
if (!reduceMotion) requestAnimationFrame(animate);
