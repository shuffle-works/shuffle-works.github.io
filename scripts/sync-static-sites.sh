#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLISH_ROOT="${PUBLISH_ROOT:-$REPO_ROOT}"
PRODUCT_BAR_STYLESHEET="$REPO_ROOT/shuffle-works-product-bar.css"
DESIGN_TOKENS_STYLESHEET="$REPO_ROOT/shuffle-works-tokens.css"
FOOTER_STYLESHEET="$REPO_ROOT/shuffle-works-footer.css"
FOOTER_PARTIAL="$REPO_ROOT/partials/shuffle-works-footer.html"

# The Spark reference now ships inside SparkForensics' own docs site (a
# VitePress nav item, not a standalone vendored build); this is where its
# entry page is published.
REFERENCE_LANDING_PATH="/sparkforensics/docs/tuning-reference/"

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
PRODUCT_BAR_HREFS=("/sparkforensics/" "/sparkforensics/docs/tuning-reference/")

# Identical on every surface (docs/product-bar-contract.md), unlike the
# per-surface arrays above. Wrapped in its own flex group (CSS: margin-left:
# auto) so it, and whatever page control gets hoisted after it, sit
# right-aligned instead of trailing directly after the product tabs.
PRODUCT_BAR_HEADER_LINKS='<span class="shuffle-product-bar__end"><a class="header-link" href="/sparkforensics/docs/tuning-reference/intro.html">Reference</a><a class="header-link github" href="https://github.com/shuffle-works" target="_blank" rel="noopener">GitHub <span aria-hidden="true">↗</span></a></span>'

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

# Marks a page's own theme-toggle button (if any) so the hub's runtime hoist
# script can relocate it onto the shared product bar's row. Silent no-op on
# a page with no theme-toggle at all (e.g. a stock VitePress build, which
# ships its own toggle with no id="theme-toggle" to match).
#
# The "already marked" check matches the exact marked button
# (id="theme-toggle" data-shuffle-page-controls), not the bare
# data-shuffle-page-controls substring: that substring also appears inside
# data-shuffle-page-controls-hoist (the hoist script's own querySelector
# call), so a broad substring check would false-positive and silently skip
# marking the button on any page where the hoist script was injected first.
mark_page_controls_if_present() {
  local page=$1

  if grep -Fq 'id="theme-toggle"' "$page" && ! grep -Fq 'id="theme-toggle" data-shuffle-page-controls' "$page"; then
    sed -i 's|id="theme-toggle"|id="theme-toggle" data-shuffle-page-controls|' "$page"
  fi
}

# A page whose own build ships a bespoke <header> (e.g. a docs theme's nav)
# would otherwise render stacked underneath the hub's freshly-inserted
# product bar. The hub's runtime hoist script relocates that header's marked
# control (mark_page_controls_if_present, above) onto the shared bar and then
# best-effort removes the now-empty old header -- but that removal is
# client-side and timing-dependent. This CSS is the deterministic fallback:
# it hides any other <header> in the document, regardless of whether the JS
# relocation/removal ran, raced, or failed. Harmless on a page with no other
# <header> (the selector simply never matches).
#
# Uses :has() rather than a general sibling combinator (~) because the other
# header isn't always a direct sibling of the bar: a docs theme like
# VitePress nests its own <header class="VPNav"> several levels deep inside
# its own root wrapper div, which sibling combinators can't reach regardless
# of nesting depth. `body:has(> header.shuffle-product-bar)` still anchors
# the rule to pages where the bar was actually injected as body's first
# child, so it can't fire on a standalone open of an unrelated page.
inject_header_dedup_style() {
  inject_dedup_style "$1" 'data-shuffle-header-dedup' \
    'body:has(> header.shuffle-product-bar) header:not([data-shuffle-product-bar]){display:none}'
}

inject_product_shell() {
  local page=$1 surface=$2 bar temp_page
  # Tokens first so the shared palette/type are defined before any consumer.
  local stylesheet='<link rel="stylesheet" href="/shuffle-works-tokens.css"><link rel="stylesheet" href="/shuffle-works-product-bar.css"><link rel="stylesheet" href="/shuffle-works-footer.css">'

  if ! grep -Fq 'data-shuffle-product-bar' "$page"; then
    # Leave non-HTML source placeholders untouched rather than making
    # publication depend on a particular HTML formatter.
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
  fi

  mark_page_controls_if_present "$page"
  inject_product_footer "$page"
  inject_page_controls_hoist "$page"
  inject_product_bar_height_sync "$page"
  inject_dashboard_chrome_toggle "$page"
  inject_header_dedup_style "$page"
  inject_favicon "$page"
  inject_social_meta "$page"
}

# Any page can ship pre-existing links to the reference's old standalone
# URL in its own content, independent of whether that page gets the
# product-bar/footer shell; keep this a plain per-page rewrite so it runs
# regardless of which branch below a page takes.
rewrite_legacy_reference_links() {
  local page=$1
  sed -i 's|href="/spark-tuning-reference/"|href="/sparkforensics/docs/tuning-reference/"|g' "$page"
}

# Every page under the tree carries the shared product bar and footer,
# scoped to its owning product's surface: sparkforensics/index.html and
# everything under docs/ use the "sparkforensics" surface, except
# docs/tuning-reference/ (the Spark tuning reference, one VitePress nav item
# among docs/'s others, not a separately built product) which keeps its own
# "spark-tuning-reference" surface -- matched before the general docs/*
# pattern since case takes the first match.
# A page that already carries its own data-shuffle-product-bar marker (a
# docs-site build that embeds the marker itself, e.g. via its own theme)
# is left as-is by inject_product_shell's early-return branch instead of
# getting a second bar spliced in.
inject_product_shells() {
  local root=$1 default_surface=$2 page relative

  while IFS= read -r -d '' page; do
    relative="${page#"$root"/}"
    rewrite_legacy_reference_links "$page"

    case "$relative" in
      docs/tuning-reference/*)
        inject_product_shell "$page" spark-tuning-reference
        ;;
      index.html | docs/*)
        inject_product_shell "$page" "$default_surface"
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

# Shared by inject_header_dedup_style: guards on a marker attribute, requires
# a </head> to inject before, and injects a single <style> rule -- only the
# marker and CSS differ per caller.
inject_dedup_style() {
  local page=$1 marker=$2 css=$3

  if grep -Fq "$marker" "$page"; then
    return
  fi

  if ! grep -Fq '</head>' "$page"; then
    return
  fi

  inject_before "$page" '</head>' "<style $marker>$css</style>"
}

escape_ere() {
  printf '%s' "$1" | sed 's/[.[\*^$+?(){}|\\]/\\&/g'
}

# A vendored static build (e.g. SparkForensics' own VitePress docs) emits its
# internal absolute links -- CSS url()s, href/src attribute values -- rooted
# at whatever "base" path its own build tool assumed at build time, which
# doesn't generally match wherever this hub actually ends up publishing that
# subtree. Neither side of that mapping is hardcoded here: the mount path is
# derived from where `dir` sits under $STAGED_DIR (which mirrors
# $PUBLISH_ROOT 1:1), and the build's own base is derived by finding how one
# of the tree's own real asset files is actually referenced in its own HTML.
# That keeps this working across an upstream build-tool upgrade (a new base
# convention) or a reshuffle of this hub's own tree (a new mount path)
# without either ever being spelled out as a literal in this script.
#
# The replacement is anchored to only fire where old_base starts a
# reference (preceded by a quote, a "(", or start-of-line) rather than a
# blind string replace, so an unrelated link that merely contains the same
# substring further into its own path (e.g. a GitHub source link ending in
# .../main/docs/adr/README.md) is left alone.
rebase_absolute_paths() {
  local dir=$1 mount_prefix mount_slash sample_file sample_rel
  local old_base old_base_re html_file found f

  if [ ! -d "$dir" ]; then
    return
  fi

  mount_prefix="/${dir#"$STAGED_DIR"/}"
  mount_slash="$mount_prefix/"

  sample_file="$(find "$dir" -type f -path '*/assets/*' | head -n1)"
  if [ -z "$sample_file" ]; then
    return
  fi
  sample_rel="${sample_file#"$dir"/}"

  old_base=""
  while IFS= read -r -d '' html_file; do
    found="$(awk -v needle="$sample_rel" '
      {
        p = index($0, needle)
        if (p > 0) {
          prefix = substr($0, 1, p - 1)
          for (i = length(prefix); i >= 1; i--) {
            c = substr(prefix, i, 1)
            if (c == "\"") {
              print substr(prefix, i + 1)
              exit
            }
          }
        }
      }
    ' "$html_file")"
    if [ -n "$found" ]; then
      old_base="$found"
      break
    fi
  done < <(find "$dir" -type f -name '*.html' -print0)

  if [ -z "$old_base" ] || [ "$old_base" = "$mount_slash" ]; then
    return
  fi

  old_base_re="$(escape_ere "$old_base")"

  while IFS= read -r -d '' f; do
    sed -i -E "s#([^A-Za-z0-9]|^)${old_base_re}#\1${mount_slash}#g" "$f"
  done < <(find "$dir" -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.mjs' \) -print0)
}

FORENSICS_CHECKOUT="$CHECKOUT_DIR/SparkForensics"
clone_repo "shuffle-works/sparkforensics" "$FORENSICS_CHECKOUT" "$FORENSICS_REF"

if [ ! -f "$FORENSICS_CHECKOUT/dist/index.html" ]; then
  echo "error: SparkForensics at ref $FORENSICS_REF is missing dist/index.html" >&2
  exit 1
fi

if [ ! -f "$FORENSICS_CHECKOUT/dist/docs/tuning-reference/index.html" ] || \
  [ ! -f "$FORENSICS_CHECKOUT/dist/docs/tuning-reference/intro.html" ]; then
  echo "error: SparkForensics at ref $FORENSICS_REF is missing its docs-hosted Spark tuning reference" >&2
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

rebase_absolute_paths "$STAGED_DIR/sparkforensics/docs"

inject_product_shells "$STAGED_DIR/sparkforensics" sparkforensics

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
# the landing page instead), plus the reference's own entry point. Derived
# from PRODUCT_BAR_HREFS rather than hand-typed, so a renamed/added product
# can't drift out of sync with the sitemap.
SITEMAP_PATHS=(
  "/"
  "${PRODUCT_BAR_HREFS[@]}"
  "${REFERENCE_LANDING_PATH}intro.html"
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
