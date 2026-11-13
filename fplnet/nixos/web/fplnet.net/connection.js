"use strict";

// v4. and v6. have only that family's addresses; each router name points at that edge alone.
const DOMAIN = "fplnet.net";

const EDGES = {
  "er1-dus1": { label: "er1.dus1", city: "Düsseldorf" },
  "er1-ams1": { label: "er1.ams1", city: "Amsterdam" },
  "er1-fra1": { label: "er1.fra1", city: "Frankfurt" },
};

const $ = (id) => document.getElementById(id);

function el(tag, text, cls) {
  const e = document.createElement(tag);
  if (text !== undefined && text !== null) e.textContent = text;
  if (cls) e.className = cls;
  return e;
}

// A value, optionally coloured, with a plain note after it.
function show(node, value, cls, note) {
  node.replaceChildren(el("span", value, cls));
  if (note) node.append(" ", el("span", note, "note"));
}

function ms(value) {
  return value < 10 ? `${value.toFixed(1)} ms` : `${Math.round(value)} ms`;
}

async function getJSON(url, timeout = 8000) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeout);
  try {
    const r = await fetch(url, { cache: "no-store", credentials: "omit", signal: ctl.signal });
    return await r.json();
  } finally {
    clearTimeout(timer);
  }
}

// This connection, from the values nginx wrote into the page.
function describeConnection() {
  const edge = EDGES[$("edge").dataset.raw];
  if (edge) {
    $("edge").textContent = `${edge.label}, ${edge.city}`;
    $("summary-edge").textContent = `${edge.label} in ${edge.city}`;
  }

  const proto = $("protocol").dataset.raw;
  if (proto === "HTTP/3.0") show($("protocol"), "HTTP/3", "good", "QUIC");
  else if (proto) show($("protocol"), proto.replace(".0", ""), proto === "HTTP/2.0" ? null : "warn");

  const tls = $("tls").dataset;
  if (tls.raw) $("tls").textContent = [tls.raw.replace("TLSv", "TLS "), tls.cipher].filter(Boolean).join(", ");

  const group = $("group").dataset.raw;
  if (/MLKEM/i.test(group) || group === "0x11ec" || group === "0x11eb") show($("group"), group, "good", "post-quantum");
  else if (group) show($("group"), group, "warn", "not post-quantum");

  const ech = {
    SUCCESS: ["Yes", "good"],
    GREASE: ["No", "warn", "GREASE only"],
    NOT_TRIED: ["No", "bad"],
    FAILED: ["Failed", "bad"],
    BACKEND: ["Backend", "warn"],
  }[$("ech").dataset.raw];
  if (ech) show($("ech"), ...ech);

  const s = $("session").dataset;
  show($("session"), s.resumed === "r" ? "Resumed" : "New", null, s.early === "1" ? "0-RTT" : null);

  const rtt = parseInt($("rtt").dataset.raw, 10);
  if (rtt > 0) show($("rtt"), ms(rtt / 1000));
  else show($("rtt"), "n/a", null, proto === "HTTP/3.0" ? "QUIC" : null);
}

async function testFamily(family) {
  const node = $(`fam-${family}`);
  try {
    const body = await getJSON(`https://v${family}.${DOMAIN}/api/conn`, 6000);
    show(node, body.ip, "good");
  } catch {
    show(node, "No connection", family === 6 ? "bad" : "warn");
  }
}

// Best of four requests after the first, which also opens the connection.
async function timeEdge(label) {
  const base = `https://${label}.${DOMAIN}/api/ping`;
  let best = Infinity;
  for (let i = 0; i < 5; i++) {
    const url = `${base}?${i}.${Math.random().toString(36).slice(2)}`;
    const t0 = performance.now();
    const r = await fetch(url, { cache: "no-store", credentials: "omit" });
    const t1 = performance.now();
    if (!r.ok) throw new Error(String(r.status));
    if (i === 0) continue;
    const e = performance.getEntriesByName(url).pop();
    const rtt = e && e.responseStart > 0 && e.requestStart > 0 ? e.responseStart - e.requestStart : t1 - t0;
    best = Math.min(best, rtt);
  }
  return best;
}

async function timeEdges() {
  const here = $("edge").dataset.raw;
  const rows = {};
  for (const [host, edge] of Object.entries(EDGES)) {
    const tr = el("tr");
    tr.append(el("td", edge.label), el("td", edge.city), el("td", "…", "num"), el("td"));
    $("edges").append(tr);
    rows[host] = tr;
  }
  const results = {};
  // One at a time, so the requests do not slow each other down.
  for (const [host, edge] of Object.entries(EDGES)) {
    try {
      results[host] = await timeEdge(edge.label);
      rows[host].children[2].textContent = ms(results[host]);
    } catch {
      rows[host].children[2].textContent = "failed";
    }
  }
  const ok = Object.entries(results);
  const fastest = ok.length ? ok.reduce((a, b) => (b[1] < a[1] ? b : a))[0] : null;
  for (const [host, tr] of Object.entries(rows)) {
    const tags = [];
    if (host === here) tags.push("connected");
    if (host === fastest) tags.push("fastest");
    tr.children[3].textContent = tags.join(", ");
    if (host === here) tr.className = "here";
  }
}

describeConnection();
document.querySelector("section.js").hidden = false;
testFamily(4).then(() => testFamily(6)).then(timeEdges);
