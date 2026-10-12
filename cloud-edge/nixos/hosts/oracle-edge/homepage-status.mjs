// Writes the homepage's status.json from Gatus. Runs on every 5 minutes (homepage.nix).
// Gatus only returns the last 100 results per check, so the 30-day history is kept here.
// Each run folds the new results into STATE.
import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const GATUS = process.env.GATUS_URL;
const DIR = process.env.STATE_DIRECTORY ?? ".";
const STATE = join(DIR, "state.json");
const OUT = join(DIR, "status.json");
const DAYS = 30;
const TZ = "Europe/Berlin";
const MIN_OUTAGE_MS = 10 * 60 * 1000;
const DAY_MS = 86400000;

const ROWS = [
  { label: "Website", match: (e) => e.name === "Website" },
  { label: "Mail", match: (e) => e.group === "Mail" },
  { label: "Storage", match: (e) => e.group === "NAS" },
  { label: "Authentik", match: (e) => e.name === "Authentik" },
];

if (!GATUS) {
  console.error("GATUS_URL is required");
  process.exit(1);
}

const dayKey = (t) =>
  new Intl.DateTimeFormat("en-CA", { timeZone: TZ, dateStyle: "short" }).format(new Date(t));

async function get(path) {
  const res = await fetch(new URL(path, GATUS), { signal: AbortSignal.timeout(20000) });
  if (!res.ok) throw new Error(`gatus ${path} returned ${res.status}`);
  return res.json();
}

function writeAtomic(path, data) {
  writeFileSync(`${path}.tmp`, JSON.stringify(data));
  renameSync(`${path}.tmp`, path);
}

async function seed(key) {
  const { events = [] } = await get(`/api/v1/endpoints/${encodeURIComponent(key)}/statuses?page=1&pageSize=1`);
  const st = { last: null, seen: [], runs: [], open: null };
  if (events.length === 0) return st;

  for (const ev of events) {
    const t = Date.parse(ev.timestamp);
    if (ev.type === "UNHEALTHY") st.open ??= { start: t, last: t };
    if (ev.type === "HEALTHY" && st.open) {
      st.runs.push({ start: st.open.start, end: t });
      st.open = null;
    }
  }
  st.last = Date.parse(events.at(-1).timestamp);
  for (let t = Date.parse(events[0].timestamp); t < Date.now(); t += DAY_MS) st.seen.push(dayKey(t));
  return st;
}

function fold(st, results) {
  const seen = new Set(st.seen);
  for (const r of results) {
    const t = Date.parse(r.timestamp);
    if (st.last !== null && t <= st.last) continue;
    seen.add(dayKey(t));
    if (!r.success) {
      if (st.open) st.open.last = t;
      else st.open = { start: t, last: t };
    } else if (st.open) {
      st.runs.push({ start: st.open.start, end: t });
      st.open = null;
    }
    st.last = t;
  }
  st.seen = [...seen];
}

function prune(st, keys) {
  const cutoff = Date.now() - (DAYS + 1) * DAY_MS;
  st.runs = st.runs.filter((r) => r.end >= cutoff);
  st.seen = st.seen.filter((k) => keys.includes(k));
}

function outageMinutes(st) {
  const perDay = new Map();
  const runs = st.open ? [...st.runs, { start: st.open.start, end: st.open.last }] : st.runs;
  for (const { start, end } of runs) {
    if (end - start <= MIN_OUTAGE_MS) continue;
    for (let t = start; t < end; t += 60000) {
      const k = dayKey(t);
      perDay.set(k, (perDay.get(k) ?? 0) + Math.min(60000, end - t));
    }
  }
  return new Map([...perDay].map(([k, ms]) => [k, Math.round(ms / 60000)]));
}

const keys = [];
for (let i = DAYS - 1; i >= 0; i--) keys.push(dayKey(Date.now() - i * DAY_MS));

const state = existsSync(STATE) ? JSON.parse(readFileSync(STATE, "utf8")) : {};
const endpoints = await get("/api/v1/endpoints/statuses?page=1&pageSize=100");

const rows = [];
let newest = 0;
for (const row of ROWS) {
  const matched = endpoints.filter(row.match);
  if (matched.length === 0) continue;

  const down = new Map();
  const seen = new Set();
  for (const e of matched) {
    state[e.key] ??= await seed(e.key);
    const results = [...(e.results ?? [])].sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp));
    fold(state[e.key], results);
    prune(state[e.key], keys);
    if (state[e.key].last) newest = Math.max(newest, state[e.key].last);

    for (const k of state[e.key].seen) seen.add(k);
    for (const [k, m] of outageMinutes(state[e.key])) down.set(k, Math.max(down.get(k) ?? 0, m));
  }

  rows.push({
    label: row.label,
    state: matched.every((e) => (e.results ?? []).at(-1)?.success) ? "ok" : "degraded",
    days: keys.map((k) => (!seen.has(k) ? null : down.has(k) ? 0 : 1)),
    minutes: keys.map((k) => (!seen.has(k) ? null : (down.get(k) ?? 0))),
  });
}

writeAtomic(STATE, state);
writeAtomic(OUT, {
  generated: newest ? new Date(newest).toISOString() : null,
  days: DAYS,
  minOutageMinutes: 10,
  keys,
  rows,
});
console.log(`wrote ${OUT} with ${rows.length} rows`);
