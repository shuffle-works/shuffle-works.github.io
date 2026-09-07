#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLISH_ROOT="${PUBLISH_ROOT:-$REPO_ROOT}"
PRODUCT_BAR_STYLESHEET="$REPO_ROOT/shuffle-works-product-bar.css"
DESIGN_TOKENS_STYLESHEET="$REPO_ROOT/shuffle-works-tokens.css"
FOOTER_STYLESHEET="$REPO_ROOT/shuffle-works-footer.css"
FOOTER_PARTIAL="$REPO_ROOT/partials/shuffle-works-footer.html"

# The Spark reference now ships embedded in the SparkForensics bundle; this is
# where its entry page is published.
REFERENCE_LANDING_PATH="/sparkforensics/vendor/spark-doc/landing.html"

if [ "$#" -gt 1 ]; then
  echo "error: expected at most one SparkForensics ref" >&2
  exit 64
fi

FORENSICS_REF="${1:-main}"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: GitHub CLI (gh) is required" >&2
  exit 1
fi

if ! gh auth status; then
  echo "error: authenticate GitHub CLI with: gh auth login -h github.com" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

CHECKOUT_DIR="$WORK_DIR/checkout"
STAGED_DIR="$WORK_DIR/staged"
mkdir -p "$CHECKOUT_DIR" "$STAGED_DIR"

clone_repo() {
  local repository=$1 target=$2 ref=$3
  if ! gh repo clone "$repository" "$target" -- --depth 1 --branch "$ref"; then
    echo "error: could not fetch $repository at ref $ref" >&2
    exit 1
  fi
}

stage_tree() {
  local source=$1 target=$2
  mkdir -p "$target"
  cp -R "$source"/. "$target"/
}

# Product bar entries: surface key, label, href. One list drives every
# surface's markup so adding/renaming a product only means editing this one
# place instead of a hand-copied literal per surface.
PRODUCT_BAR_KEYS=(sparkforensics spark-tuning-reference)
PRODUCT_BAR_LABELS=("SparkForensics" "Spark Tuning Reference")
PRODUCT_BAR_HREFS=("/sparkforensics/" "/sparkforensics/vendor/spark-doc/landing.html")

# Identical on every surface (docs/product-bar-contract.md), unlike the
# per-surface arrays above. Wrapped in its own flex group (CSS: margin-left:
# auto) so it, and whatever page control gets hoisted after it, sit
# right-aligned instead of trailing directly after the product tabs.
PRODUCT_BAR_HEADER_LINKS='<span class="shuffle-product-bar__end"><a class="header-link" href="/sparkforensics/vendor/spark-doc/chapters/spark/index.html">Reference</a><a class="header-link github" href="https://github.com/shuffle-works" target="_blank" rel="noopener">GitHub <span aria-hidden="true">↗</span></a></span>'

product_bar_markup() {
  local current_surface=$1 i key label href current_attr links=""
  local known=0

  for i in "${!PRODUCT_BAR_KEYS[@]}"; do
    key="${PRODUCT_BAR_KEYS[$i]}"
    label="${PRODUCT_BAR_LABELS[$i]}"
    href="${PRODUCT_BAR_HREFS[$i]}"
    current_attr=""
    if [ "$key" = "$current_surface" ]; then
      current_attr=' aria-current="page"'
      known=1
    fi
    links+="<a class=\"shuffle-product-bar__product\" href=\"$href\"$current_attr>$label</a>"
  done

  if [ "$known" -ne 1 ]; then
    echo "error: unknown product surface: $current_surface" >&2
    exit 1
  fi

  printf '%s' "<header class=\"shuffle-product-bar\" data-shuffle-product-bar><nav class=\"shuffle-product-bar__nav\" aria-label=\"Shuffle Works products\"><a class=\"shuffle-product-bar__brand\" href=\"/\">Shuffle Works</a>${links}${PRODUCT_BAR_HEADER_LINKS}</nav></header>"
}

footer_markup() {
  cat "$FOOTER_PARTIAL"
}

# Some host pages carry a leftover bare `footer { padding: ... }` tag-selector
# rule in their own <style> block, predating the shared footer. The canonical
# footer partial's <footer data-shuffle-footer> element still matches that
# bare tag selector, so its padding stacks on top of .footer-inner's own
# padding, doubling the footer's height. This targets the attribute selector
# specifically (higher specificity than a bare tag selector, so it always
# wins regardless of the host page's own rule's position in the cascade)
# instead of requiring the host page's source to scope its own rule.
footer_override_style() {
  printf '%s' '<style data-shuffle-footer-override>footer[data-shuffle-footer]{padding:0!important}</style>'
}

# Drop any pre-existing (non-canonical) <footer>...</footer> block so it can
# be replaced by the shared one. Handles both a self-contained one-liner and
# a multi-line block, matching how footers actually show up in the wild here
# (SparkForensics' bare dashboard has none; the vendored Spark Tuning
# Reference page ships its own bespoke one).
strip_existing_footer() {
  local page=$1 temp_page
  temp_page="$(mktemp)"

  awk '
    /<footer[ >].*<\/footer>/ {
      sub(/<footer[ >].*<\/footer>/, "")
      print
      next
    }
    /<footer[ >]/ { in_footer=1; next }
    /<\/footer>/ { in_footer=0; next }
    !in_footer { print }
  ' "$page" >"$temp_page"
  mv "$temp_page" "$page"
}

inject_product_footer() {
  local page=$1 temp_page

  if grep -Fq 'data-shuffle-footer' "$page"; then
    return
  fi

  if ! grep -Fq '</body>' "$page"; then
    return
  fi

  if grep -Eq '<footer[ >]' "$page"; then
    strip_existing_footer "$page"
  fi

  temp_page="$(mktemp)"
  awk -v footer="$(footer_markup)" -v override="$(footer_override_style)" '
    index($0, "</body>") { print footer; print override }
    { print }
  ' "$page" >"$temp_page"
  mv "$temp_page" "$page"
}

# A host page can mark its own header controls (product-internal nav, GitHub
# link, theme toggle, ...) with data-shuffle-page-controls to opt into being
# merged onto the shared product bar's row instead of rendering as a second
# stacked bar underneath it. This only takes effect once the product bar is
# actually present, so it's a no-op on a standalone open of the source page.
#
# Tries once immediately (the static-HTML case, e.g. Spark Tuning Reference's
# landing.html, where the marker is already in the document by the time this
# script runs) and falls back to a MutationObserver (the client-rendered
# case, e.g. SparkForensics' React shell, where data-shuffle-page-controls
# doesn't exist in the page source at all — it's only ever produced by the
# app's own JS bundle after mount — so grepping the static HTML for the
# marker can't gate this injection the way inject_product_footer gates on
# <footer>; it's injected unconditionally alongside the product bar instead).
# Inserting the hoisted control after .shuffle-product-bar__end (rather than
# as a sibling of nav, after the whole .shuffle-product-bar__nav block) makes
# it a flex item participating in nav's own flex-wrap, so it wraps onto the
# __end row it's meant to sit beside. A sibling-of-nav placement instead
# centers it against nav's full wrapped height (via the header's own
# single-row flex layout), orphaning it from that row on narrow viewports.
#
# SparkForensics' own bundle already does the merge itself via
# ReactDOM.createPortal(controlsNode, productBarEl) once it finds the bar in
# the DOM, so `controls` can already be a live React-managed node sitting
# inside the bar by the time this runs. Physically relocating it with
# .after() leaves React's fiber still pointing at the bar as that node's
# parent; the next time React tears down or updates it, its removeChild call
# targets a parent the node was silently moved out of and throws
# NotFoundError, which React (with no error boundary here) treats as fatal
# and unmounts the whole app. So: skip the move entirely when `controls` is
# already inside the bar — nothing to hoist, it's already merged — and only
# physically relocate it for the genuinely-separate-header case (e.g. Spark
# Tuning Reference's static pages, never touched by React).
page_controls_hoist_script() {
  printf '%s' '<script data-shuffle-page-controls-hoist>(() => { const tryHoist = () => { const productBar = document.querySelector("[data-shuffle-product-bar]"); const controls = document.querySelector("[data-shuffle-page-controls]"); if (!productBar || !controls) return false; if (productBar.contains(controls)) return true; const bar = productBar.querySelector(".shuffle-product-bar__nav"); if (!bar) return false; const oldHeader = controls.closest("header"); const end = productBar.querySelector(".shuffle-product-bar__end"); (end || bar).after(controls); if (oldHeader && oldHeader !== productBar) { oldHeader.remove(); } return true; }; if (tryHoist()) return; const observer = new MutationObserver(() => { if (tryHoist()) observer.disconnect(); }); observer.observe(document.body, { childList: true, subtree: true }); })();</script>'
}

inject_page_controls_hoist() {
  local page=$1

  if grep -Fq 'data-shuffle-page-controls-hoist' "$page"; then
    return
  fi

  if ! grep -Fq '</body>' "$page"; then
    return
  fi

  inject_before "$page" '</body>' "$(page_controls_hoist_script)"
}

# The product bar's rendered height isn't a constant: the product tabs, the
# Reference/GitHub link group, and a hoisted page control can each wrap it
# onto more rows as the viewport narrows, and which controls get hoisted
# varies by page. CSS consumers that need to sit below the bar (the mobile
# nav-toggle, the sidebar) can't hardcode a single-row height, so this keeps
# a --shuffle-product-bar-height custom property in sync with the bar's
# actual offsetHeight at runtime, resyncing on any resize of the bar itself.
product_bar_height_sync_script() {
  printf '%s' '<script data-shuffle-product-bar-height-sync>(() => { const bar = document.querySelector("[data-shuffle-product-bar]"); if (!bar) return; const sync = () => { document.documentElement.style.setProperty("--shuffle-product-bar-height", bar.offsetHeight + "px"); }; sync(); if (window.ResizeObserver) { new ResizeObserver(sync).observe(bar); } else { window.addEventListener("resize", sync); } })();</script>'
}

inject_product_bar_height_sync() {
  local page=$1

  if grep -Fq 'data-shuffle-product-bar-height-sync' "$page"; then
    return
  fi

  if ! grep -Fq '</body>' "$page"; then
    return
  fi

  inject_before "$page" '</body>' "$(product_bar_height_sync_script)"
}

# SparkForensics marks its dashboard root with data-testid="dashboard" once a
# log is loaded; hide the hub's own bar/footer chrome there so the dashboard
# gets the full viewport instead of losing rows to chrome it didn't ask for.
# Every other page (the landing view, both reference surfaces) never has that
# node, so this is a no-op there — no per-page gating needed.
# Toggles inline style rather than a class: a class could lose a specificity
# fight with the bar/footer's own stylesheet rules, inline style always wins.
# Stays subscribed (no disconnect) since the app can return to the landing
# view — loading a different file, a "start over" action — and the chrome
# needs to reappear then, not just disappear once.
dashboard_chrome_toggle_script() {
  printf '%s' '<script data-shuffle-dashboard-chrome-toggle>(() => { const bar = document.querySelector("[data-shuffle-product-bar]"); const footer = document.querySelector("[data-shuffle-footer]"); if (!bar && !footer) return; const sync = () => { const inDashboard = !!document.querySelector("[data-testid=dashboard]"); if (bar) bar.style.display = inDashboard ? "none" : ""; if (footer) footer.style.display = inDashboard ? "none" : ""; }; sync(); new MutationObserver(sync).observe(document.body, { childList: true, subtree: true }); })();</script>'
}

inject_dashboard_chrome_toggle() {
  local page=$1

  if grep -Fq 'data-shuffle-dashboard-chrome-toggle' "$page"; then
    return
  fi

  if ! grep -Fq '</body>' "$page"; then
    return
  fi

  inject_before "$page" '</body>' "$(dashboard_chrome_toggle_script)"
}

favicon_link_markup() {
  printf '%s' '<link rel="icon" href="/icon.svg" type="image/svg+xml">'
}

inject_favicon() {
  local page=$1

  if grep -Fq 'rel="icon"' "$page"; then
    return
  fi

  if ! grep -Fq '</head>' "$page"; then
    return
  fi

  inject_before "$page" '</head>' "$(favicon_link_markup)"
}

social_meta_markup() {
  local title=$1 description=$2 tags

  tags="<meta property=\"og:site_name\" content=\"Shuffle Works\"><meta property=\"og:type\" content=\"website\"><meta property=\"og:title\" content=\"$title\"><meta name=\"twitter:card\" content=\"summary\"><meta name=\"twitter:title\" content=\"$title\">"
  if [ -n "$description" ]; then
    tags+="<meta property=\"og:description\" content=\"$description\"><meta name=\"twitter:description\" content=\"$description\">"
  fi

  printf '%s' "$tags"
}

# Reuses each page's own <title> and <meta name="description"> instead of
# hand-authoring per-page Open Graph/Twitter-card copy that would drift from
# what's already there. Pages that carry no <title> (none observed here, but
# nothing structurally prevents it) get skipped rather than shipping an
# empty og:title.
inject_social_meta() {
  local page=$1 title description

  if grep -Fq 'property="og:title"' "$page"; then
    return
  fi

  if ! grep -Fq '</head>' "$page"; then
    return
  fi

  # grep -o exits 1 on no match, which (via pipefail, inside a plain
  # assignment) would otherwise trip set -e and abort the whole publish
  # instead of just skipping this one page; `|| true` keeps a missing
  # <title>/description a no-op here.
  title="$(grep -o '<title>[^<]*</title>' "$page" | head -n1 | sed -e 's#^<title>##' -e 's#</title>$##' || true)"
  if [ -z "$title" ]; then
    return
  fi

  description="$(grep -o '<meta name="description" content="[^"]*"' "$page" | head -n1 | sed -e 's#^<meta name="description" content="##' -e 's#"$##' || true)"

  inject_before "$page" '</head>' "$(social_meta_markup "$title" "$description")"
}

# spark-tuning-reference's landing.html ships its own <nav class="header-nav">
# with a Reference link, a GitHub link, and a theme toggle. The hub's
# product_bar_markup() now supplies the Reference/GitHub links itself, so
# marking the whole nav would duplicate those links once they're already
# coming from the hub: only the theme toggle still needs to move. This
# keys the marker's injection off the toggle button's own known, stable
# selector and applies it to the copied build output only, so the vendored
# source never needs the attribute pre-authored into it.
# No grep guard here: the hoist script injected elsewhere on the page also
# contains the literal substring "data-shuffle-page-controls" (in its
# querySelector call), so a broad guard would false-positive on a page that
# already carries the hoist script and silently skip marking the button. The
# sed pattern below only matches the unmarked button (no trailing
# attribute), so it's naturally idempotent on rerun without needing a guard.
mark_page_controls() {
  local page=$1

  sed -i 's|<button id="theme-toggle" class="theme-toggle"|<button id="theme-toggle" class="theme-toggle" data-shuffle-page-controls|' "$page"

  if ! grep -Fq 'data-shuffle-page-controls' "$page"; then
    echo "error: could not mark page controls in $page (theme-toggle selector drifted upstream?)" >&2
    exit 1
  fi
}

inject_product_shell() {
  local page=$1 surface=$2 bar temp_page
  # Tokens first so the shared palette/type are defined before any consumer.
  local stylesheet='<link rel="stylesheet" href="/shuffle-works-tokens.css"><link rel="stylesheet" href="/shuffle-works-product-bar.css"><link rel="stylesheet" href="/shuffle-works-footer.css">'

  if grep -Fq 'data-shuffle-product-bar' "$page"; then
    inject_product_footer "$page"
    inject_page_controls_hoist "$page"
    inject_product_bar_height_sync "$page"
    inject_dashboard_chrome_toggle "$page"
    inject_favicon "$page"
    inject_social_meta "$page"
    return
  fi

  # Leave non-HTML source placeholders untouched rather than making publication
  # depend on a particular HTML formatter.
  if ! grep -Fq '</head>' "$page" || ! grep -Eq '<body([[:space:]>])' "$page"; then
    return
  fi

  bar="$(product_bar_markup "$surface")"
  temp_page="$(mktemp)"

  awk -v stylesheet="$stylesheet" '
    index($0, "</head>") { print stylesheet }
    { print }
  ' "$page" >"$temp_page"

  awk -v bar="$bar" '
    /<body([[:space:]>])/ { print; print bar; next }
    { print }
  ' "$temp_page" >"$page"
  rm -f "$temp_page"

  inject_product_footer "$page"
  inject_page_controls_hoist "$page"
  inject_product_bar_height_sync "$page"
  inject_dashboard_chrome_toggle "$page"
  inject_favicon "$page"
  inject_social_meta "$page"
}

# Vendored reference pages can ship pre-existing links to the reference's old
# standalone URL in their own content, independent of whether that page gets
# the product-bar/footer shell; keep this a plain per-page rewrite so it runs
# regardless of which branch below a page takes.
rewrite_legacy_reference_links() {
  local page=$1
  sed -i 's|href="/spark-tuning-reference/"|href="/sparkforensics/vendor/spark-doc/landing.html"|g' "$page"
}

# Only each product's own landing page carries the shared product bar and
# footer: sparkforensics/index.html (SparkForensics itself) and
# vendor/spark-doc/landing.html (Spark Tuning Reference's entry point). Every
# other page under the tree -- notably the embedded reference's own
# index.html/meta.html content pages -- is a sub-page of a product, not a
# product surface in its own right, so it only gets the family-wide,
# bar/footer-independent touches (favicon, Open Graph/Twitter tags).
inject_product_shells() {
  local root=$1 default_surface=$2 page relative

  while IFS= read -r -d '' page; do
    relative="${page#"$root"/}"
    rewrite_legacy_reference_links "$page"

    case "$relative" in
      index.html)
        inject_product_shell "$page" "$default_surface"
        ;;
      vendor/spark-doc/landing.html)
        inject_product_shell "$page" spark-tuning-reference
        ;;
      *)
        inject_favicon "$page"
        inject_social_meta "$page"
        ;;
    esac
  done < <(find "$root" -type f -name '*.html' -print0)
}

inject_before() {
  local page=$1 marker=$2 content=$3 temp_page
  temp_page="$(mktemp)"

  # Only the first matching line counts: some already-injected one-liners
  # (e.g. footer_override_style's <style>...</style>) contain the same
  # marker substring as plain text later in the page, and inserting before
  # every match would duplicate content outside its intended tag.
  #
  # `content` goes through the environment (ENVIRON), not -v: awk's -v
  # assignment runs the value through the same backslash-escape processing
  # as a string literal in the program text, so a -v'd `\"` silently
  # collapses to `"` and `\n` becomes a real newline — corrupting any
  # injected content that legitimately contains a backslash escape (e.g. a
  # JS string literal with an escaped quote). ENVIRON values are passed
  # through verbatim.
  content="$content" awk -v marker="$marker" '
    !found && index($0, marker) { print ENVIRON["content"]; found=1 }
    { print }
  ' "$page" >"$temp_page"
  mv "$temp_page" "$page"
}

reference_router_markup() {
  printf '%s' '<nav class="symptom-router" data-shuffle-symptom-router aria-labelledby="symptom-router-title"><h3 id="symptom-router-title">Start with a symptom</h3><p>Choose the closest starting point, then follow the linked diagnosis and tuning guidance.</p><ul class="symptom-router-list"><li><a href="bottleneck-slow-host.html">Slow stages</a></li><li><a href="bottleneck-skew.html">Skew, spill, or memory</a></li><li><a href="bottleneck-failures.html">Failures or retries</a></li><li><a href="spark-architecture.html">Configuration or architecture</a></li></ul></nav>'
}

reference_router_styles() {
  printf '%s' '.symptom-router { max-width: var(--content-max-width); margin: 0 auto var(--space-5); padding: var(--space-3); border: 1px solid var(--color-border); border-radius: 8px; background: var(--color-surface); } .symptom-router h3 { margin: 0 0 var(--space-2); font-size: 1rem; } .symptom-router p { margin: 0 0 var(--space-3); color: var(--color-text-muted); } .symptom-router-list { display: flex; flex-wrap: wrap; gap: var(--space-2); padding: 0; margin: 0; list-style: none; } .symptom-router-list a { display: inline-flex; align-items: center; min-height: 44px; padding: var(--space-2) var(--space-3); border: 1px solid var(--color-border); border-radius: 6px; color: var(--color-text); font-weight: 600; } .symptom-router-list a:hover { border-color: var(--color-accent); color: var(--color-accent-hover); }'
}

reference_drawer_script() {
  printf '%s' '<script data-shuffle-reference-a11y>document.addEventListener("DOMContentLoaded", () => { const toggle = document.getElementById("nav-toggle"); const sidebar = document.getElementById("sidebar"); if (!toggle || !sidebar) return; const mobileNavigation = window.matchMedia("(max-width: 900px)"); const closeDrawer = (restoreFocus = false) => { sidebar.classList.remove("sidebar-open"); sidebar.toggleAttribute("inert", mobileNavigation.matches); sidebar.setAttribute("aria-hidden", String(mobileNavigation.matches)); toggle.setAttribute("aria-expanded", "false"); if (restoreFocus) toggle.focus({ preventScroll: true }); }; const openDrawer = () => { sidebar.classList.add("sidebar-open"); sidebar.removeAttribute("inert"); sidebar.setAttribute("aria-hidden", "false"); toggle.setAttribute("aria-expanded", "true"); requestAnimationFrame(() => sidebar.querySelector("#nav-search, .nav-link")?.focus()); }; const syncDrawerForViewport = () => { if (mobileNavigation.matches) { closeDrawer(); } else { sidebar.classList.remove("sidebar-open"); sidebar.removeAttribute("inert"); sidebar.setAttribute("aria-hidden", "false"); toggle.setAttribute("aria-expanded", "false"); } }; syncDrawerForViewport(); mobileNavigation.addEventListener("change", syncDrawerForViewport); document.addEventListener("click", (event) => { if (!mobileNavigation.matches) return; if (event.target.closest("#nav-toggle")) { event.preventDefault(); event.stopPropagation(); if (sidebar.classList.contains("sidebar-open")) closeDrawer(); else openDrawer(); } else if (event.target.closest("#sidebar .nav-link")) { closeDrawer(true); event.stopPropagation(); } }, true); document.addEventListener("keydown", (event) => { if (event.key === "Escape" && mobileNavigation.matches && sidebar.classList.contains("sidebar-open")) closeDrawer(true); }); });</script>'
}

inject_reference_enhancements() {
  local page=$1

  # The router's links are relative filenames (bottleneck-skew.html, ...), so
  # this only makes sense injected into a page that's itself a sibling of
  # those chapter files (currently: chapters/spark/index.html and intro.html,
  # the only pages carrying the "Severity dots" heading this keys off of).
  if grep -Fq '<h2>Severity dots</h2>' "$page" && ! grep -Fq 'data-shuffle-symptom-router' "$page"; then
    inject_before "$page" '<h2>Severity dots</h2>' "$(reference_router_markup)"
  fi

  if grep -Fq 'id="nav-toggle"' "$page" && ! grep -Fq 'data-shuffle-reference-a11y' "$page"; then
    inject_before "$page" '</body>' "$(reference_drawer_script)"
  fi
}

# The router's markup gets injected per-page (above), but its styles live in
# the chapter tree's one shared stylesheet now instead of a per-page inline
# <style> block, so this only needs to run once against that shared file.
# Guarded on the rule's own selector rather than the page-level
# data-shuffle-symptom-router marker, since this operates on the stylesheet,
# not a page.
inject_symptom_router_styles() {
  local stylesheet=$1

  if grep -Fq '.symptom-router {' "$stylesheet"; then
    return
  fi

  printf '\n%s\n' "$(reference_router_styles)" >>"$stylesheet"
}

# The shared product-bar (injected above the doc reference pages at publish
# time) already names the current product as the active tab. This hides the
# sidebar's own repeated product-name text so there's no duplicate nav. It's
# scoped by DOM presence, so it's inert on a standalone open of the page
# (no .shuffle-product-bar exists there to match against).
sidebar_dedup_style() {
  printf '%s' '<style data-shuffle-sidebar-dedup>header.shuffle-product-bar ~ .layout .site-name{display:none}</style>'
}

inject_sidebar_dedup_style() {
  local page=$1

  if grep -Fq 'data-shuffle-sidebar-dedup' "$page"; then
    return
  fi

  if ! grep -Fq '</head>' "$page"; then
    return
  fi

  inject_before "$page" '</head>' "$(sidebar_dedup_style)"
}

# The vendored Spark Tuning Reference pages ship with their own theme-storage
# key, distinct from the one landing.html and the rest of the site use. That
# split means a visitor's theme choice on landing.html silently reverts when
# they land on index.html/meta.html. Realigning the key here keeps the choice
# shared across the whole vendored doc set. sed's global flag makes this
# naturally idempotent: once the literal is gone, rerunning is a no-op.
align_reference_theme_key() {
  local page=$1

  sed -i 's/spark-tuning-reference-theme/shuffle-works-theme/g' "$page"
}

# The vendored pages' own generic external-link-arrow rule also matches the
# GitHub link inside the injected product-bar header, which already carries
# its own literal arrow glyph -- doubling it on that one link. Scoping the
# rule to .content keeps it limited to the page's own prose, where the
# product bar (outside .content) can't match. The ^-anchor keeps this
# idempotent on rerun: once the selector already starts with ".content ",
# it no longer matches the unanchored pattern, so a rerun is a no-op instead
# of re-prefixing an already-scoped rule.
scope_reference_external_link_arrow() {
  local page=$1

  sed -i 's/^a\[href\^="http"\]::after {/.content a[href^="http"]::after {/' "$page"
}

FORENSICS_CHECKOUT="$CHECKOUT_DIR/SparkForensics"
clone_repo "shuffle-works/sparkforensics" "$FORENSICS_CHECKOUT" "$FORENSICS_REF"

if [ ! -f "$FORENSICS_CHECKOUT/dist/index.html" ]; then
  echo "error: SparkForensics at ref $FORENSICS_REF is missing dist/index.html" >&2
  exit 1
fi

if [ ! -f "$FORENSICS_CHECKOUT/dist/vendor/spark-doc/chapters/spark/index.html" ] || \
  [ ! -f "$FORENSICS_CHECKOUT/dist/vendor/spark-doc/chapters/meta/index.html" ] || \
  [ ! -f "$FORENSICS_CHECKOUT/dist/vendor/spark-doc/anchors.json" ] || \
  [ ! -f "$FORENSICS_CHECKOUT/dist/vendor/spark-doc/landing.html" ]; then
  echo "error: SparkForensics at ref $FORENSICS_REF is missing its embedded Spark reference" >&2
  exit 1
fi

if [ ! -f "$PRODUCT_BAR_STYLESHEET" ]; then
  echo "error: missing shared product-bar stylesheet: $PRODUCT_BAR_STYLESHEET" >&2
  exit 1
fi

if [ ! -f "$DESIGN_TOKENS_STYLESHEET" ]; then
  echo "error: missing shared design-tokens stylesheet: $DESIGN_TOKENS_STYLESHEET" >&2
  exit 1
fi

if [ ! -f "$FOOTER_STYLESHEET" ]; then
  echo "error: missing shared footer stylesheet: $FOOTER_STYLESHEET" >&2
  exit 1
fi

if [ ! -f "$FOOTER_PARTIAL" ]; then
  echo "error: missing shared footer partial: $FOOTER_PARTIAL" >&2
  exit 1
fi

stage_tree "$FORENSICS_CHECKOUT/dist" "$STAGED_DIR/sparkforensics"

landing_page="$STAGED_DIR/sparkforensics/vendor/spark-doc/landing.html"
if [ -f "$landing_page" ]; then
  mark_page_controls "$landing_page"
fi

inject_product_shells "$STAGED_DIR/sparkforensics" sparkforensics

while IFS= read -r -d '' reference_page; do
  inject_reference_enhancements "$reference_page"
  inject_sidebar_dedup_style "$reference_page"
  align_reference_theme_key "$reference_page"
done < <(find "$STAGED_DIR/sparkforensics/vendor/spark-doc/chapters" -type f -name '*.html' -print0)

# The per-chapter pages share these assets instead of each inlining its own
# copy (unlike the old monolithic index.html/meta.html), so the same
# theme-key/link-arrow rewrites apply once here rather than per page.
reference_client_script="$STAGED_DIR/sparkforensics/vendor/spark-doc/chapters/assets/chapters-client.mjs"
if [ -f "$reference_client_script" ]; then
  align_reference_theme_key "$reference_client_script"
fi

reference_docs_stylesheet="$STAGED_DIR/sparkforensics/vendor/spark-doc/chapters/assets/docs.css"
if [ -f "$reference_docs_stylesheet" ]; then
  scope_reference_external_link_arrow "$reference_docs_stylesheet"
  inject_symptom_router_styles "$reference_docs_stylesheet"
fi

mkdir -p "$PUBLISH_ROOT"
rm -rf "$PUBLISH_ROOT/sparkforensics" "$PUBLISH_ROOT/spark-tuning-reference"
mv "$STAGED_DIR/sparkforensics" "$PUBLISH_ROOT/sparkforensics"

# Keep the historical /spark-tuning-reference/ URL alive: it predates the
# embedded reference and is still linked externally, so publish a redirect
# stub to the current landing page instead of returning a 404.
mkdir -p "$PUBLISH_ROOT/spark-tuning-reference"
cat >"$PUBLISH_ROOT/spark-tuning-reference/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Spark Tuning Reference moved</title>
<link rel="canonical" href="$REFERENCE_LANDING_PATH">
<meta http-equiv="refresh" content="0; url=$REFERENCE_LANDING_PATH">
<script>location.replace("$REFERENCE_LANDING_PATH");</script>
</head>
<body>
<p>The Spark Tuning Reference has moved to <a href="$REFERENCE_LANDING_PATH">its new home</a>.</p>
</body>
</html>
EOF

if [ ! "$PRODUCT_BAR_STYLESHEET" -ef "$PUBLISH_ROOT/shuffle-works-product-bar.css" ]; then
  cp "$PRODUCT_BAR_STYLESHEET" "$PUBLISH_ROOT/shuffle-works-product-bar.css"
fi

if [ ! "$DESIGN_TOKENS_STYLESHEET" -ef "$PUBLISH_ROOT/shuffle-works-tokens.css" ]; then
  cp "$DESIGN_TOKENS_STYLESHEET" "$PUBLISH_ROOT/shuffle-works-tokens.css"
fi

if [ ! "$FOOTER_STYLESHEET" -ef "$PUBLISH_ROOT/shuffle-works-footer.css" ]; then
  cp "$FOOTER_STYLESHEET" "$PUBLISH_ROOT/shuffle-works-footer.css"
fi

# One sitemap for the whole published family, listing each surface's
# canonical URL (the /spark-tuning-reference/ redirect stub above is
# deliberately excluded: its own canonical link already points crawlers at
# the landing page instead). Derived from PRODUCT_BAR_HREFS and
# REFERENCE_LANDING_PATH rather than hand-typed, so a renamed/added product
# can't drift out of sync with the sitemap.
REFERENCE_DOC_DIR="$(dirname "$REFERENCE_LANDING_PATH")"
SITEMAP_PATHS=(
  "/"
  "${PRODUCT_BAR_HREFS[@]}"
  "$REFERENCE_DOC_DIR/chapters/index.html"
  "$REFERENCE_DOC_DIR/chapters/spark/index.html"
  "$REFERENCE_DOC_DIR/chapters/meta/index.html"
)

SITEMAP_LASTMOD="$(date -u +%Y-%m-%d)"
{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
  for sitemap_path in "${SITEMAP_PATHS[@]}"; do
    printf '<url><loc>https://shuffle-works.github.io%s</loc><lastmod>%s</lastmod></url>\n' \
      "$sitemap_path" "$SITEMAP_LASTMOD"
  done
  printf '</urlset>\n'
} >"$PUBLISH_ROOT/sitemap.xml"

printf 'Published SparkForensics (%s) with its embedded Spark reference\n' "$FORENSICS_REF"
