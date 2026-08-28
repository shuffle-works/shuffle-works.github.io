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

  printf '%s' "<header class=\"shuffle-product-bar\" data-shuffle-product-bar><nav class=\"shuffle-product-bar__nav\" aria-label=\"Shuffle Works products\"><a class=\"shuffle-product-bar__brand\" href=\"/\">Shuffle Works</a>${links}</nav></header>"
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
page_controls_hoist_script() {
  printf '%s' '<script data-shuffle-page-controls-hoist>(() => { const tryHoist = () => { const bar = document.querySelector("[data-shuffle-product-bar] .shuffle-product-bar__nav"); const controls = document.querySelector("[data-shuffle-page-controls]"); if (!bar || !controls) return false; const oldHeader = controls.closest("header"); bar.after(controls); if (oldHeader && oldHeader !== document.querySelector("[data-shuffle-product-bar]")) { oldHeader.remove(); } return true; }; if (tryHoist()) return; const observer = new MutationObserver(() => { if (tryHoist()) observer.disconnect(); }); observer.observe(document.body, { childList: true, subtree: true }); })();</script>'
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

# spark-tuning-reference's landing.html ships its own <nav class="header-nav">
# as its only header controls. inject_page_controls_hoist already knows how
# to relocate anything marked data-shuffle-page-controls onto the shared
# product bar at runtime. This keys the marker's injection off that nav's
# own known, stable selector and applies it to the copied build output only,
# so the vendored source never needs the attribute pre-authored into it.
# No grep guard here: the hoist script injected elsewhere on the page also
# contains the literal substring "data-shuffle-page-controls" (in its
# querySelector call), so a broad guard would false-positive on a page that
# already carries the hoist script and silently skip marking the nav. The
# sed pattern below only matches the unmarked nav (no trailing attribute),
# so it's naturally idempotent on rerun without needing a guard.
mark_page_controls() {
  local page=$1

  sed -i 's|<nav class="header-nav" aria-label="Primary navigation">|<nav class="header-nav" aria-label="Primary navigation" data-shuffle-page-controls>|' "$page"

  if ! grep -Fq 'data-shuffle-page-controls' "$page"; then
    echo "error: could not mark page controls in $page (nav selector drifted upstream?)" >&2
    exit 1
  fi
}

inject_product_shell() {
  local page=$1 surface=$2 bar temp_page
  # Tokens first so the shared palette/type are defined before any consumer.
  local stylesheet='<link rel="stylesheet" href="/shuffle-works-tokens.css"><link rel="stylesheet" href="/shuffle-works-product-bar.css"><link rel="stylesheet" href="/shuffle-works-footer.css">'

  if grep -Fq 'data-shuffle-product-bar' "$page"; then
    sed -i 's|href="/spark-tuning-reference/"|href="/sparkforensics/vendor/spark-doc/landing.html"|g' "$page"
    inject_product_footer "$page"
    inject_page_controls_hoist "$page"
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
}

inject_product_shells() {
  local root=$1 default_surface=$2 page surface

  while IFS= read -r -d '' page; do
    surface=$default_surface
    case "$page" in
      "$root"/vendor/spark-doc/*)
        surface=spark-tuning-reference
        ;;
    esac
    inject_product_shell "$page" "$surface"
  done < <(find "$root" -type f -name '*.html' -print0)
}

inject_before() {
  local page=$1 marker=$2 content=$3 temp_page
  temp_page="$(mktemp)"

  awk -v marker="$marker" -v content="$content" '
    index($0, marker) { print content }
    { print }
  ' "$page" >"$temp_page"
  mv "$temp_page" "$page"
}

reference_router_markup() {
  printf '%s' '<nav class="symptom-router" data-shuffle-symptom-router aria-labelledby="symptom-router-title"><h3 id="symptom-router-title">Start with a symptom</h3><p>Choose the closest starting point, then follow the linked diagnosis and tuning guidance.</p><ul class="symptom-router-list"><li><a href="#bottleneck-slow-host">Slow stages</a></li><li><a href="#bottleneck-skew">Skew, spill, or memory</a></li><li><a href="#bottleneck-failures">Failures or retries</a></li><li><a href="#spark-architecture">Configuration or architecture</a></li></ul></nav>'
}

reference_router_styles() {
  printf '%s' '.symptom-router { max-width: var(--content-max-width); margin: 0 auto var(--space-5); padding: var(--space-3); border: 1px solid var(--color-border); border-radius: 8px; background: var(--color-surface); } .symptom-router h3 { margin: 0 0 var(--space-2); font-size: 1rem; } .symptom-router p { margin: 0 0 var(--space-3); color: var(--color-text-muted); } .symptom-router-list { display: flex; flex-wrap: wrap; gap: var(--space-2); padding: 0; margin: 0; list-style: none; } .symptom-router-list a { display: inline-flex; align-items: center; min-height: 44px; padding: var(--space-2) var(--space-3); border: 1px solid var(--color-border); border-radius: 6px; color: var(--color-text); font-weight: 600; } .symptom-router-list a:hover { border-color: var(--color-accent); color: var(--color-accent-hover); }'
}

reference_drawer_script() {
  printf '%s' '<script data-shuffle-reference-a11y>document.addEventListener("DOMContentLoaded", () => { const toggle = document.getElementById("nav-toggle"); const sidebar = document.getElementById("sidebar"); if (!toggle || !sidebar) return; const mobileNavigation = window.matchMedia("(max-width: 900px)"); const closeDrawer = (restoreFocus = false) => { sidebar.classList.remove("sidebar-open"); sidebar.toggleAttribute("inert", mobileNavigation.matches); sidebar.setAttribute("aria-hidden", String(mobileNavigation.matches)); toggle.setAttribute("aria-expanded", "false"); if (restoreFocus) toggle.focus({ preventScroll: true }); }; const openDrawer = () => { sidebar.classList.add("sidebar-open"); sidebar.removeAttribute("inert"); sidebar.setAttribute("aria-hidden", "false"); toggle.setAttribute("aria-expanded", "true"); requestAnimationFrame(() => sidebar.querySelector("#nav-search, .nav-link")?.focus()); }; const syncDrawerForViewport = () => { if (mobileNavigation.matches) { closeDrawer(); } else { sidebar.classList.remove("sidebar-open"); sidebar.removeAttribute("inert"); sidebar.setAttribute("aria-hidden", "false"); toggle.setAttribute("aria-expanded", "false"); } }; syncDrawerForViewport(); mobileNavigation.addEventListener("change", syncDrawerForViewport); document.addEventListener("click", (event) => { if (!mobileNavigation.matches) return; if (event.target.closest("#nav-toggle")) { event.preventDefault(); event.stopPropagation(); if (sidebar.classList.contains("sidebar-open")) closeDrawer(); else openDrawer(); } else if (event.target.closest("#sidebar .nav-link")) { closeDrawer(true); event.stopPropagation(); } }, true); document.addEventListener("keydown", (event) => { if (event.key === "Escape" && mobileNavigation.matches && sidebar.classList.contains("sidebar-open")) closeDrawer(true); }); });</script>'
}

inject_reference_enhancements() {
  local page=$1

  if grep -Fq '<h3>Severity dots</h3>' "$page" && ! grep -Fq 'data-shuffle-symptom-router' "$page"; then
    inject_before "$page" '</style>' "$(reference_router_styles)"
    inject_before "$page" '<h3>Severity dots</h3>' "$(reference_router_markup)"
  fi

  if grep -Fq 'id="nav-toggle"' "$page" && ! grep -Fq 'data-shuffle-reference-a11y' "$page"; then
    inject_before "$page" '</body>' "$(reference_drawer_script)"
  fi
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

FORENSICS_CHECKOUT="$CHECKOUT_DIR/SparkForensics"
clone_repo "shuffle-works/sparkforensics" "$FORENSICS_CHECKOUT" "$FORENSICS_REF"

if [ ! -f "$FORENSICS_CHECKOUT/dist/index.html" ]; then
  echo "error: SparkForensics at ref $FORENSICS_REF is missing dist/index.html" >&2
  exit 1
fi

if [ ! -f "$FORENSICS_CHECKOUT/dist/vendor/spark-doc/index.html" ] || \
  [ ! -f "$FORENSICS_CHECKOUT/dist/vendor/spark-doc/meta.html" ] || \
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

for reference_page in \
  "$STAGED_DIR/sparkforensics/vendor/spark-doc/index.html" \
  "$STAGED_DIR/sparkforensics/vendor/spark-doc/meta.html"
do
  if [ -f "$reference_page" ]; then
    inject_reference_enhancements "$reference_page"
    inject_sidebar_dedup_style "$reference_page"
  fi
done

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

printf 'Published SparkForensics (%s) with its embedded Spark reference\n' "$FORENSICS_REF"
