import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { parse } from "yaml";

const REPO = resolve(process.cwd(), "..");

export type Component = {
  name: string;
  namespace: string;
  pins: { chart: string; version: string }[];
  group: string;
  blurb: string;
  source: "argocd" | "terraform";
};

const COPY: Record<string, { group: string; blurb: string }> = {
  "argocd-config": {
    group: "Platform",
    blurb:
      "ApplicationSet: Reconciles the cluster against this repository.",
  },
  crossplane: {
    group: "Platform",
    blurb:
      "Provisions Postgres databases and PgBouncer poolers and writes the credentials to a secret.",
  },
  cnpg: {
    group: "Platform",
    blurb:
      "Postgres operator for shared DB.",
  },
  "cluster-namespaces": {
    group: "Platform",
    blurb: "Namespaces and their Pod Security Admission labels.",
  },
  dns: {
    group: "Networking",
    blurb:
      "Blocky for filtering and caching, with an Unbound sidecar for DNSSEC validation, prefetching and DoT forwarding upstream.",
  },
  "gateway-external-routes": {
    group: "Networking",
    blurb:
      "Gateway API routes for services hosted outside the cluster.",
  },
  tailscale: {
    group: "Networking",
    blurb:
      "Tailscale operator. GitHub Actions runners join the tailnet to reach the cluster.",
  },
  authentik: {
    group: "Identity",
    blurb: "Single sign-on for the services.",
  },
  kyverno: {
    group: "Policy",
    blurb:
      "The policy set for baseline pod hardening, enforced at admission.",
  },
  "kyverno-operator": {
    group: "Policy",
    blurb:
      "The Kyverno admission controller. CI runs the same policy set against rendered charts before merge.",
  },
  tetragon: {
    group: "Policy",
    blurb:
      "eBPF runtime observability. The tracing policies are observe-only.",
  },
  "kube-prometheus-stack": {
    group: "Observability",
    blurb: "Prometheus, Alertmanager and Grafana.",
  },
  loki: { group: "Observability", blurb: "Log storage, queried from Grafana." },
  alloy: {
    group: "Observability",
    blurb:
      "Telemetry collection. Scrapes nodes, Proxmox syslog and UniFi syslog.",
  },
  gatus: {
    group: "Observability",
    blurb: "Black-box health checks and alerting.",
  },
  "local-path-provisioner": {
    group: "Storage",
    blurb:
      "Node-local volumes on the database node. Everything else uses the NFS storage class.",
  },
  "it-tools": { group: "Applications", blurb: "A self-hosted collection of small conversion and encoding utilities." },
};

const PLATFORM_COPY: Record<string, string> = {
  cilium:
    "Replaces kube-proxy as CNI, advertises LoadBalancer addresses, Gateway API for HTTPRoutes.",
  "cert-manager":
    "Issues the wildcard certificate from Let's Encrypt over a DNS-01 challenge.",
  "argo-cd":
    "Installed by Terraform. From then on it deploys everything else from this repository.",
  "external-secrets":
    "Pulls secrets from Vault for Services. The cluster authenticates with a short-lived ServiceAccount token.",
  "csi-driver-nfs":
    "Backs the default storage class with the NFS export.",
};

const GROUP_ORDER = [
  "Platform",
  "Networking",
  "Identity",
  "Policy",
  "Observability",
  "Storage",
  "Applications",
  "Other",
];

function platformComponents(): Component[] {
  const dir = join(REPO, "03-services");
  const files = readdirSync(dir).filter((f) => f.endsWith(".tf"));
  const out: Component[] = [];

  // helm_release blocks name their namespace by reference, not by literal
  const declared = new Map<string, string>();
  for (const file of files) {
    const tf = readFileSync(join(dir, file), "utf8");
    const re = /resource\s+"(kubernetes_namespace(?:_v1)?)"\s+"([\w-]+)"\s*\{[^}]*?name\s*=\s*"([^"]+)"/g;
    for (const m of tf.matchAll(re)) declared.set(`${m[1]}.${m[2]}`, m[3]);
  }

  for (const file of files) {
    const tf = readFileSync(join(dir, file), "utf8");
    for (const block of tf.split(/resource\s+"helm_release"/).slice(1)) {
      const body = block.slice(0, block.indexOf("\n}"));
      const chart = /\bchart\s*=\s*"([^"]+)"/.exec(body)?.[1];
      const version = /\bversion\s*=\s*"([^"]+)"/.exec(body)?.[1];
      const ref = /\bnamespace\s*=\s*(kubernetes_namespace(?:_v1)?\.[\w-]+)\.metadata/.exec(body)?.[1];
      const namespace =
        /\bnamespace\s*=\s*"([^"]+)"/.exec(body)?.[1] ?? (ref ? declared.get(ref) : undefined);
      if (!chart || !version) continue;
      out.push({
        name: chart,
        namespace: namespace ?? "",
        pins: [{ chart, version }],
        group: "Platform",
        blurb: PLATFORM_COPY[chart] ?? "",
        source: "terraform",
      });
    }
  }
  return out;
}

// Every charts/<dir>/app.yaml becomes one Application via the ApplicationSet in apps/charts.yaml
function appDirs(): string[] {
  return readdirSync(join(REPO, "charts")).filter((d) => existsSync(join(REPO, "charts", d, "app.yaml")));
}

function chartPins(chartPath: string): Component["pins"] {
  const file = join(REPO, chartPath, "Chart.yaml");
  if (!existsSync(file)) return [];
  const chart = parse(readFileSync(file, "utf8")) ?? {};
  const deps: { name: string; version: string }[] = chart.dependencies ?? [];
  const seen = new Set<string>();
  return deps
    .map((d) => ({ chart: String(d.name), version: String(d.version) }))
    .filter((p) => (seen.has(p.chart + p.version) ? false : seen.add(p.chart + p.version)));
}

export function components(): { group: string; items: Component[] }[] {
  const all: Component[] = platformComponents();

  for (const dir of appDirs()) {
    const app = parse(readFileSync(join(REPO, "charts", dir, "app.yaml"), "utf8")) ?? {};

    const name = (app.name as string) ?? dir;
    const namespace = (app.namespace as string) ?? "";
    const pins = chartPins(join("charts", dir));

    const copy = COPY[name];
    all.push({
      name,
      namespace,
      pins,
      group: copy?.group ?? "Other",
      blurb: copy?.blurb ?? "",
      source: "argocd",
    });
  }

  return GROUP_ORDER.map((group) => ({
    group,
    items: all.filter((c) => c.group === group).sort((a, b) => a.name.localeCompare(b.name)),
  })).filter((g) => g.items.length > 0);
}

export function counts() {
  const groups = components();
  const items = groups.flatMap((g) => g.items);
  return {
    apps: items.filter((i) => i.source === "argocd").length,
    platform: items.filter((i) => i.source === "terraform").length,
    pinned: items.flatMap((i) => i.pins).length,
    wrappers: readdirSync(join(REPO, "charts")).length,
  };
}
