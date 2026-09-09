---
name: Shuffle Works
description: Local-first tools for reading Spark event logs, catching PySpark schema drift, and tuning shuffle-heavy jobs
colors:
  bg: "#080b0d"
  bg-elevated: "#11171a"
  text: "#f4f4f5"
  text-muted: "#a9b5b4"
  accent: "#ff6b2c"
  accent-hover: "#ff8a4f"
  signal: "#39d6b5"
  on-accent: "#11110f"
  border: "#233035"
typography:
  display:
    fontFamily: "'Recursive', -apple-system, BlinkMacSystemFont, sans-serif"
    fontWeight: 700
  body:
    fontFamily: "'Recursive', -apple-system, BlinkMacSystemFont, sans-serif"
    lineHeight: 1.55
  label:
    fontFamily: "'JetBrains Mono', ui-monospace, monospace"
rounded:
  card: "0.75rem"
  pill: "999px"
  control: "0.35rem"
  focus-ring: "4px"
  focus-ring-sm: "0.2rem"
spacing:
  xs: "0.5rem"
  sm: "0.75rem"
  md: "1rem"
  lg: "1.5rem"
  xl: "2rem"
  2xl: "3rem"
  3xl: "4rem"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.pill}"
  project-card-featured:
    backgroundColor: "{colors.bg-elevated}"
    textColor: "{colors.text}"
    rounded: "{rounded.card}"
---

# Design System: Shuffle Works

## Overview

**Creative North Star: "The Forensics Bench"**

Shuffle Works is a family of local-first Spark diagnostic tools: a landing hub, a zero-backend event-log analyzer (SparkForensics), a schema-contract checker (sparkenforce), and a tuning reference. The visual system reads as an evidence bench, not a marketing page: dark by default (the color scheme of a terminal or a log viewer), a single hot accent used sparingly for calls to action and live signal, and a second cooler accent reserved for confirmation and "this is working" states. Monospace type appears only where it's earned (config strings, metrics, tags), never as a blanket "technical" costume.

Confirmed rejections: no hero-metric dashboards on the marketing surfaces, no gradient text, no glassmorphism, no card-in-card nesting.

**Key Characteristics:**
- Dark-first, with a fully-specified light theme (`[data-theme]` attribute wins over `prefers-color-scheme`, which wins over the CSS default)
- One warm accent (orange) for action and emphasis, one cool accent (teal) reserved for confirmation/signal language, never used interchangeably
- Recursive (variable font) for prose, JetBrains Mono for anything that reads as data or config
- Directional, low-opacity accent-tinted shadows as the family's one depth signature, never a zero-offset "glow"

## Colors

Two token sets exist, selected by `[data-theme="dark"|"light"]` on `<html>` (see `shuffle-works-tokens.css`, the single source of truth every product in the family imports or aliases against; see the Named Rule below).

### Primary
- **Signal Orange** (`#ff6b2c` dark / `#bf4413` light): the one warm accent. CTAs, focus rings, hover shadows, active states. Used on a minority of any given screen; see the One Accent Rule.

### Secondary
- **Confirmation Teal** (`#39d6b5` dark / `#00695a` light): reserved for "this succeeded, this is evidence" language, used in the `.proof-list` labels and signal metrics. The light-theme value was deepened from an earlier `#007e6b` (4.7:1 contrast, the thinnest margin in the palette) to `#00695a` (6.2:1 against `--color-bg`, 6.6:1 against `--color-bg-elevated`) to give it real headroom without shifting its hue identity.

### Neutral
- **Ink** (`#f4f4f5` dark text / `#151b1e` light text): body copy.
- **Ash** (`#a9b5b4` dark / `#4f5f60` light): muted/secondary text.
- **Void** (`#080b0d` dark bg / `#f7f8f4` light bg): page background.
- **Panel** (`#11171a` dark / `#ffffff` light): card and raised-surface background.
- **Seam** (`#233035` dark / `#dbe2df` light): borders and dividers.

### Named Rules
**The One Accent Rule.** Orange means "act here." Teal means "this is confirmed." A screen never uses both for the same kind of affordance: mixing them dilutes the one-glance read that a Spark diagnostics tool depends on.

**The Alias, Don't Redefine Rule.** `shuffle-works-tokens.css` is published from the hub and injected into every downstream product page at publish time (`scripts/sync-static-sites.sh`). Subprojects alias their local variable names to these canonical tokens (`--accent: var(--color-accent)`) rather than redefining the palette. SparkForensics' compiled bundle and the VitePress docs both currently match the shared tokens hex for hex, verified during the 2026-09 audit.

## Typography

**Display Font:** Recursive (variable, weights 400 to 700, with a `CASL` casual axis available)
**Body Font:** Recursive
**Label/Mono Font:** JetBrains Mono (weights 400/500/600)

**Character:** Recursive gives the family one typeface that can flex from a slightly casual, approachable register (the `CASL` axis) to a neutral technical one, so the same font family covers both the landing page's voice and the docs' reference-manual register without a font switch.

### Hierarchy
- **Display** (700, `clamp` fluid, tight line-height): hub `<h1>`, product-card names.
- **Body** (400, 1.1 to 1.4rem fluid, line-height 1.55): tagline and section copy.
- **Label** (600, 0.78 to 0.85rem, uppercase where used, JetBrains Mono): tag chips, evidence-list pills, the `.proof-list` metric labels.

### Named Rules
**The Hub-Only Casual Rule.** `font-variation-settings: "CASL" 0.15` is applied to `body` in `styles.css` only. This is a deliberate, hub-only detail: the flagship landing page gets one small distinguishing letterform touch that the SparkForensics app shell and the VitePress docs (both compiled from separate build pipelines this repo doesn't own the source of) don't carry. This is an intentional scope boundary, not an inconsistency to fix. Extending it would mean hand-patching vendored, hash-named compiled CSS on every resync, which is a worse trade than the letterform difference it would close.

## Layout

Container max-width 72rem, centered. Spacing scale runs `--space-2` (0.5rem) through `--space-16` (4rem) in a roughly-doubling progression with a couple of in-between steps (`--space-3`, `--space-6`). Fluid type and spacing lean on `clamp()` throughout `styles.css` rather than fixed breakpoint jumps; hard breakpoints exist mainly for grid reflow (project cards, evidence list).

## Elevation & Depth

Flat at rest; shadows appear only as a hover/focus response, and every shadow in the hand-authored CSS is directional and accent-tinted rather than a neutral drop shadow or a symmetric glow.

### Shadow Vocabulary
- **CTA rest** (`box-shadow: 0 8px 8px -8px color-mix(in srgb, var(--color-accent) 60%, transparent)`, `styles.css:241`): `.org-cta` at rest.
- **CTA hover** (`0 8px 8px -6px color-mix(in srgb, var(--color-accent) 70%, transparent)`, `styles.css:248`): intensifies on hover.
- **Card hover** (`0 16px 32px -16px color-mix(in srgb, var(--color-accent) 40%, transparent)`, `styles.css:402`): `.project-card:hover`.

### Named Rules
**The Directional-Only Rule.** Every shadow in this system carries a non-zero vertical offset and a negative spread, so it reads as light falling on a lifted element, not as a halo. A zero-offset, symmetric colored glow is out of bounds here even though the palette itself is saturated. Don't let the accent-tinted shadow rule get confused with the "glowing shadow accent" anti-pattern flagged by generic AI-slop detectors; see Known Detector False Positives below.

## Shapes

Radius: `0.75rem` for cards, `999px` (full pill) for tags and the evidence-list chips, `0.35rem` for smaller controls (product-bar nav items, the skip link), and `4px`/`0.2rem` for focus-ring outlines. The two focus-ring values predate this pass and live in different stylesheets: `styles.css` uses `4px`, `shuffle-works-footer.css`/`shuffle-works-product-bar.css` use `0.2rem`. They read as close enough visually that unifying them wasn't part of this scope. No hard-edged neobrutalist shadows; no clipped/masked geometry.

## Components

### Buttons
- **Shape:** pill (`border-radius: 999px`) via `.org-cta`.
- **Primary:** accent background, `--color-on-accent` text, directional accent shadow (see Elevation).
- **Hover:** shadow intensifies (60% to 70% accent mix), no layout shift.

### Chips / Tags
- **Style:** `.tag-list` and `.evidence-list li` use a pill shape, `--font-mono`, small sizing, a border, and a tinted background via `color-mix`.

### Cards
- **Corner Style:** `0.75rem`.
- **Background:** `--color-bg-elevated`.
- **Shadow Strategy:** directional accent shadow on hover only (see Elevation).
- **Variants:** `.project-card-featured` (SparkForensics, larger and visually weighted) vs. `.project-card-supporting` (sparkenforce, spark-tuning-reference).

### Navigation
- **Hub:** custom header, brand mark plus GitHub link plus theme toggle; no shared product bar (the hub is the root of the family, not a sibling product; see `docs/product-bar-contract.md`).
- **Product pages:** shared `shuffle-product-bar` injected at publish time, carrying a brand link, current-product tab (`aria-current="page"`), Reference link, GitHub link, and theme toggle. Identical across every synced product surface.
- **Skip link:** first focusable element in `<body>` on the hub's own pages (`index.html`, `404.html`), visually hidden until focused, jumping to `id="main"`. VitePress docs ship their own equivalent; the SparkForensics app shell gets a matching one via the shared product-bar injection.

## Do's and Don'ts

### Do:
- **Do** treat `shuffle-works-tokens.css` as the only place color/type/space primitives are defined; alias, don't redefine.
- **Do** keep shadows directional (non-zero offset, negative spread) and accent-tinted, never a symmetric colored halo.
- **Do** use JetBrains Mono only for things that are actually data, config, or measurement, not as a general "technical" flourish.

### Don't:
- **Don't** mix the orange (action) and teal (confirmation) accents for the same kind of affordance on one screen.
- **Don't** hand-edit vendored/synced product output (`sparkforensics/`, its docs) directly for anything that needs to survive the next `scripts/sync-static-sites.sh` resync. Fix it in the sync script's injection logic instead, per `docs/product-bar-contract.md`.
- **Don't** treat every `impeccable detect` finding on this codebase at face value; check Known Detector False Positives below first.

## Known Detector False Positives

Recorded here so future `/impeccable audit` or `/impeccable detect` runs don't re-flag the same non-issues. `dark-glow` findings on `index.html` and `404.html` (the `.org-cta`/`.project-card` accent shadows documented in Elevation & Depth above) are suppressed via `.impeccable/config.json` (`detector.ignoreValues`, scoped per file) with the reasoning recorded in that config. Not yet suppressed, but verified false positives if `impeccable detect` re-surfaces them:
- `cramped-padding` on `index.html`'s `.proof-list li`: the element has `padding: clamp(1rem, 2vw, 1.35rem) var(--space-6)` (styles.css); the detector was reading the wrong box.
- `side-tab`, `overused-font` (Inter), and `gradient-text` findings inside `sparkforensics/docs/assets/style.*.css`: all three are VitePress's own stock default-theme CSS output, not code authored in this repo.
- `em-dash-overuse` on VitePress-rendered docs pages: the regex was counting Vue SSR comment markers (`<!--[-->`), not literal em-dashes.
- `design-system-color` on `index.html`/`404.html`: Stitch's frontmatter schema holds one flat `colors:` map, with no field for a second theme. Every light-theme render (and every `color-mix()`-derived tint) reads as "outside DESIGN.md colors" even though the light values are fully documented in the Colors prose above and traceable to `shuffle-works-tokens.css`. Scoped off via `.impeccable/config.json` rather than left to reappear every scan.
- `design-system-color` on `partials/shuffle-works-footer.html`: this is a bare fragment with no `<html>`/`<head>`/stylesheet, the injection source snippet `scripts/sync-static-sites.sh` splices into product pages, never served on its own.
- `design-system-color` on `spark-tuning-reference/index.html`: the redirect stub is intentionally zero-CSS (meta-refresh + JS `location.replace`); its one fallback `<p>` renders in the browser default color on purpose, for the rare case JS and the refresh both fail.
- `design-system-color`/`design-system-radius`/`design-system-font` inside `sparkforensics/**`: vendored SparkForensics/VitePress build output, outside this repo's design authority per `docs/product-bar-contract.md`.
