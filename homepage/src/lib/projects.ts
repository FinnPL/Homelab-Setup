export type Repo = {
  slug: string;
  title: string;
  summary: string;
  topics: string[];
  /** Set false to keep the project off the front page. */
  home?: boolean;
  /** Set when the project has a page of its own under /projects. */
  page?: { href: string; label: string };
  image?: { src: string; alt: string; width: number; height: number };
  meta: { stars: number; language: string | null; pushed: string };
};

type Featured = Pick<Repo, "slug" | "home" | "page" | "image">;

const FEATURED: Featured[] = [
  {
    slug: "FinnPL/Homelab-Setup",
    page: { href: "/homelab", label: "Homelab" },
    image: {
      src: "/diagrams/multi-site-topology.svg",
      alt: "Topology of the three sites: a Kubernetes cluster on Proxmox, a Docker Compose host, and a NixOS edge on Oracle Cloud, joined by a WireGuard tunnel.",
      width: 2540,
      height: 1754,
    },
  },
  { slug: "FinnPL/Vault-Deployment" },
  { slug: "FinnPL/NixOS-Configuration" },
  { slug: "FinnPL/Forum", home: false },
];

type ApiRepo = {
  full_name: string;
  name: string;
  description: string | null;
  topics?: string[];
  stargazers_count: number;
  language: string | null;
  pushed_at: string;
};

// GitHub is the source of truth for summaries and topics, so a failed fetch fails the build
// instead of shipping empty cards.
async function fetchRepos(): Promise<Map<string, ApiRepo>> {
  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "User-Agent": "lippok.dev-build",
  };
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  const res = await fetch("https://api.github.com/users/FinnPL/repos?per_page=100&sort=pushed", {
    headers,
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) throw new Error(`[projects] GitHub API ${res.status}`);
  return new Map(((await res.json()) as ApiRepo[]).map((r) => [r.full_name, r]));
}

const load = async () => ({ repos: await fetchRepos(), fetchedAt: new Date() });

let cached: Promise<{ repos: Map<string, ApiRepo>; fetchedAt: Date }> | undefined;

export async function projects(): Promise<{ featured: Repo[]; fetchedAt: Date }> {
  const { repos, fetchedAt } = await (cached ??= load());
  return {
    fetchedAt,
    featured: FEATURED.map((p) => {
      const r = repos.get(p.slug);
      if (!r) throw new Error(`[projects] ${p.slug} not found on GitHub`);
      if (!r.description) throw new Error(`[projects] ${p.slug} has no GitHub description`);
      return {
        ...p,
        title: r.name,
        summary: r.description.trim(),
        topics: r.topics ?? [],
        meta: { stars: r.stargazers_count, language: r.language, pushed: r.pushed_at.slice(0, 10) },
      };
    }),
  };
}
