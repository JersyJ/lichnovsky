// Everything the start page's network map shows. Each service is a station on its line, in order.
// `monitor` is the monitor's name on the public Uptime Kuma status page "home"; stations without
// one show an empty ring.

/** How a visitor can reach the service. */
export type Access =
  /** Open from anywhere. */
  | "public"
  /** From the internet only after signing in through Cloudflare Access. */
  | "sign-in"
  /** Only at home and over Tailscale; the tunnel doesn't carry it. */
  | "private";

export type Service = {
  name: string;
  description: string;
  url: string;
  access: Access;
  monitor?: string;
  /** Not deployed yet: drawn as a station under construction, not linked. */
  planned?: boolean;
  /** The page the visitor is reading ("you are here"). */
  self?: boolean;
};

export type Line = { id: "apps" | "admin"; name: string; services: Service[] };

export const lines: Line[] = [
  {
    id: "apps",
    name: "Apps",
    services: [
      { name: "lichnovsky.eu", description: "This page", url: "https://lichnovsky.eu",
        access: "public", self: true },
      { name: "Vaultwarden", description: "Passwords", url: "https://vault.lichnovsky.eu",
        access: "public", monitor: "Vaultwarden" },
      { name: "Papra", description: "Documents", url: "https://papra.lichnovsky.eu",
        access: "sign-in", monitor: "Papra" },
      { name: "Jellyfin", description: "Movies & Series", url: "https://tv.lichnovsky.eu",
        access: "private", monitor: "Jellyfin" },
      { name: "Seerr", description: "Watchlist", url: "https://watchlist.lichnovsky.eu",
        access: "private", monitor: "Seerr" },
      { name: "Immich", description: "Photos", url: "https://photos.lichnovsky.eu",
        access: "public", planned: true },
    ],
  },
  {
    id: "admin",
    name: "Admin",
    services: [
      { name: "Argo CD", description: "Deployments", url: "https://argocd.lichnovsky.eu",
        access: "sign-in", monitor: "ArgoCD" },
      { name: "Grafana", description: "Metrics & Logs", url: "https://grafana.lichnovsky.eu",
        access: "sign-in", monitor: "Grafana" },
      { name: "Uptime Kuma", description: "Monitoring", url: "https://status.lichnovsky.eu",
        access: "sign-in", monitor: "Uptime Kuma" },
      { name: "AdGuard Home", description: "DNS & Ad Blocking", url: "https://dns.lichnovsky.eu",
        access: "private", monitor: "Adguard" },
    ],
  },
];

export const statusPage = "https://status.lichnovsky.eu/status/home";
export const repo = "https://github.com/jersyj/lichnovsky";

export const host = (url: string) => new URL(url).host;

/** On the map, sign-in is a `sign-in*` tag and home-only a blue ring (both in the key); a planned
    station gets a written note. Screen readers get all of it in words. */
export const accessText = (s: Service) =>
  s.planned ? "opening soon" : s.access === "private" ? "home and Tailscale only"
  : s.access === "sign-in" ? "sign-in required" : "";

/** A station's accessible name; the status script appends the live state. */
export const stationLabel = (s: Service) =>
  [s.name, s.description, s.self ? "you are here" : accessText(s)].filter(Boolean).join(", ");

/** Stations still under construction, for the "mind the gap" line under the key. */
export const planned = lines.flatMap((l) => l.services).filter((s) => s.planned);
