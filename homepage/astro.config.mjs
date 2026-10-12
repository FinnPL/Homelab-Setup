import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://lippok.dev",
  build: { format: "file" },
  devToolbar: { enabled: false },
  compressHTML: true,
  integrations: [sitemap({ filter: (page) => !page.endsWith("/datenschutz") })],
});
