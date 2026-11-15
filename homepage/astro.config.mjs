import { readFileSync } from "node:fs";
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

// The edges' public facts from inventory/fplnet.json
const fplnet = JSON.parse(readFileSync(new URL("../inventory/fplnet.json", import.meta.url), "utf8")).inventory.fplnet;
const edges = Object.fromEntries(
  Object.entries(fplnet.routers)
    .filter(([, r]) => r.prefix)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, r]) => [
      name.split("-")[1],
      { name: name.replace("-", "."), city: r.city, provider: r.provider, prefix: r.prefix, loopback: r.loopback },
    ]),
);

export default defineConfig({
  site: "https://lippok.dev",
  build: { format: "file" },
  devToolbar: { enabled: false },
  compressHTML: true,
  redirects: { "/homelab": "/vieta", "/projects": "/repos" },
  integrations: [sitemap({ filter: (page) => !/\/(datenschutz|homelab|projects)$/.test(page) })],
  vite: {
    define: { __FPLNET__: JSON.stringify({ asn: fplnet.asn, aggregate: fplnet.prefixes.aggregate, edges }) },
  },
});
