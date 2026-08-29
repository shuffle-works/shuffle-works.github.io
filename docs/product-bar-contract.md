# Shuffle Works product-bar contract

This is the contract between `shuffle-works-site` (the hub, sole publisher
of every product surface) and the product pages it publishes. The hub
unifies the product bar, footer, and controls row entirely through
publish-time injection in `scripts/sync-static-sites.sh`, applied to a
copy of each product's build output. It never edits a product's tracked
source.

## What the hub guarantees

`[data-shuffle-product-bar]` exists in the DOM before any product bundle
runs. For a static page, the hub injects the product-bar markup as static
HTML before `<body>`'s own content, so it is present pre-hydration,
before any client-side JavaScript (yours or a framework's) executes. That
injected bar already carries a `Reference` link and a `GitHub` link
(`.header-link` / `.header-link.github`), identical on every surface, so
a product's own header should not duplicate them.

## What a static page should do

Mark only the controls the hub doesn't already provide (a theme toggle,
page-specific in-product navigation) with `data-shuffle-page-controls` on
the containing element. The hub's injected hoist script finds that marker
at runtime and relocates it onto the shared product bar's own row, so
your page ends up with one merged bar instead of two stacked ones. You do
not need to add that marker yourself if the hub's injection pipeline can
key off a stable enough selector to add it for you at publish time (as it
does for `spark-tuning-reference`'s `landing.html`, which only marks its
theme-toggle button this way: its Reference/GitHub links come from the
hub's bar instead).

## What a client-rendered page should do

A vanilla-JS DOM relocation, the technique the hoist script uses for a
static page, does not work here. Physically moving a DOM node with plain
JS carries it outside your framework's root, where React 18's
root-delegated synthetic event listeners (and equivalents in other
frameworks) can no longer reach it: a click handler on a relocated node
silently stops firing, with no console error. This was confirmed by a
live click-and-check in a browser, not just a visual screenshot.

Portal your own controls into
`document.querySelector('[data-shuffle-product-bar]')`, for example via
`ReactDOM.createPortal`. A portal keeps your component's event handling
wired to its own fiber tree regardless of where its target DOM node
lives, so this works even though the target element was never rendered
by your own app.

The hub cannot do this for you: it only ever processes a copy of your
build output as static files. A portal call has to exist in your own
component's source before that output is built.
