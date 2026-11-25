// Facts about the network that live.json and site.json do not carry. Read at build time and by
// the browser scripts.

type Edge = { name: string; city: string; provider: string; prefix: string; loopback: string };

// From inventory/fplnet.json, put in by astro.config.mjs.
declare const __FPLNET__: { asn: number; aggregate: string; edges: Record<string, Edge> };
const FPLNET = __FPLNET__;

export const ASN = `AS${FPLNET.asn}`;
export const AGGREGATE = FPLNET.aggregate;

export type EdgeId = string;

export const EDGES: Record<EdgeId, Edge> = FPLNET.edges;
export const EDGE_IDS = Object.keys(EDGES) as EdgeId[];

export const liveUrl = (e: EdgeId) => `https://${EDGES[e].name}.fplnet.net/live.json`;
export const SITE_DATA = "https://site-data.relay.lippok.dev/site.json";
export const STATUS_DATA = "https://site-data.relay.lippok.dev/status.json";
export const NTP_DATA = "https://site-data.relay.lippok.dev/ntp.json";
export const timeUrl = (e: EdgeId) => `https://${EDGES[e].name}.fplnet.net/time`;
export const NTP_HOST = "ntp1.aah1.fplnet.net";
export const NTP_POOL = [
  { address: "2a0c:b641:f94:20::123", family: "IPv6", via: "ntp1.aah1" },
  { address: "209.250.233.8", family: "IPv4", via: "er1.fra1" },
  { address: "194.28.99.178", family: "IPv4", via: "er1.dus1" },
];
export const poolScores = (address: string) => `https://www.ntppool.org/scores/${address}`;
export const DNS_CHECK = "https://dns-check.fplnet.net/api/ping";
export const CONNECTION = "https://fplnet.net/connection";

export const LOOKING_GLASS = "https://lg.fplnet.net/";
export const lgSummary = (e: EdgeId) => `${LOOKING_GLASS}summary/${EDGES[e].loopback}`;
export const lgSession = (e: EdgeId, protocol: string) => `${LOOKING_GLASS}detail/${EDGES[e].loopback}/${encodeURIComponent(protocol)}`;

// gw1-aah1 takes its default route from the edges in this order (local pref 200/150/100 in
// from_edge, fplnet/nixos/hosts/gw1-aah1).
export const GW1_AAH1_PREFERENCE: EdgeId[] = ["fra1", "dus1", "ams1"];

// Names of the networks behind each external BGP session, by session name.
const NETWORKS: [RegExp, string][] = [
  [/^paradox/, "Paradox"],
  [/^he$/, "HE"],
  [/^interix/, "InterIX"],
  [/^cloudflare/, "Cloudflare"],
  [/^servperso/, "Servperso"],
  [/^route64/, "Route64"],
  [/^locix/, "LocIX"],
  [/^vultr/, "Vultr"],
];
export const networkOf = (session: string) => NETWORKS.find(([re]) => re.test(session))?.[1] ?? session;

// Sessions that are not a neighbour network: the backbone, and the HE route collector, which
// only receives routes.
export const isNeighbourSession = (s: { name: string; kind: string }) =>
  s.kind !== "backbone" && s.name !== "he_collector";

// Backbone tunnels and their far ends; every other interface is an uplink.
export const isBackboneIface = (name: string) => /^wg-(er1|gw1)-/.test(name);

export const NAV: { href: string; label: string }[][] = [
  [
    { href: "/vieta", label: "vieta" },
    { href: "/minerva", label: "minerva" },
    { href: "https://fplnet.net/", label: "fplnet.net ↗" },
  ],
  [
    { href: "/dns", label: "dns" },
    { href: "/ntp", label: "ntp" },
    { href: "/status", label: "status" },
  ],
  [
    { href: "/repos", label: "repos" },
    { href: "/writing", label: "writing" },
    { href: "/about", label: "about" },
  ],
];
