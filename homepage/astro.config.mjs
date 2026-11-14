import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://lippok.dev",
  build: { format: "file" },
  devToolbar: { enabled: false },
  compressHTML: true,
  redirects: { "/homelab": "/vieta", "/projects": "/repos" },
  integrations: [sitemap({ filter: (page) => !/\/(datenschutz|homelab|projects)$/.test(page) })],
});
