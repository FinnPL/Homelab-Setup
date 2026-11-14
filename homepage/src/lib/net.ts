// Facts about the network that live.json and site.json do not carry. Read at build time and by
// the browser scripts.

export const ASN = "AS218255";
export const AGGREGATE = "2a0c:b641:f90::/44";

export type EdgeId = "ams1" | "dus1" | "fra1";

export const EDGES: Record<EdgeId, { name: string; city: string; provider: string; prefix: string; loopback: string }> = {
  ams1: { name: "er1.ams1", city: "Amsterdam", provider: "getvps.net", prefix: "2a0c:b641:f99::/48", loopback: "2a0c:b641:f99::1" },
  dus1: { name: "er1.dus1", city: "Düsseldorf", provider: "Servperso", prefix: "2a0c:b641:f98::/48", loopback: "2a0c:b641:f98::1" },
  fra1: { name: "er1.fra1", city: "Frankfurt", provider: "Vultr", prefix: "2a0c:b641:f9a::/48", loopback: "2a0c:b641:f9a::1" },
};
export const EDGE_IDS = Object.keys(EDGES) as EdgeId[];

export const liveUrl = (e: EdgeId) => `https://${EDGES[e].name}.fplnet.net/live.json`;
export const SITE_DATA = "https://site-data.relay.lippok.dev/site.json";
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
