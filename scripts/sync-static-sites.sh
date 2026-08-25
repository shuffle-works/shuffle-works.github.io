#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLISH_ROOT="${PUBLISH_ROOT:-$REPO_ROOT}"
PRODUCT_BAR_STYLESHEET="$REPO_ROOT/shuffle-works-product-bar.css"
DESIGN_TOKENS_STYLESHEET="$REPO_ROOT/shuffle-works-tokens.css"

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

product_bar_markup() {
  local surface=$1

  case "$surface" in
    sparkforensics)
      printf '%s' '<header class="shuffle-product-bar" data-shuffle-product-bar><nav class="shuffle-product-bar__nav" aria-label="Shuffle Works products"><a class="shuffle-product-bar__brand" href="/">Shuffle Works</a><a class="shuffle-product-bar__product" href="/sparkforensics/" aria-current="page">SparkForensics</a><a class="shuffle-product-bar__product" href="/sparkforensics/vendor/spark-doc/landing.html">Spark Tuning Reference</a></nav></header>'
      ;;
    spark-tuning-reference)
      printf '%s' '<header class="shuffle-product-bar" data-shuffle-product-bar><nav class="shuffle-product-bar__nav" aria-label="Shuffle Works products"><a class="shuffle-product-bar__brand" href="/">Shuffle Works</a><a class="shuffle-product-bar__product" href="/sparkforensics/">SparkForensics</a><a class="shuffle-product-bar__product" href="/sparkforensics/vendor/spark-doc/landing.html" aria-current="page">Spark Tuning Reference</a></nav></header>'
      ;;
    *)
      echo "error: unknown product surface: $surface" >&2
      exit 1
      ;;
  esac
}

inject_product_shell() {
  local page=$1 surface=$2 bar temp_page
  # Tokens first so the shared palette/type are defined before any consumer.
  local stylesheet='<link rel="stylesheet" href="/shuffle-works-tokens.css"><link rel="stylesheet" href="/shuffle-works-product-bar.css">'

  if grep -Fq 'data-shuffle-product-bar' "$page"; then
    sed -i 's|href="/spark-tuning-reference/"|href="/sparkforensics/vendor/spark-doc/landing.html"|g' "$page"
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

stage_tree "$FORENSICS_CHECKOUT/dist" "$STAGED_DIR/sparkforensics"
inject_product_shells "$STAGED_DIR/sparkforensics" sparkforensics

for reference_page in \
  "$STAGED_DIR/sparkforensics/vendor/spark-doc/index.html" \
  "$STAGED_DIR/sparkforensics/vendor/spark-doc/meta.html"
do
  if [ -f "$reference_page" ]; then
    inject_reference_enhancements "$reference_page"
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

printf 'Published SparkForensics (%s) with its embedded Spark reference\n' "$FORENSICS_REF"
