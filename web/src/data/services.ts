// Everything the start page links to. `monitor` is the monitor's name on the public Uptime Kuma
// status page "home"; cards without one show no status dot.
import type { IconName } from "../components/Icon.astro";

export type Service = {
  name: string;
  description: string;
  url: string;
  icon: IconName;
  monitor?: string;
  /** Only reachable at home and over Tailscale. */
  private?: boolean;
};

export const groups: { title: string; services: Service[] }[] = [
  {
    title: "Apps",
    services: [
      { name: "Vaultwarden", description: "Passwords", url: "https://vault.lichnovsky.eu",
        icon: "key", monitor: "Vaultwarden" },
      { name: "Papra", description: "Documents", url: "https://papra.lichnovsky.eu",
        icon: "file", monitor: "Papra" },
      { name: "Jellyfin", description: "Movies & shows", url: "https://tv.lichnovsky.eu",
        icon: "play", monitor: "Jellyfin", private: true },
    ],
  },
  {
    title: "Admin",
    services: [
      { name: "Argo CD", description: "Deployments", url: "https://argocd.lichnovsky.eu", icon: "git" },
      { name: "Grafana", description: "Metrics & logs", url: "https://grafana.lichnovsky.eu",
        icon: "chart", monitor: "Grafana" },
      { name: "Uptime Kuma", description: "Monitoring", url: "https://status.lichnovsky.eu", icon: "pulse" },
      { name: "AdGuard Home", description: "DNS & ad blocking", url: "https://dns.lichnovsky.eu",
        icon: "shield", monitor: "Adguard", private: true },
    ],
  },
];

export const statusPage = "https://status.lichnovsky.eu/status/home";
