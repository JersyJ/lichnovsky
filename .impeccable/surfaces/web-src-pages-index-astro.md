---
version: 1
slug: "web-src-pages-index-astro"
primary_target: "web/src/pages/index.astro"
related_targets: ["web/src/pages/404.astro"]
---

# Home page (lichnovsky.eu `/`)

Scope: the start page at `/`, plus the 404 in the same world. Visitor mode: Experience; the living system leads, with Operate constraints (a friend finds their service in one click).

Audience: tech peers (who runs this, on what) and friends & family (which link, is it working). Proof is the real service list and live Uptime Kuma state; no invented metrics.

Constraints: every service shown, admin and home-only ones marked (symbols + key, the user asked for less text); availability is one quiet dot per station; one data entry per service; the page must still read correctly with no status data. The user rejected looking like a template and the green-on-black hacker cliché.

## Direction contract

THESIS: The homelab drawn as a Beck-style transit diagram: three ways in (Tunnel, Home LAN, Tailscale) converge at the rpi-01 interchange, and the Apps and Admin lines run out to a station for every service. It refuses the dashboard card grid of icon tiles.

OWN-WORLD: White enamel ground, station names in corporate navy, flat line colours (Overground orange tunnel, Bakerloo brown home, Victoria blue Tailscale, Metropolitan magenta apps, Jubilee grey admin), 45° geometry only, white ring stations with ink stroke, status as the dot inside the ring (green up, red down, amber pending; green belongs to status only). Overpass for all type, Overpass Mono for hosts only. Night variant: navy ground, same lines.

STORY: The visitor sees how a request reaches the Pi and where each service sits. Peers read the architecture from the diagram; friends find their station, see the dot, click.

FIRST VIEWPORT: Compact header row: `lichnovsky.eu` large with Dominik's name, role, a one-line description (self-hosted services, GitOps) and a guide matched to the input (point on the map, tap on the strip); overall status and the repo link at the right. Below it the full-width map (desktop ≥1000px): ways in on the left converging at the rpi-01 interchange centre-left, Apps line up to the right with 5 stations (lichnovsky.eu "you are here", Vaultwarden, Papra, Jellyfin, Immich opening soon), Admin line down to the right with 4. Stations show name and description; hosts appear on pointing; sign-in is an outlined `sign-in*` tag; home-only is the blue ring; the key explains all of it, and a "Mind the gap" line under it names what is still under construction. Phones get a vertical line-strip diagram, the in-carriage version of the same map.

SIGNATURE INTERACTION: Hovering or focusing a station lights its real route and dims the rest; a home-only station turns the Internet line off. On load, the lines draw from the ways in through the interchange to the ends, then the status dots light in reading order. Reduced motion shows the finished map.

FORM: Line Map, candidate 1 of 7 on the ordered list (chosen as Impeccable's pick over the roll); seed key 7af4d494.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
