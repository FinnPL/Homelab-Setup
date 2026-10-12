import { execSync } from "node:child_process";

const REPO = "https://github.com/FinnPL/Homelab-Setup";

function localSha(): string | null {
  try {
    return execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
  } catch {
    return null;
  }
}

const env = process.env;
const sha = env.GITHUB_SHA ?? localSha();

export const BUILD = {
  at: new Date(),
  sha: sha?.slice(0, 7) ?? null,
  commitUrl: sha ? `${REPO}/commit/${sha}` : null,
  runUrl: env.GITHUB_RUN_ID
    ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`
    : null,
};

/** Minute precision in UTC, e.g. "2026-10-12 14:03 UTC". */
export const stamp = (d: Date) => `${d.toISOString().slice(0, 16).replace("T", " ")} UTC`;
