#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOCK_BIN="$TEST_ROOT/mock-bin"
MOCK_LOG="$TEST_ROOT/gh.log"
MOCK_AUTH_STATE="$TEST_ROOT/auth.status.checked"
PUBLISHED_ROOT="$TEST_ROOT/published"
export MOCK_LOG MOCK_AUTH_STATE

mkdir -p "$MOCK_BIN" "$PUBLISHED_ROOT"
touch "$MOCK_LOG"

cat >"$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="$MOCK_LOG"
auth_state="$MOCK_AUTH_STATE"

if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
  printf '%s\n' "gh auth status" >>"$log_file"
  : >"$auth_state"
  exit 0
fi

if [ "${1:-}" = repo ] && [ "${2:-}" = clone ]; then
  if [ ! -f "$auth_state" ]; then
    printf 'expected gh auth status before clone\n' >&2
    exit 1
  fi

  printf '%s\n' "gh $*" >>"$log_file"
  target_dir="${4:-}"
  case "${3:-}" in
    shuffle-works/sparkforensics)
      mkdir -p "$target_dir/dist/vendor"
      # A minimal-but-real app shell (rather than a bare content string): it
      # needs an actual <head>/<body>/#root for inject_product_shell and the
      # skip-link injection layered on top of it to have anything to act on.
      printf '%s\n' '<!doctype html><html><head><title>SparkForensics</title></head><body><div id="root"></div></body></html>' >"$target_dir/dist/index.html"
      printf '%s\n' 'worker' >"$target_dir/dist/vendor/worker.js"

      # SparkForensics' own docs site (a VitePress build), mocked with the
      # same /docs/-rooted absolute paths upstream's build actually emits:
      # an href/src pair in the page, a CSS url(), and a GitHub source link
      # that merely contains the substring "docs/" further into its path
      # (must NOT be rewritten, unlike the two above). Also carries
      # VitePress's own pre-hydration theme script and a stray Inter font
      # preload + a preloaded, genuinely empty vp-icons.css, exercising
      # fix_docs_theme_flash and strip_dead_docs_font_assets.
      mkdir -p "$target_dir/dist/docs/assets"
      printf '%s\n' '<!doctype html><html><head><link rel="stylesheet" href="/docs/assets/style.css"><link rel="preload" href="/docs/assets/inter-roman-latin.HASH123.woff2" as="font" type="font/woff2" crossorigin=""><link rel="preload stylesheet" href="/docs/vp-icons.css" as="style"><script id="check-dark-mode">(()=>{const e=localStorage.getItem("vitepress-theme-appearance")||"auto",a=window.matchMedia("(prefers-color-scheme: dark)").matches;(!e||e==="auto"?a:e==="dark")&&document.documentElement.classList.add("dark")})();</script></head><body><script src="/docs/assets/app.js"></script><a href="https://github.com/shuffle-works/sparkforensics/blob/main/docs/adr/README.md">ADR</a></body></html>' >"$target_dir/dist/docs/index.html"
      printf '%s\n' '@font-face{src:url(/docs/assets/inter.woff2)}@font-face{font-family:Inter;font-style:normal;font-weight:400;font-display:swap;src:url(/docs/assets/inter-roman-latin.HASH123.woff2) format("woff2")}:root{--vp-font-family-base: "Inter", sans-serif}' >"$target_dir/dist/docs/assets/style.css"
      printf '%s\n' 'function withBase(e){return"/docs/"+e}' >"$target_dir/dist/docs/assets/app.js"
      printf '%s\n' 'font binary' >"$target_dir/dist/docs/assets/inter-roman-latin.HASH123.woff2"
      : >"$target_dir/dist/docs/vp-icons.css"

      # The Spark tuning reference now lives inside the same VitePress docs
      # site, one nav item among others (upstream #160: "serve the tuning
      # reference from the docs site"). No more standalone vendor/ build, no
      # theme-toggle button to hoist, no nav-toggle drawer: VitePress ships
      # its own <header> (dedup'd the same way contributor-guide/user-guide
      # already are) and its own accessible nav.
      tuning_dir="$target_dir/dist/docs/tuning-reference"
      mkdir -p "$tuning_dir"
      printf '%s\n' '<!doctype html><html><head><title>Spark Tuning Reference</title><meta name="description" content="Move from a symptom to the mechanic and lever that fixes it."></head><body><header class="VPNav"><nav><a href="/docs/tuning-reference/intro">Tuning Reference</a></nav></header><h1>Symptoms, mapped to the right lever</h1><a href="/spark-tuning-reference/">old reference link</a></body></html>' >"$tuning_dir/index.html"
      printf '%s\n' '<!doctype html><html><head><title>Introduction</title></head><body><header class="VPNav"><nav><a href="/docs/tuning-reference/intro">Tuning Reference</a></nav></header><h1>Introduction</h1></body></html>' >"$tuning_dir/intro.html"

      if [ "${MOCK_MISSING_EMBEDDED_REFERENCE:-0}" = 1 ]; then
        rm -f "$tuning_dir/intro.html"
      fi
      if [ "${MOCK_MISSING_EMBEDDED_LANDING:-0}" = 1 ]; then
        rm -f "$tuning_dir/index.html"
      fi
      exit 0
      ;;
  esac
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 1
EOF

chmod +x "$MOCK_BIN/gh"

run_sync() {
  if PUBLISH_ROOT="$1" PATH="$MOCK_BIN:$PATH" \
    "$REPO_ROOT/scripts/sync-static-sites.sh" "${@:2}"
  then
    return 0
  fi

  printf 'expected sync to succeed\n' >&2
  exit 1
}

assert_last_invocations() {
  expected_auth="$1"
  expected_forensics="$2"

  actual="$(tail -n 2 "$MOCK_LOG")"
  printf '%s\n' "$actual" | sed -n '1p' | grep -Fx "$expected_auth" >/dev/null
  printf '%s\n' "$actual" | sed -n '2p' | grep -Ex "$expected_forensics" >/dev/null
}

run_sync "$PUBLISHED_ROOT"
assert_last_invocations \
  "gh auth status" \
  "gh repo clone shuffle-works/sparkforensics .*/checkout/SparkForensics -- --depth 1 --branch main"

FORENSICS_APP="$PUBLISHED_ROOT/sparkforensics/index.html"
test -f "$FORENSICS_APP"
test -f "$PUBLISHED_ROOT/sparkforensics/vendor/worker.js"

# The app shell gets a "skip to content" link ahead of the injected product
# bar (the first tab stop in the document), jumping to the React mount
# point, which needs tabindex="-1" to actually be focusable when jumped to.
grep -F 'data-shuffle-product-bar' "$FORENSICS_APP" >/dev/null
grep -F '<a class="shuffle-skip-link" data-shuffle-skip-link href="#root">Skip to content</a>' "$FORENSICS_APP" >/dev/null
grep -F 'id="root" tabindex="-1"' "$FORENSICS_APP" >/dev/null

SKIP_LINE="$(grep -n 'data-shuffle-skip-link' "$FORENSICS_APP" | head -n1 | cut -d: -f1)"
BAR_LINE="$(grep -n 'data-shuffle-product-bar' "$FORENSICS_APP" | head -n1 | cut -d: -f1)"
if [ "$SKIP_LINE" -ge "$BAR_LINE" ]; then
  echo "expected the skip link to appear before the product bar" >&2
  exit 1
fi

# The app shell's header-dedup style must be scoped to VitePress's own
# VPNav, not "any other header in the document": SparkForensics' React app
# renders its own per-view <header> once a log is loaded (the dashboard
# toolbar with the file switcher and plan-graph button), and an unscoped
# selector hides that legitimate header along with any actual stale chrome.
grep -F 'body:has(> header.shuffle-product-bar) header.VPNav{display:none}' "$FORENSICS_APP" >/dev/null
if grep -F 'header:not([data-shuffle-product-bar])' "$FORENSICS_APP" >/dev/null; then
  echo "expected the header-dedup style to be scoped to VPNav, not every header" >&2
  exit 1
fi

# SparkForensics' own docs site is built assuming it deploys at /docs/, but
# the hub actually publishes it nested under /sparkforensics/docs/; sync
# must rewrite the vendored build's own absolute references so its assets
# and in-app links resolve where it's actually mounted.
DOCS_INDEX="$PUBLISHED_ROOT/sparkforensics/docs/index.html"
DOCS_STYLESHEET="$PUBLISHED_ROOT/sparkforensics/docs/assets/style.css"
DOCS_APP_SCRIPT="$PUBLISHED_ROOT/sparkforensics/docs/assets/app.js"

# VitePress docs pages already ship their own skip link (VPSkipLink); only
# the app shell's single page should get the hub-injected one.
if grep -F 'data-shuffle-skip-link' "$DOCS_INDEX" >/dev/null; then
  echo "expected no duplicate skip link on a VitePress docs page" >&2
  exit 1
fi

grep -F 'href="/sparkforensics/docs/assets/style.css"' "$DOCS_INDEX" >/dev/null
grep -F 'src="/sparkforensics/docs/assets/app.js"' "$DOCS_INDEX" >/dev/null
grep -F 'url(/sparkforensics/docs/assets/inter.woff2)' "$DOCS_STYLESHEET" >/dev/null
grep -F 'return"/sparkforensics/docs/"+e' "$DOCS_APP_SCRIPT" >/dev/null

# A GitHub source link that merely contains "docs/" further into its own
# path (not anchored at the start, unlike the vendored build's own asset
# references above) must be left untouched.
grep -F 'href="https://github.com/shuffle-works/sparkforensics/blob/main/docs/adr/README.md"' "$DOCS_INDEX" >/dev/null

# VitePress's own pre-hydration theme script reads the shared
# shuffle-works-theme key first (falling back to its original
# vitepress-theme-appearance/auto chain) and sets data-theme alongside its
# own .dark class, so a theme set elsewhere in the family doesn't flash
# wrong on a docs page's first paint.
grep -F 'localStorage.getItem("shuffle-works-theme")' "$DOCS_INDEX" >/dev/null
grep -F 'localStorage.getItem("vitepress-theme-appearance")' "$DOCS_INDEX" >/dev/null
grep -F 'document.documentElement.setAttribute("data-theme"' "$DOCS_INDEX" >/dev/null

# The Inter @font-face rule (never rendered with, since --vp-font-family-base
# is overridden to Recursive elsewhere) is stripped, its preload link is
# removed, and the underlying font file is deleted -- but an unrelated
# @font-face rule with no font-family of its own still gets its url()
# rebased like any other asset reference.
if grep -F 'font-family:Inter' "$DOCS_STYLESHEET" >/dev/null; then
  echo "expected the dead Inter @font-face rule to be stripped" >&2
  exit 1
fi
grep -F 'url(/sparkforensics/docs/assets/inter.woff2)' "$DOCS_STYLESHEET" >/dev/null
if grep -F 'inter-roman-latin' "$DOCS_INDEX" >/dev/null; then
  echo "expected the Inter font preload link to be removed" >&2
  exit 1
fi
test ! -e "$PUBLISHED_ROOT/sparkforensics/docs/assets/inter-roman-latin.HASH123.woff2"

# vp-icons.css is preloaded as a stylesheet on every docs page despite being
# genuinely empty; the preload link and the empty file are both dropped.
if grep -F 'vp-icons.css' "$DOCS_INDEX" >/dev/null; then
  echo "expected the empty vp-icons.css preload link to be removed" >&2
  exit 1
fi
test ! -e "$PUBLISHED_ROOT/sparkforensics/docs/vp-icons.css"

# The docs/index.html page (contributor-guide/user-guide's home, not the
# tuning reference) stays on the "sparkforensics" surface: its product bar
# marks the first tab current, not the second.
grep -F '<a class="shuffle-product-bar__product" href="/sparkforensics/" aria-current="page">SparkForensics</a>' "$DOCS_INDEX" >/dev/null

TUNING_DIR="$PUBLISHED_ROOT/sparkforensics/docs/tuning-reference"
LANDING="$TUNING_DIR/index.html"
INTRO="$TUNING_DIR/intro.html"

test -f "$LANDING"
test -f "$INTRO"

# docs/tuning-reference/* is nested under docs/, so it rides the same
# absolute-path rebase as the rest of the docs site (no special-casing
# needed): its own in-page link to another docs/ page resolves under
# /sparkforensics/docs/ too.
grep -F 'href="/sparkforensics/docs/tuning-reference/intro"' "$LANDING" >/dev/null
grep -F 'href="/sparkforensics/docs/tuning-reference/intro"' "$INTRO" >/dev/null

# Pages under docs/tuning-reference/ get the shared bar and footer on the
# "spark-tuning-reference" surface (its own product-bar tab), not the
# default "sparkforensics" surface the rest of docs/ uses.
for reference_page in "$LANDING" "$INTRO"; do
  grep -F 'data-shuffle-product-bar' "$reference_page" >/dev/null
  grep -F '<a class="shuffle-product-bar__product" href="/sparkforensics/docs/tuning-reference/" aria-current="page">Spark Tuning Reference</a>' "$reference_page" >/dev/null
  grep -F 'href="/shuffle-works-tokens.css"' "$reference_page" >/dev/null
  grep -F 'data-shuffle-footer' "$reference_page" >/dev/null
  grep -F 'data-shuffle-page-controls-hoist' "$reference_page" >/dev/null
  grep -F '<link rel="icon" href="/icon.svg" type="image/svg+xml">' "$reference_page" >/dev/null

  # VitePress ships its own <header>, unrelated to the hub's injected
  # product bar; it must be dedup'd exactly like contributor-guide's is,
  # not specially hoisted (no theme-toggle button exists to hoist anymore).
  # Scoped to VPNav specifically, not "any other header": SparkForensics'
  # own app shell gets this same style, and its dashboard legitimately
  # renders its own per-view <header> once a log is loaded (the toolbar
  # with the file switcher and plan-graph button) that must stay visible.
  grep -F 'data-shuffle-header-dedup' "$reference_page" >/dev/null
  grep -F 'body:has(> header.shuffle-product-bar) header.VPNav{display:none}' "$reference_page" >/dev/null
done

# The shared product bar opts out of VitePress's client-side router (its
# own `vp-raw` escape hatch) so a link like "SparkForensics" navigates to
# the actual app shell instead of being intercepted and resolved against
# this docs build's own base ("/sparkforensics/docs/").
grep -F '<header class="shuffle-product-bar vp-raw" data-shuffle-product-bar>' "$LANDING" >/dev/null

# The header's "Reference" quick-link jumps straight into the reference
# content (intro), distinct from the product-bar tab which points at the
# landing page.
grep -F '<a class="header-link" href="/sparkforensics/docs/tuning-reference/intro.html">Reference</a>' "$LANDING" >/dev/null

# A leftover link to the reference's old standalone URL gets rewritten to
# the new docs-hosted landing page.
grep -F 'href="/sparkforensics/docs/tuning-reference/"' "$LANDING" >/dev/null
if grep -F 'href="/spark-tuning-reference/"' "$LANDING" >/dev/null; then
  echo "expected the legacy reference link to be rewritten" >&2
  exit 1
fi

# Open Graph/Twitter tags are built from each page's own <title>/<meta
# name="description">. index.html's mock has both; intro.html's has only a
# title.
grep -F '<meta property="og:title" content="Spark Tuning Reference">' "$LANDING" >/dev/null
grep -F '<meta property="og:description" content="Move from a symptom to the mechanic and lever that fixes it.">' "$LANDING" >/dev/null
grep -F '<meta property="og:title" content="Introduction">' "$INTRO" >/dev/null
if grep -F 'og:description' "$INTRO" >/dev/null; then
  echo "expected no og:description without a source <meta name=\"description\">" >&2
  exit 1
fi

test -f "$PUBLISHED_ROOT/spark-tuning-reference/index.html"
grep -F 'url=/sparkforensics/docs/tuning-reference/' "$PUBLISHED_ROOT/spark-tuning-reference/index.html" >/dev/null
grep -F '<meta name="viewport" content="width=device-width, initial-scale=1.0">' "$PUBLISHED_ROOT/spark-tuning-reference/index.html" >/dev/null

test -f "$PUBLISHED_ROOT/shuffle-works-footer.css"

# One sitemap for the whole published family.
test -f "$PUBLISHED_ROOT/sitemap.xml"
grep -F '<loc>https://shuffle-works.github.io/sparkforensics/docs/tuning-reference/</loc>' "$PUBLISHED_ROOT/sitemap.xml" >/dev/null
grep -F '<loc>https://shuffle-works.github.io/sparkforensics/docs/tuning-reference/intro.html</loc>' "$PUBLISHED_ROOT/sitemap.xml" >/dev/null

run_sync "$TEST_ROOT/one-ref" SparkForensics
assert_last_invocations \
  "gh auth status" \
  "gh repo clone shuffle-works/sparkforensics .*/checkout/SparkForensics -- --depth 1 --branch SparkForensics"

mkdir -p "$TEST_ROOT/unchanged/sparkforensics"
printf '%s\n' 'old forensics' >"$TEST_ROOT/unchanged/sparkforensics/index.html"

if MOCK_MISSING_EMBEDDED_REFERENCE=1 PUBLISH_ROOT="$TEST_ROOT/unchanged" PATH="$MOCK_BIN:$PATH" \
  "$REPO_ROOT/scripts/sync-static-sites.sh"
then
  echo "expected missing embedded reference to fail" >&2
  exit 1
fi

test "$(cat "$TEST_ROOT/unchanged/sparkforensics/index.html")" = "old forensics"

if MOCK_MISSING_EMBEDDED_LANDING=1 PUBLISH_ROOT="$TEST_ROOT/unchanged" PATH="$MOCK_BIN:$PATH" \
  "$REPO_ROOT/scripts/sync-static-sites.sh"
then
  echo "expected missing embedded landing page to fail" >&2
  exit 1
fi

test "$(cat "$TEST_ROOT/unchanged/sparkforensics/index.html")" = "old forensics"
