---
name: lichnovsky.eu
description: The homelab drawn as a transit diagram, with a live status dot in every station.
colors:
  ground: "#ffffff"
  ink: "#0b1b4d"
  ink-soft: "#3d4a73"
  ink-faint: "#69739a"
  rule: "#dde1ec"
  tunnel: "#ee7c0e"
  tunnel-text: "#b35600"
  home: "#a45a00"
  tailscale: "#0098d4"
  tailscale-text: "#0077a8"
  apps: "#9b0056"
  admin: "#9aa3ab"
  admin-text: "#5f6972"
  up: "#10a14d"
  down: "#dc241f"
  wait: "#e0a100"
  bullet-text: "#ffffff"
  night-ground: "#0b1330"
  night-ink: "#eef1fa"
  night-ink-soft: "#b7bfd9"
  night-ink-faint: "#8891b3"
  night-rule: "#232d57"
  night-tunnel: "#f5923a"
  night-tunnel-text: "#f7a660"
  night-home: "#c98a3e"
  night-tailscale: "#2fb3e8"
  night-tailscale-text: "#5cc6ef"
  night-apps: "#d1377f"
  night-admin: "#7c8791"
  night-up: "#2cc46b"
  night-down: "#f0524d"
  night-wait: "#f0b72c"
typography:
  display:
    fontFamily: "Overpass Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "clamp(2.5rem, 6vw, 4.5rem)"
    fontWeight: 800
    lineHeight: 0.95
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "Overpass Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "clamp(2rem, 5vw, 3rem)"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-0.03em"
  title:
    fontFamily: "Overpass Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.1875rem"
    fontWeight: 700
  station-name:
    fontFamily: "Overpass Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Overpass Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
    fontFeature: "tnum"
  label:
    fontFamily: "Overpass Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 600
  line-bullet:
    fontFamily: "Overpass Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 700
    letterSpacing: "0.02em"
  tag:
    fontFamily: "Overpass Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 600
    lineHeight: 1.4
  host:
    fontFamily: "Overpass Mono, ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "14.5px"
    fontWeight: 400
    lineHeight: 1.4
rounded:
  focus: "2px"
  bullet: "4px"
  pill: "999px"
  ring: "50%"
spacing:
  gutter: "clamp(1rem, 3vw, 2.5rem)"
  container: "90rem"
  stop-row: "3.75rem"
  strip-text-inset: "76px"
components:
  line-bullet-apps:
    backgroundColor: "{colors.apps}"
    textColor: "{colors.bullet-text}"
    typography: "{typography.line-bullet}"
    rounded: "{rounded.bullet}"
    padding: "0.1rem 0.55rem 0"
  line-bullet-admin:
    backgroundColor: "{colors.admin-text}"
    textColor: "{colors.bullet-text}"
    typography: "{typography.line-bullet}"
    rounded: "{rounded.bullet}"
    padding: "0.1rem 0.55rem 0"
  station-ring:
    backgroundColor: "{colors.ground}"
    rounded: "{rounded.ring}"
    size: "24px"
  sign-in-tag:
    textColor: "{colors.ink-soft}"
    typography: "{typography.tag}"
    rounded: "{rounded.pill}"
    padding: "0.1rem 0.55rem 0"
  you-are-here:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
    rounded: "{rounded.pill}"
    padding: "0.1rem 0.55rem 0"
  station-row:
    height: "{spacing.stop-row}"
    padding: "0.55rem 0 0.55rem 76px"
---

# Design System: lichnovsky.eu

## Overview

**Creative North Star: "The Night Service Map"**

The whole site is a Beck-style transit diagram of the homelab. Three ways in (Internet through the Cloudflare Tunnel, Home LAN, Anywhere over Tailscale) run left to right into the rpi-01 interchange. The Apps and Admin lines leave it side by side, then split at 45 degrees to a station for every service; this page itself (lichnovsky.eu) is the first station on the Apps line. Nothing is a card, a tile, or a dashboard panel: every service is a white ring on a coloured line, and its live state is the dot inside that ring.

The material is enamel signage: a white ground, station names in corporate navy, flat line colours with no gradients or shading, and one typeface family doing all the work. Density is low and the page is quiet on purpose; the diagram carries the "wow" through geometry and a single drawing-in animation, not ornament. Dark mode is the night service: the same lines, slightly brightened, on a navy ground.

On phones the map becomes the in-carriage line strip: the ways in stack and join at the Pi, then the Apps and Admin rails run down the left edge with one stop per service. It is the same system at a different scale, not a different layout language.

**Key Characteristics:**
- Transit-diagram geometry: horizontal runs and 45-degree bends only, round line joins.
- Flat line colours from the London palette; status colours reserved for status.
- White ring stations with an ink stroke; the status dot sits inside the ring.
- Stations say name and description; access is a mark (an outlined "sign-in*" tag for sign-in, a Victoria Blue ring for home-only), and hostnames appear only when a map station is pointed at.
- Overpass for everything, Overpass Mono only for hostnames.
- Light and night variants follow the system colour scheme.
- One drawing-in sequence on load and one route-highlight interaction; reduced motion shows the finished map.

## Colors

A white-enamel ground with navy ink, five flat line colours, and three status colours that appear nowhere else.

### Primary
- **Corporate Navy** (ink): station names, headings, ring strokes, the interchange outline, the "You are here" pill, focus rings, text selection. The system's single voice.

### Secondary (the lines)
- **Overground Orange** (tunnel): the Internet way in through the Cloudflare Tunnel.
- **Deep Overground Orange** (tunnel-text): the text form of Overground Orange, used only for the asterisk (800) in the "sign-in*" tag on the map, the strip and the key, where it reads as "required".
- **Bakerloo Brown** (home): the Home LAN way in.
- **Victoria Blue** (tailscale): the Tailscale way in, and the ring stroke of every home-and-Tailscale-only station.
- **Deep Victoria Blue** (tailscale-text): the text form of Victoria Blue, reserved for Victoria Blue read as text. Still defined in both modes, but no element uses it now that the written access notes are gone.
- **Metropolitan Magenta** (apps): the Apps line and its bullet.
- **Jubilee Grey** (admin): the Admin line.
- **Slate Grey** (admin-text): the Admin bullet's fill behind white text, where Jubilee Grey is too light to carry it. Same value in both modes.
- **Bullet White** (bullet-text): text on line bullets, constant across light and night.

### Tertiary (status only)
- **Signal Green** (up): a running service's dot, the overall "all running" dot, and the "you are here" station.
- **Signal Red** (down): a down service's dot.
- **Signal Amber** (wait): pending or maintenance, and the overall dot when status is unavailable.

### Neutral
- **Enamel White** (ground): page ground and the fill inside every ring and the interchange.
- **Soft Navy** (ink-soft): descriptions, the role line, the about sentence and its guide, the sign-in tag's text, the key's secondary text.
- **Faint Navy** (ink-faint): hostnames, the sign-in tag's outline, the "opening soon" note, the platform notice, the "checked" stamp, planned stations, the no-data dot (at 0.35 opacity), scrollbar thumb.
- **Pale Rule** (rule): the 1px dividers under the header and above the key.

Night variants (`night-*`) replace each token one for one under `prefers-color-scheme: dark`; the lines lift in lightness so they hold on navy.

### Named Rules
**The Green Belongs To Status Rule.** Green, red and amber mean up, down and pending, nothing else. No line, link, accent or decoration may use them.

**The Text-Tone Pair Rule.** When a line colour must be read as text or carry white text (Overground Orange, Victoria Blue, Jubilee Grey), use its `-text` partner token, never the line colour itself.

## Typography

**Display Font:** Overpass Variable (with ui-sans-serif, system-ui)
**Body Font:** Overpass Variable
**Label/Mono Font:** Overpass Mono (with ui-monospace, SFMono-Regular, Menlo)

**Character:** Overpass is the highway-signage face: open, legible at a distance, and at home on a diagram. The mono cut appears only where the content is literally a machine name.

### Hierarchy
- **Display** (800, clamp(2.5rem, 6vw, 4.5rem), 0.95): the `lichnovsky.eu` wordmark in the header, tightly tracked (-0.035em).
- **Headline** (800, clamp(2rem, 5vw, 3rem), 1): page-level headings on secondary pages such as the 404.
- **Title** (700, 1.1875rem): the owner's name beside the role line (role in 500, ink-soft).
- **Station name** (700, 1.0625rem strip / 20px map units, 1.3): the service name at each stop. The interchange name is the heaviest map label (800, 24px map units).
- **Body** (400, 16px, 1.5): running text, tabular numerals everywhere; the about line caps at 36rem.
- **Label** (600, 0.875rem): key entries, and the planned station's "opening soon" note (ink-faint; 0.84375rem strip, 14.5px map units). The platform notice under the key is smaller still (400, 0.8125rem, ink-faint).
- **Tag** (600, 0.75rem strip / 14.5px map units / 0.8125rem key, 1.4): the "sign-in*" tag in ink-soft, its asterisk at 800 in Deep Overground Orange. The "You are here" pill shares the size at 700 (14px map units).
- **Line bullet** (700, 0.8125rem strip / 15px map units, +0.02em): the line name on its coloured bullet.
- **Host** (Overpass Mono 400, 14.5px map units): subdomain hostnames, map only, shown on hover or focus.

### Named Rules
**The Mono Is For Machines Rule.** Overpass Mono appears only on hostnames. Labels, notes, status text and headings stay in Overpass.

**The 12px Floor Rule.** No map text renders below 12px at any viewport; between 1000px and 1120px the small map labels lift to 16px map units and the sign-in tag and "You are here" pill scale 1.15 to hold the floor.

## Layout

A single centred column, `min(90rem, 100% - 2 × gutter)` with a fluid gutter, top padding `clamp(1.75rem, 5vh, 3.5rem)`. The header is one flex row that wraps: the wordmark block left (wordmark, name and role, one about sentence), status and GitHub right, aligned to the baseline end, closed by a 1px rule. The about sentence ("Self-hosted services, deployed with GitOps.") is followed by a guide that matches the map in front of you: "Point at a station to see the route, click to open it." from 62.5rem with `(hover: hover)`, "Tap a station to see the route, tap again to open it." otherwise. The map follows full-width, then the key (a two-column grid, heading spanning both rows, closed above by a rule), then, while any station is planned, the platform notice 1.75rem below the key. There is no footer.

The map is an SVG drawn in fixed viewBox units (1240 wide) and scaled to the column; station positions are computed from the data, spread evenly along each line after the split, with labels alternating above and below the line. Each label stack is built from rows: the hostname is always outermost, so it can appear without moving anything; then name and description; and the tag, note or pill after the description (above the line it sits between the description and the line, below the line it sits under the description). Each row sits from its neighbour by the larger of the two rows' gaps (description 22, tag 23, note 20, pill 22, host 25 map units).

Breakpoints: from 62.5rem the map shows; below it the line strip replaces it. Below 40rem the key collapses to a single column and its lists stack vertically. Strip stops have a 3.75rem minimum row height, a 76px text inset clear of the rails, and rails at 24px (Apps) and 44px (Admin) from the left edge.

## Elevation & Depth

Flat. There are no shadows, blurs or layered surfaces anywhere; depth is conveyed only by line order, the white fill inside rings covering the line beneath, and opacity. The only box-shadow is the strip's focus ring (a ground-coloured 3px gap then a 2px ink ring), which is a focus device, not elevation.

### Named Rules
**The Enamel Rule.** Every surface is flat printed colour. Dimming (opacity 0.16) is the only way something recedes.

## Shapes

The geometry is the transit diagram's: straight runs and 45-degree bends, round stroke joins, lines 12 map units thick (8px on the strip). Termini are short perpendicular bars in the line colour; intermediate points (Cloudflare, Tunnel, Tailscale) are small ticks. Stations are circles: ring radius 12 with a 4-unit ink stroke and a 5.5-radius dot. The interchange is a stadium (fully rounded rectangle) with a 5-unit ink stroke (4px on the strip, laid horizontal). Line bullets are gently rounded rectangles (4px). The "You are here" marker and the sign-in tag are full pills: the pill is solid ink, the tag an outline only (1.5 ink-faint stroke, no fill; 80 × 21 map units). Dashes mean "not open yet": planned line sections (10/8 dash, reduced opacity) and planned station rings (4/3.5 dash, ink-faint).

## Components

### Station (signature)
Ring, dot, name and description. Nothing else is written at rest.
- **Ring:** ground fill, ink stroke; Victoria Blue stroke for home-and-Tailscale-only stations; dashed ink-faint for planned ones, with no dot.
- **Dot:** ink-faint at 0.35 opacity until status arrives, then Signal Green, Red or Amber at full opacity. Dots light in reading order (70ms stagger per station, 0.4s fade). This page's own station is always green.
- **Hover / Focus:** the station name takes a 2px underline offset 3px. On the map, the ring stroke thickens to 5 on focus; on the strip, the ring gains the ground-gap ink focus ring.
- **Access marks:** a sign-in station carries the "sign-in*" tag under its description; a home-and-Tailscale-only station is marked by its Victoria Blue ring alone. The full access words ("sign-in required", "home and Tailscale only") live in the station's accessible name; the strip's tag is hidden from assistive tech.
- **Hostname:** on the map, the Overpass Mono hostname is transparent at rest and fades in (0.25s, the route easing) when the station is hovered or focused. The strip never shows hostnames.
- **Planned:** name in ink-faint, description, then "opening soon" in the Label style; no hostname, not linked.
- **This page:** lichnovsky.eu is the first station on the Apps line, an ordinary ring with "This page" as its description and the "You are here" pill in the tag's place; no hostname, dot always green.

### Route Highlight (signature interaction, map only)
Hovering or focusing a station dims every way in, line and other station to 0.16 opacity (only the interchange stays lit) and keeps its real route lit: its own line, Home LAN and Tailscale, plus the Internet line unless the station is home-and-Tailscale only. 0.25s on `cubic-bezier(0.16, 1, 0.3, 1)`.

On touch, the first tap selects a station (`data-selected`) and shows the same route; the second tap opens it, and tapping elsewhere or pressing Escape clears it. Mouse and keyboard open at once. On the strip, the selected stop reveals its hostname and a solid ink "Open" pill (0.8125rem, 700), gains a 4px halo in its line colour, and the rest fades: other stops to 0.3, the other line's rail and badge, and the Internet line for a home-only stop, to 0.2. The touch guide in the header reads "Tap a station to see the route, tap again to open it."

On phones (below 40rem) the strip is one block, at most 18rem wide, centred in the page: the rails sit on its left edge, and the way-in labels and stop text share one left edge 88px in. From 40rem up to the map (landscape phones, portrait tablets), the strip splits into two columns: Apps stays on the left rail, and Admin leaves the Pi as a horizontal branch into its own column on the right, with stop text starting 56px in instead of 88px.

### Drawing In (load motion, map only)
Lines draw from their start (0.9s, ways in staggered 0.05s/0.12s/0.19s), the interchange appears at 0.45s, the out lines draw from 0.55s over 1.1s, stations fade in from 0.8s with a 45ms stagger, planned sections at 1.4s. All of it is inside `prefers-reduced-motion: no-preference`; otherwise the finished map shows.

### Line Bullet
A line's name on its colour: white bold text, 4px corners, slightly tracked. Apps uses Metropolitan Magenta; Admin uses Slate Grey.

### You Are Here
Ink pill with ground-coloured text, 700, uppercase, +0.04em tracking (132 × 23 map units with 14px text; 0.75rem on the strip; scaled 1.15 on the map below 70rem). Used once, on the station for the page being read.

### Sign-in Tag
An outlined pill reading "sign-in*": no fill, ink-faint border, ink-soft 600 text, the asterisk in Deep Overground Orange at 800 reading as "required", as on a form. On the map it is 80 × 21 units with a 1.5 stroke and 14.5 text, scaled 1.15 below 70rem; on the strip a 1.5px border, 0.75rem type, 0.3rem above it; in the key 0.8125rem.

### Status Line
A 0.625rem dot followed by the summary link (ink, 600, no underline until hover) and a "checked HH:MM" stamp in ink-faint. The dot starts ink-faint at 0.4 opacity and takes the status colour when data arrives.

### Key
The key explains only what the map cannot say by itself (every line is already named on the map): station swatches are miniature rings (1.125rem, 3px ink border) for running, down, pending, no status data, home & Tailscale only (Victoria Blue ring) and opening soon (dashed), followed by the sign-in tag and "through Cloudflare Access". The entries wrap as one flowing row at every size; on phones the key and the platform notice sit in the same centred 18rem column as the strip.

### Platform Notice
One line under the key, 0.8125rem ink-faint, in transit-announcement wording. Its notices share one grid cell, so the line keeps the height of the longest and never shifts the page, and they take turns every 7 s with a 0.6s opacity crossfade (an instant swap under reduced motion). There are three: live status from Uptime Kuma ("Good service on all lines." / "Minor delays on the Admin line." / "Severe delays on the Apps line." / "Service information is unavailable right now."), one per planned station ("Photos: station closed for engineering works."), and the sign-in barrier ("Please have your ticket ready: sign-in* stations check at the barrier.", with `sign-in` in ink-soft 600 and the asterisk in Deep Overground Orange). While a service is down, the live notice holds the board and the rotation pauses.

### Links
Inherit colour, 1px underline offset 0.2em; focus is a 2px ink outline offset 3px with 2px corners. Secondary links (GitHub) sit in ink-soft without underline and gain ink and underline on hover. The GitHub link (github.com/jersyj/lichnovsky) carries an inline 16px mark in currentColor.

## Do's and Don'ts

### Do:
- **Do** draw every new route with horizontal runs and 45-degree bends only, 12-unit lines with round joins.
- **Do** add a service as a new station on its line from `services.ts`; never hand-place markup.
- **Do** put status in the dot inside the ring, and expose it as text too (title, accessible name, summary line).
- **Do** use the `-text` partner token whenever a line colour is read as text or carries white text.
- **Do** mark access with the system's own devices (the outlined "sign-in*" tag with its asterisk in tunnel-text, the Victoria Blue ring for home-only), explain both in the key, and put the words in the accessible name.
- **Do** show "not open yet" with dashes: dashed line sections and dashed ink-faint rings.
- **Do** keep every animation inside `prefers-reduced-motion: no-preference` and show the finished state otherwise.

### Don't:
- **Don't** use green, red or amber for anything except status.
- **Don't** add cards, tiles, icon grids, shadows or gradients; the world is flat enamel signage.
- **Don't** use Overpass Mono for anything but hostnames.
- **Don't** let map text fall below 12px rendered.
- **Don't** bend a line at any angle other than 45 degrees.
