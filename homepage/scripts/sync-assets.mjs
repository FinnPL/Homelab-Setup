import { copyFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const repo = fileURLToPath(new URL("../../", import.meta.url));
const out = fileURLToPath(new URL("../public/diagrams/", import.meta.url));

mkdirSync(out, { recursive: true });
for (const f of ["multi-site-topology.svg", "dns-resolution.svg"]) {
  copyFileSync(join(repo, "docs/diagrams", f), join(out, f));
  console.log(`synced ${f}`);
}
