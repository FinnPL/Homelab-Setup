// Per-day status bars from /status.json, which the edge rewrites from Gatus every 5 minutes.
// Rows with no check behind them yet are listed as such, not drawn as bars.
const NOT_BUILT = ["DNS Minerva", "NTP"];

type StatusJson = {
  generated?: string;
  keys?: string[];
  rows?: { label: string; state: string; days?: number[]; minutes?: number[] }[];
};

// Three missed runs means the homelab or the path to it is down, which is exactly when the last
// good state must not be shown as current.
const STALE_MS = 15 * 60 * 1000;

const duration = (m: number) => (m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "min" : m + " min");

function li(name: string, ...rest: HTMLElement[]) {
  const row = document.createElement("li");
  const n = document.createElement("span");
  n.className = "name";
  n.textContent = name;
  row.append(n, ...rest);
  return row;
}

function span(cls: string, text = "") {
  const s = document.createElement("span");
  s.className = cls;
  s.textContent = text;
  return s;
}

export async function renderStatus(list: HTMLElement, stampEl: HTMLElement | null, days: number) {
  let data: StatusJson | null = null;
  try {
    const res = await fetch("/status.json", { cache: "no-store" });
    if (res.ok) data = await res.json();
  } catch {
    data = null;
  }

  const rows = Array.isArray(data?.rows) ? data.rows : [];
  const generated = data?.generated ? new Date(data.generated) : null;
  const stale = !generated || Date.now() - generated.getTime() > STALE_MS;

  if (rows.length === 0) list.append(li("Status", span("nbrow", "no data")));

  for (const row of rows) {
    const d = Array.isArray(row.days) ? row.days.slice(-days) : [];
    const keys = Array.isArray(data!.keys) ? data!.keys.slice(-d.length) : [];
    const minutes = Array.isArray(row.minutes) ? row.minutes.slice(-d.length) : [];
    const bars = span("bars");
    d.forEach((v, i) => {
      const bar = document.createElement("i");
      if (v === 0) bar.className = "down";
      else if (v !== 1) bar.className = "none";
      const when = keys[i]
        ? new Date(keys[i] + "T12:00:00").toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })
        : null;
      const what = v === 0 ? "down " + duration(minutes[i] ?? 0) : v === 1 ? "no outage" : "no data";
      bar.dataset.tip = when ? when + " · " + what : what;
      bars.appendChild(bar);
    });
    const pill = span(
      stale ? "pill stale" : row.state === "ok" ? "pill" : "pill bad",
      stale ? "Unknown" : row.state === "ok" ? "Operational" : "Degraded",
    );
    list.append(li(row.label, bars, pill));
  }

  for (const name of NOT_BUILT) list.append(li(name, span("nbrow", "no check yet"), span("pill nb", "Not built yet")));

  if (stampEl && generated && stale) {
    const when = generated.toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
    stampEl.textContent = "no update since " + when;
    stampEl.classList.add("stale");
  }
}
