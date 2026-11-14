// One feed for every page: each edge's live.json, the sites' site.json and this visitor's
// Cloudflare trace. Pages ask for a source with want(); the shortest interval asked for wins.
import { EDGE_IDS, liveUrl, SITE_DATA, isBackboneIface, type EdgeId } from "../lib/net";

export type Live = {
  edge: string;
  time: number;
  links: { target: string; kind: string; rtt_ms: number | null; loss_60s: number | null }[];
  interfaces: { name: string; rx_bps: number; tx_bps: number }[];
  sessions: { name: string; kind: string; state: string; up: boolean; prefixes: number | null }[];
};

export type Site = {
  generated: string;
  source: string;
  sites: {
    vieta?: {
      nodes: number; nodes_ready: number; pods_running: number;
      cpu_used: number; memory_used: number;
      apps: number; apps_synced: number; apps_healthy: number;
    };
    minerva?: { nas_pool_online?: number; nas_free_bytes?: number };
  };
};

type Fresh<T> = { data: T | null; ok: boolean; stamp: unknown; changed: number; tried: boolean };

// A file counts as fresh while its own timestamp keeps moving. Comparing the timestamp with the
// visitor's clock would mark everything stale on a machine whose clock is off.
const STALE_MS = { edge: 15_000, site: 90_000 };

export const state = {
  edges: Object.fromEntries(EDGE_IDS.map((e) => [e, { data: null, ok: false, stamp: null, changed: 0, tried: false }])) as Record<EdgeId, Fresh<Live>>,
  site: { data: null, ok: false, stamp: null, changed: 0, tried: false } as Fresh<Site>,
  trace: null as Record<string, string> | null,
};

const subs: (() => void)[] = [];
export function on(cb: () => void) {
  subs.push(cb);
  cb();
}
const emit = () => subs.forEach((cb) => cb());

async function getJson<T>(url: string): Promise<T | null> {
  try {
    const res = await fetch(url, { cache: "no-store", signal: AbortSignal.timeout(4000) });
    return res.ok ? ((await res.json()) as T) : null;
  } catch {
    return null;
  }
}

function settle<T>(f: Fresh<T>, data: T | null, stamp: unknown, limit: number) {
  const now = performance.now();
  f.tried = true;
  if (data) {
    if (stamp !== f.stamp) f.changed = now;
    f.data = data;
    f.stamp = stamp;
  }
  f.ok = !!data && now - f.changed < limit;
}

const sources = {
  edges: async () => {
    await Promise.all(
      EDGE_IDS.map(async (e) => {
        const d = await getJson<Live>(liveUrl(e));
        settle(state.edges[e], d, d?.time, STALE_MS.edge);
      }),
    );
  },
  site: async () => {
    const d = await getJson<Site>(SITE_DATA);
    settle(state.site, d, d?.generated, STALE_MS.site);
  },
};
type Source = keyof typeof sources;

const every: Partial<Record<Source, number>> = {};
const timers: Partial<Record<Source, number>> = {};

async function run(src: Source) {
  clearTimeout(timers[src]);
  if (!document.hidden) {
    await sources[src]();
    emit();
  }
  timers[src] = window.setTimeout(() => run(src), every[src]);
}

export function want(src: Source, ms: number) {
  const first = every[src] == null;
  every[src] = Math.min(every[src] ?? ms, ms);
  if (first) run(src);
}

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) for (const src of Object.keys(every) as Source[]) run(src);
});

// ---- helpers shared by the pages

export const fresh = (e: EdgeId) => (state.edges[e].ok ? state.edges[e].data : null);

export function sessionTotals() {
  let up = 0, all = 0;
  for (const e of EDGE_IDS) for (const s of fresh(e)?.sessions ?? []) { all++; if (s.up) up++; }
  return { up, all };
}

export function uplinkTotals() {
  let rx = 0, tx = 0;
  for (const e of EDGE_IDS)
    for (const i of fresh(e)?.interfaces ?? []) if (!isBackboneIface(i.name)) { rx += i.rx_bps; tx += i.tx_bps; }
  return { rx, tx };
}

export function fmtRate(bps: number) {
  if (bps >= 1e9) return (bps / 1e9).toFixed(2) + " Gbit/s";
  if (bps >= 1e6) return (bps / 1e6).toFixed(1) + " Mbit/s";
  return Math.round(bps / 1e3) + " kbit/s";
}

export const fmtNum = (n: number | null | undefined) => (n == null ? "" : n.toLocaleString("en-GB"));

export const esc = (s: unknown) =>
  String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export const NB = '<span class="nb">not built yet</span>';
export const NO_DATA = '<span class="nb stale">no data</span>';

// ---- status bar: the network on the left, this visitor's connection on the right

async function trace() {
  try {
    const res = await fetch("/cdn-cgi/trace", { cache: "no-store", signal: AbortSignal.timeout(4000) });
    if (!res.ok) return;
    state.trace = Object.fromEntries(
      (await res.text()).split("\n").filter(Boolean).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]),
    );
    emit();
  } catch {
    return;
  }
}

function statusbar() {
  const net = document.getElementById("sb-net");
  if (net) {
    const answering = EDGE_IDS.filter((e) => state.edges[e].ok).length;
    const seen = EDGE_IDS.some((e) => state.edges[e].tried);
    const s = sessionTotals();
    const cls = answering === 0 ? " down" : answering < EDGE_IDS.length || s.up < s.all ? " warn" : "";
    net.innerHTML = !seen
      ? ""
      : `<span><span class="dot${cls}"></span>AS218255</span><span>${answering}/${EDGE_IDS.length} edges</span>` +
        (answering ? `<span>${s.up}/${s.all} BGP sessions</span>` : "");
  }
  const conn = document.getElementById("sb-conn");
  const t = state.trace;
  if (conn && t) {
    const kex = t.kex ?? "";
    conn.innerHTML = [
      `<span>${t.ip?.includes(":") ? "IPv6" : "IPv4"}</span>`,
      t.http ? `<span>${esc(t.http.toUpperCase())}</span>` : "",
      kex ? `<span${/MLKEM/i.test(kex) ? ' class="pq"' : ""}>${esc(kex)}</span>` : "",
      t.sni === "encrypted" ? "<span>ECH</span>" : "",
      t.colo ? `<span>Cloudflare ${esc(t.colo)}</span>` : "",
    ].join("");
  }
}

on(statusbar);
want("edges", 10_000);
trace();
