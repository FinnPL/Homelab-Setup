// lippok.dev/ntp: ntp1's state from site-data's ntp.json (rewritten every 15 s from Prometheus) and a
// clock set against the nearest FPLNET edge, whose clock follows ntp1.
import { EDGES, EDGE_IDS, NTP_DATA, timeUrl, type EdgeId } from "../lib/net";

type Ntp = {
  up?: number;
  poll_age_s?: number;
  status?: string;
  lock?: string;
  pps_valid?: number;
  gps_available?: number;
  holdover_s?: number;
  locked_s?: number;
  tfom?: number;
  ffom?: number;
  phase_s?: number;
  sats_tracked?: number;
  sats_untracked?: number;
  stratum?: number;
  refid?: string;
  offset_s?: number;
  rms_offset_s?: number;
  root_dispersion_s?: number;
  pps_selected?: number;
  pps_stddev_s?: number;
  pps_reach?: number;
  requests_per_min?: number;
  hw_rx_share?: number;
  cno?: number[];
  offset_3h?: [number, number][];
  phase_3h?: [number, number][];
};

// Two missed feeder runs, or a UCCM poll older than a minute, mean the values are not current.
const STALE_MS = 2 * 60 * 1000;
const POLL_STALE_S = 60;

// TFOM n: the UCCM's own time error is between 10^(n-1) and 10^n ns.
const TFOM_RANGE = ["under 1 ns", "1 to 10 ns", "10 to 100 ns", "0.1 to 1 µs", "1 to 10 µs", "10 to 100 µs", "0.1 to 1 ms"];

// FFOM as the UCCM words it; 2 has not been seen on this unit.
const FFOM_TEXT: Record<number, string> = { 0: "PLL stabilized", 1: "PLL stabilizing", 3: "PLL unlocked" };

const SVG = "http://www.w3.org/2000/svg";
function svg(tag: string, attrs: Record<string, string | number>, parent?: Element) {
  const e = document.createElementNS(SVG, tag);
  for (const k in attrs) e.setAttribute(k, String(attrs[k]));
  parent?.append(e);
  return e;
}

export function seconds(v: number | undefined) {
  if (v === undefined) return "no data";
  const a = Math.abs(v);
  const [n, unit] = a < 1e-6 ? [a * 1e9, "ns"] : a < 1e-3 ? [a * 1e6, "µs"] : [a * 1e3, "ms"];
  const digits = unit === "ns" ? 0 : 1;
  const text = n.toFixed(digits);
  if (Number(text) === 0) return `0 ${unit}`;
  return (v < 0 ? "−" : "+") + text + " " + unit;
}

const unsigned = (v: number | undefined) => (v === undefined ? "no data" : seconds(Math.abs(v)).replace(/^\+/, ""));

const duration = (s: number) => {
  const m = Math.floor(s / 60), h = Math.floor(m / 60);
  return h >= 24 ? `${Math.floor(h / 24)} d ${h % 24} h` : h ? `${h} h ${m % 60} min` : `${m} min`;
};

function put(root: ParentNode, key: string, text: string) {
  root.querySelectorAll<HTMLElement>(`[data-k="${key}"]`).forEach((el) => (el.textContent = text));
}

// "<dot> text", built from nodes: the status text comes from the UCCM.
function putState(el: HTMLElement | null, dot: string, text: string) {
  if (!el) return;
  const d = document.createElement("span");
  d.className = dot ? `dot ${dot}` : "dot";
  el.replaceChildren(d, text);
}

function tip(el: HTMLElement, x: number, width: number, strong: string, rest: string) {
  const b = document.createElement("b");
  b.textContent = strong;
  el.replaceChildren(b, document.createElement("br"), rest);
  const pct = (x / width) * 100;
  el.style.left = pct + "%";
  // Near an edge the box hangs inward instead of past the panel.
  el.style.transform = pct < 15 ? "translate(0,-6px)" : pct > 85 ? "translate(-100%,-6px)" : "";
  el.hidden = false;
}

// A series over the last 3 hours in ns, on a symmetric scale of at least ±minScale.
function seriesChart(root: HTMLElement, key: string, minScale: number) {
  const box = root.querySelector<SVGSVGElement>(`svg[data-k=${key}]`)!;
  const tipEl = root.querySelector<HTMLElement>(`[data-k=${key}-tip]`)!;
  // Axis labels are HTML beside the plot: the plot stretches to its width and would distort SVG text.
  const ylab = root.querySelector<HTMLElement>(`[data-k=${key}-y]`)!;
  const W = 600, H = 190, P = 14, L = 0;
  let pts: [number, number][] = [];
  let scale = minScale;
  const Y = (ns: number) => H / 2 - (Math.max(-scale, Math.min(scale, ns)) / scale) * (H / 2 - P);
  const X = (i: number) => L + (pts.length > 1 ? (i / (pts.length - 1)) * (W - L) : 0);

  const grid = svg("g", {}, box);
  const line = svg("path", { class: "series" }, box);
  const cross = svg("line", { y1: 0, y2: H, class: "cross", visibility: "hidden" }, box);
  const mark = svg("circle", { r: 4, class: "mark", visibility: "hidden" }, box);
  const empty = svg("text", { x: 8, y: H / 2 - 8, class: "axis", visibility: "hidden" }, box);
  empty.textContent = "no data";

  box.addEventListener("mousemove", (e) => {
    if (pts.length < 2) return;
    const r = box.getBoundingClientRect();
    const fx = ((e.clientX - r.left) / r.width) * W;
    const i = Math.max(0, Math.min(pts.length - 1, Math.round(((fx - L) / (W - L)) * (pts.length - 1))));
    const x = X(i), ns = pts[i][1] * 1e9, ago = pts[pts.length - 1][0] - pts[i][0];
    cross.setAttribute("x1", String(x));
    cross.setAttribute("x2", String(x));
    cross.setAttribute("visibility", "visible");
    mark.setAttribute("cx", String(x));
    mark.setAttribute("cy", String(Y(ns)));
    mark.setAttribute("visibility", "visible");
    tip(tipEl, x, W, seconds(pts[i][1]), ago ? duration(ago) + " ago" : "now");
  });
  box.addEventListener("mouseleave", () => {
    cross.setAttribute("visibility", "hidden");
    mark.setAttribute("visibility", "hidden");
    tipEl.hidden = true;
  });

  return (series: [number, number][] | undefined) => {
    pts = series ?? [];
    const peak = Math.max(0, ...pts.map((p) => Math.abs(p[1]) * 1e9));
    const decade = 10 ** Math.floor(Math.log10(Math.max(peak, minScale)));
    scale = Math.max(minScale, [1, 2, 5, 10].map((m) => m * decade).find((v) => v >= peak)!);
    grid.replaceChildren();
    ylab.replaceChildren();
    for (const v of [-scale, -scale / 2, 0, scale / 2, scale]) {
      svg("line", { x1: L, x2: W, y1: Y(v), y2: Y(v), class: v ? "grid" : "grid zero" }, grid);
      const label = document.createElement("span");
      label.style.top = (Y(v) / H) * 100 + "%";
      label.textContent = (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v);
      ylab.append(label);
    }
    empty.setAttribute("visibility", pts.length < 2 ? "visible" : "hidden");
    line.setAttribute("d", pts.length < 2 ? "" : pts.map((p, i) => (i ? "L" : "M") + X(i).toFixed(1) + "," + Y(p[1] * 1e9).toFixed(1)).join(""));
  };
}

// Signal of every tracked satellite, strongest first, 0 to 50 dB-Hz.
function satChart(root: HTMLElement) {
  const box = root.querySelector<SVGSVGElement>("svg[data-k=sat]")!;
  const tipEl = root.querySelector<HTMLElement>("[data-k=sat-tip]")!;
  const W = 380, H = 190, B = 172, L = 26;
  const Y = (c: number) => B - (Math.max(0, Math.min(50, c)) / 50) * (B - 10);
  for (const c of [0, 25, 50]) {
    svg("line", { x1: L, x2: W, y1: Y(c), y2: Y(c), class: c ? "grid" : "grid zero" }, box);
    svg("text", { x: 0, y: Y(c) + 4, class: "axis" }, box).textContent = String(c);
  }
  const bars = svg("g", {}, box);
  return (cno: number[] | undefined) => {
    bars.replaceChildren();
    const list = cno ?? [];
    if (list.length === 0) {
      svg("text", { x: L + 4, y: Y(25), class: "axis" }, bars).textContent = "no satellites tracked";
      return;
    }
    // One slot per satellite across the full width, bars at most 28 wide in the middle of their slot.
    const slot = (W - L - 8) / list.length;
    list.forEach((c, i) => {
      const w = Math.min(28, slot - 8), x = L + 8 + i * slot + (slot - w) / 2, y = Y(c);
      svg("rect", { x, y, width: w, height: B - y, rx: 3, class: "bar used" }, bars);
      const hit = svg("rect", { x: L + 8 + i * slot, y: 0, width: slot, height: H, fill: "transparent" }, bars);
      hit.addEventListener("mouseenter", () => tip(tipEl, x + w / 2, W, `${c} dB-Hz`, `satellite ${i + 1} of ${list.length}`));
      hit.addEventListener("mouseleave", () => (tipEl.hidden = true));
    });
  };
}

type Draw = { off: ReturnType<typeof seriesChart>; phase: ReturnType<typeof seriesChart>; sat: ReturnType<typeof satChart> };

function render(root: HTMLElement, generated: Date | null, n: Ntp | undefined, draw: Draw) {
  const stale = !generated || Date.now() - generated.getTime() > STALE_MS || !n || n.up !== 1 || (n.poll_age_s ?? 1e9) > POLL_STALE_S;
  const stamp = root.querySelector<HTMLElement>("[data-k=stamp]");
  if (stamp) {
    stamp.textContent = !stale
      ? ""
      : generated
        ? "no update since " + generated.toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZone: "UTC" }) + " UTC"
        : "no data";
    stamp.className = stale ? "small mono bad" : "small mono";
  }
  const state = root.querySelector<HTMLElement>("[data-k=state]");
  if (!n) {
    putState(state, "down", "no data");
    draw.off(undefined);
    draw.phase(undefined);
    draw.sat(undefined);
    return;
  }
  if (stale) putState(state, "down", "not current");
  else if (n.status === "Master" && n.pps_selected) putState(state, "", "Locked");
  else if (n.status?.includes("Holdover")) putState(state, "warn", "Holdover");
  else putState(state, "down", n.status ?? "no data");

  put(root, "sat-caption", n.sats_tracked === undefined ? "Satellites, signal in dB-Hz" : `Satellites, ${n.sats_tracked} tracked, signal in dB-Hz`);
  put(root, "stratum", n.stratum === undefined ? "no data" : String(n.stratum));
  put(root, "refid", n.refid ?? "no data");
  put(root, "status", n.status ?? "no data");
  put(root, "lock", n.lock ?? "no data");
  put(root, "pps", n.pps_valid === undefined ? "no data" : n.pps_valid ? "valid" : "invalid");
  put(root, "tfom", `TFOM ${n.tfom ?? "–"}`);
  put(root, "tfom-note", n.tfom === undefined ? "no data" : TFOM_RANGE[n.tfom] ?? "over 1 ms");
  put(root, "ffom", `FFOM ${n.ffom ?? "–"}`);
  put(root, "ffom-note", n.ffom === undefined ? "no data" : FFOM_TEXT[n.ffom] ?? "");
  put(root, "jitter", `jitter ${n.pps_stddev_s === undefined ? "–" : unsigned(n.pps_stddev_s)}`);
  put(root, "reach", `reach ${n.pps_reach ?? "–"}/8`);
  put(root, "locked", n.holdover_s ? `in holdover, ${duration(n.holdover_s)}` : n.locked_s === undefined ? "over 7 d" : duration(n.locked_s));
  put(root, "offset", seconds(n.offset_s));
  put(root, "rms", unsigned(n.rms_offset_s));
  put(root, "disp", unsigned(n.root_dispersion_s));
  put(root, "rate", n.requests_per_min === undefined ? "no data" : n.requests_per_min.toFixed(1));
  put(root, "hw", n.hw_rx_share !== undefined ? (n.hw_rx_share * 100).toFixed(0) + " %" : n.requests_per_min ? "no data" : "no requests");
  draw.off(n.offset_3h);
  draw.phase(n.phase_3h);
  draw.sat(n.cno);
}

async function load(root: HTMLElement, draw: Draw) {
  let data: { generated?: string; ntp1?: Ntp } | null = null;
  try {
    const res = await fetch(NTP_DATA, { cache: "no-store" });
    if (res.ok) data = await res.json();
  } catch {
    data = null;
  }
  render(root, data?.generated ? new Date(data.generated) : null, data?.ntp1, draw);
}

// This browser's clock against each edge: four requests each (the first also opens the connection);
// the one with the shortest round trip across all edges wins. The edge's time lies somewhere inside
// that round trip, so taking its middle is off by at most half of it.
type Measured = { edge: EdgeId; offset: number; bound: number };

async function measure(): Promise<Measured | null> {
  const one = async (edge: EdgeId) => {
    let best: { edge: EdgeId; rtt: number; offset: number } | null = null;
    for (let i = 0; i < 4; i++) {
      try {
        const t0 = performance.now();
        const res = await fetch(timeUrl(edge), { cache: "no-store" });
        const text = await res.text();
        const t1 = performance.now();
        const wall = Date.now();
        const server = parseFloat(text) * 1000;
        if (!res.ok || !isFinite(server)) continue;
        const rtt = t1 - t0;
        // Where this browser's wall clock stood in the middle of the round trip.
        const mid = wall - rtt / 2;
        if (!best || rtt < best.rtt) best = { edge, rtt, offset: server - mid };
      } catch {
        /* the next request, or the next edge */
      }
    }
    return best;
  };
  const results = (await Promise.all(EDGE_IDS.map(one))).filter((r) => r !== null);
  if (results.length === 0) return null;
  const best = results.reduce((a, b) => (b.rtt < a.rtt ? b : a));
  // The edge stamps with 1 ms resolution.
  return { edge: best.edge, offset: best.offset, bound: best.rtt / 2 + 1 };
}

function startClock(root: HTMLElement, offset: () => number) {
  const clock = root.querySelector<HTMLElement>("[data-k=clock]");
  const date = root.querySelector<HTMLElement>("[data-k=date]");
  if (!clock || !date) return;
  const tick = () => {
    const now = new Date(Date.now() + offset());
    clock.textContent = now.toISOString().slice(11, 23);
    const d = now.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
    if (date.textContent !== d) date.textContent = d;
    requestAnimationFrame(tick);
  };
  tick();
}

function showOffset(you: HTMLElement, m: Measured | null) {
  if (!m) {
    you.textContent = "not measured";
    return;
  }
  const ms = Math.abs(m.offset);
  const text = ms < m.bound ? "matches" : `${ms.toFixed(0)} ms ${m.offset > 0 ? "behind" : "ahead"}`;
  const note = document.createElement("small");
  note.textContent = `±${Math.ceil(m.bound)} ms via ${EDGES[m.edge].name}`;
  you.replaceChildren(text, note);
}

export async function startNtp(root: HTMLElement) {
  const draw: Draw = { off: seriesChart(root, "off", 10), phase: seriesChart(root, "phase", 20), sat: satChart(root) };
  load(root, draw);
  setInterval(() => load(root, draw), 15000);

  let offset = 0;
  startClock(root, () => offset);
  const you = root.querySelector<HTMLElement>("[data-k=you]");
  // Measured again every 10 minutes: the computer's own time sync may step its clock meanwhile.
  const run = async () => {
    const m = await measure();
    if (m) offset = m.offset;
    if (you) showOffset(you, m);
  };
  await run();
  setInterval(run, 10 * 60 * 1000);
}
