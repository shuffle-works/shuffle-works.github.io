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
      doc_dir="$target_dir/dist/vendor/spark-tuning-reference"
      mkdir -p "$doc_dir/chapters/spark" "$doc_dir/chapters/meta" "$doc_dir/chapters/assets"
      printf '%s\n' 'spark forensics index' >"$target_dir/dist/index.html"
      printf '%s\n' 'worker' >"$target_dir/dist/vendor/worker.js"

      # SparkForensics' own docs site (a VitePress build), mocked with the
      # same /docs/-rooted absolute paths upstream's build actually emits:
      # an href/src pair in the page, a CSS url(), and a GitHub source link
      # that merely contains the substring "docs/" further into its path
      # (must NOT be rewritten, unlike the two above).
      mkdir -p "$target_dir/dist/docs/assets"
      printf '%s\n' '<!doctype html><html><head><link rel="stylesheet" href="/docs/assets/style.css"></head><body><script src="/docs/assets/app.js"></script><a href="https://github.com/shuffle-works/sparkforensics/blob/main/docs/adr/README.md">ADR</a></body></html>' >"$target_dir/dist/docs/index.html"
      printf '%s\n' '@font-face{src:url(/docs/assets/inter.woff2)}' >"$target_dir/dist/docs/assets/style.css"
      printf '%s\n' 'function withBase(e){return"/docs/"+e}' >"$target_dir/dist/docs/assets/app.js"

      # Per-chapter reference pages (upstream's chapters/ layout, replacing
      # the old monolithic vendor/spark-tuning-reference/index.html + meta.html). Each
      # page carries its own sidebar/nav-toggle and inline theme-boot
      # snippet, shares one stylesheet/client-script asset pair, and only
      # the spark TOC page (index.html) carries the "Severity dots" heading
      # the symptom router keys off.
      printf '%s\n' '<!doctype html><html><head><title>Spark Tuning Reference</title></head><body><header data-shuffle-product-bar><a href="/spark-tuning-reference/">Spark Tuning Reference</a></header><h2>Severity dots</h2><button type="button" id="nav-toggle">menu</button><button type="button" class="theme-toggle" id="theme-toggle" aria-label="Switch to light theme" aria-pressed="false">toggle</button><nav id="sidebar"></nav><script>localStorage.getItem("spark-tuning-reference-theme");</script></body></html>' >"$doc_dir/chapters/spark/index.html"
      printf '%s\n' '<!doctype html><html><head><title>How This Site Works</title><meta name="description" content="How the Spark Tuning Reference site is built and organized."></head><body><div class="layout"><span class="site-name">Spark Tuning Reference</span></div><button type="button" id="nav-toggle">menu</button><button type="button" class="theme-toggle" id="theme-toggle" aria-label="Switch to light theme" aria-pressed="false">toggle</button><nav id="sidebar"></nav><script>localStorage.getItem("spark-tuning-reference-theme");</script></body></html>' >"$doc_dir/chapters/meta/index.html"
      printf '%s\n' 'a[href^="http"]::after { content: "arrow"; }' >"$doc_dir/chapters/assets/docs.css"
      printf '%s\n' 'localStorage.setItem("spark-tuning-reference-theme", theme);' >"$doc_dir/chapters/assets/chapters-client.mjs"

      printf '%s\n' '{}' >"$doc_dir/anchors.json"
      printf '%s\n' '<!doctype html><html><head><style>footer{padding:2rem 0}</style></head><body><header class="site-header"><nav class="header-nav" aria-label="Primary navigation"><a class="header-link" href="index.html">Reference</a><a class="header-link github" href="https://github.com/shuffle-works/spark-tuning-reference" target="_blank" rel="noopener">GitHub</a><button id="theme-toggle" class="theme-toggle" type="button" aria-label="Switch to light theme" aria-pressed="false">toggle</button></nav></header><h1>Spark Tuning Reference</h1><footer><div class="footer-inner"><span>Evidence-first Spark operations.</span></div></footer></body></html>' >"$doc_dir/landing.html"
      if [ "${MOCK_MISSING_EMBEDDED_REFERENCE:-0}" = 1 ]; then
        rm -f "$doc_dir/chapters/spark/index.html"
      fi
      if [ "${MOCK_MISSING_EMBEDDED_LANDING:-0}" = 1 ]; then
        rm -f "$doc_dir/landing.html"
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

DOC_DIR="$PUBLISHED_ROOT/sparkforensics/vendor/spark-tuning-reference"
SPARK_INDEX="$DOC_DIR/chapters/spark/index.html"
META_INDEX="$DOC_DIR/chapters/meta/index.html"
DOCS_CSS="$DOC_DIR/chapters/assets/docs.css"
CLIENT_SCRIPT="$DOC_DIR/chapters/assets/chapters-client.mjs"
LANDING="$DOC_DIR/landing.html"

test -f "$PUBLISHED_ROOT/sparkforensics/index.html"
test -f "$PUBLISHED_ROOT/sparkforensics/vendor/worker.js"

# SparkForensics' own docs site is built assuming it deploys at /docs/, but
# the hub actually publishes it nested under /sparkforensics/docs/; sync
# must rewrite the vendored build's own absolute references so its assets
# and in-app links resolve where it's actually mounted.
DOCS_INDEX="$PUBLISHED_ROOT/sparkforensics/docs/index.html"
DOCS_STYLESHEET="$PUBLISHED_ROOT/sparkforensics/docs/assets/style.css"
DOCS_APP_SCRIPT="$PUBLISHED_ROOT/sparkforensics/docs/assets/app.js"

grep -F 'href="/sparkforensics/docs/assets/style.css"' "$DOCS_INDEX" >/dev/null
grep -F 'src="/sparkforensics/docs/assets/app.js"' "$DOCS_INDEX" >/dev/null
grep -F 'url(/sparkforensics/docs/assets/inter.woff2)' "$DOCS_STYLESHEET" >/dev/null
grep -F 'return"/sparkforensics/docs/"+e' "$DOCS_APP_SCRIPT" >/dev/null

# A GitHub source link that merely contains "docs/" further into its own
# path (not anchored at the start, unlike the vendored build's own asset
# references above) must be left untouched.
grep -F 'href="https://github.com/shuffle-works/sparkforensics/blob/main/docs/adr/README.md"' "$DOCS_INDEX" >/dev/null
test -f "$SPARK_INDEX"
test -f "$META_INDEX"
test -f "$DOCS_CSS"
test -f "$CLIENT_SCRIPT"
test -f "$DOC_DIR/anchors.json"
test -f "$LANDING"
test -f "$PUBLISHED_ROOT/spark-tuning-reference/index.html"
grep -F 'url=/sparkforensics/vendor/spark-tuning-reference/landing.html' "$PUBLISHED_ROOT/spark-tuning-reference/index.html" >/dev/null
grep -F 'href="/sparkforensics/vendor/spark-tuning-reference/landing.html"' "$SPARK_INDEX" >/dev/null
if grep -F 'href="/spark-tuning-reference/"' "$SPARK_INDEX" >/dev/null; then
  echo "expected embedded reference navigation to use its bundled path" >&2
  exit 1
fi

test -f "$PUBLISHED_ROOT/shuffle-works-footer.css"
grep -F 'href="/shuffle-works-footer.css"' "$LANDING" >/dev/null

# Every page under a product's tree now gets the shared bar and footer, not
# just its landing page: chapters/spark/index.html and
# chapters/meta/index.html (Spark Tuning Reference's per-chapter reading
# pages) get them exactly like landing.html does, on the same
# "spark-tuning-reference" surface.

# chapters/spark/index.html's mock already embeds its own
# data-shuffle-product-bar marker (simulating a docs build that renders the
# marker itself), so inject_product_shell's early-return branch applies: it
# gets the footer and the per-shell scripts layered on, but not a second bar
# spliced in and not the shared stylesheet links (a page that already
# renders the marker is assumed to already carry equivalent styling for it).
grep -F 'data-shuffle-footer' "$SPARK_INDEX" >/dev/null
grep -F 'data-shuffle-page-controls-hoist' "$SPARK_INDEX" >/dev/null

# Every vendored chapter page's own theme-toggle button gets marked for the
# hub's hoist script to relocate, regardless of attribute order: upstream's
# chapter-shell template orders its button attributes (type, class, id)
# differently from landing.html's (id, class).
grep -F '<button type="button" class="theme-toggle" id="theme-toggle" data-shuffle-page-controls' "$SPARK_INDEX" >/dev/null

# landing.html ships with its own bespoke footer; sync must replace it.
grep -F 'data-shuffle-footer' "$LANDING" >/dev/null
if grep -F 'Evidence-first Spark operations.' "$LANDING" >/dev/null; then
  echo "expected the bespoke footer to be replaced by the canonical one" >&2
  exit 1
fi

# landing.html marks its own theme-toggle button with data-shuffle-page-controls;
# sync must inject the runtime hoist script so it merges onto the product
# bar's row instead of rendering as a second stacked bar. The Reference/GitHub
# links are no longer hoisted: the hub's own product bar now supplies those,
# so only the toggle still needs to move.
grep -F 'data-shuffle-page-controls-hoist' "$LANDING" >/dev/null
grep -F '<button id="theme-toggle" data-shuffle-page-controls class="theme-toggle"' "$LANDING" >/dev/null

# landing.html's own <header class="site-header"> would otherwise render
# stacked underneath the hub's freshly-inserted product bar if the runtime
# hoist script's best-effort removal ever races or fails; the CSS dedup rule
# is the deterministic guarantee that doesn't depend on that script running.
grep -F 'data-shuffle-header-dedup' "$LANDING" >/dev/null
grep -F 'body:has(> header.shuffle-product-bar) header:not([data-shuffle-product-bar]){display:none}' "$LANDING" >/dev/null

# The hub's own product bar carries the Reference/GitHub links directly.
# chapters/meta/index.html's mock has no pre-existing bar marker, so it gets
# a freshly-injected bar too, on the same "spark-tuning-reference" surface
# as landing.html, complete with the shared stylesheets and footer.
grep -F '<a class="header-link" href="/sparkforensics/vendor/spark-tuning-reference/chapters/spark/index.html">Reference</a>' "$LANDING" >/dev/null
grep -F '<a class="header-link github" href="https://github.com/shuffle-works" target="_blank" rel="noopener">GitHub' "$LANDING" >/dev/null
grep -F 'data-shuffle-product-bar' "$META_INDEX" >/dev/null
grep -F '<a class="shuffle-product-bar__product" href="/sparkforensics/vendor/spark-tuning-reference/landing.html" aria-current="page">Spark Tuning Reference</a>' "$META_INDEX" >/dev/null
grep -F 'href="/shuffle-works-tokens.css"' "$META_INDEX" >/dev/null
grep -F 'data-shuffle-footer' "$META_INDEX" >/dev/null
grep -F 'data-shuffle-page-controls-hoist' "$META_INDEX" >/dev/null
grep -F '<button type="button" class="theme-toggle" id="theme-toggle" data-shuffle-page-controls' "$META_INDEX" >/dev/null

# landing.html's own <style> block still carries a bare `footer { padding }`
# tag-selector rule. Since the canonical footer element still matches that
# bare tag selector, its padding would otherwise stack on top of
# .footer-inner's own padding, doubling the footer's height. Sync must append
# an override that always wins, without requiring the source page to scope
# its own rule.
grep -F 'data-shuffle-footer-override' "$LANDING" >/dev/null
grep -F 'footer[data-shuffle-footer]{padding:0!important}' "$LANDING" >/dev/null

# Every chapter page gets the sidebar-dedup style appended. It's
# DOM-presence-scoped, so it's harmless on chapters/spark/index.html's mock
# (no .layout .site-name there) and effective on chapters/meta/index.html's.
grep -F 'data-shuffle-sidebar-dedup' "$SPARK_INDEX" >/dev/null
grep -F 'header.shuffle-product-bar ~ .layout .site-name{display:none}' "$META_INDEX" >/dev/null

# Every chapter page carrying id="nav-toggle" gets the sidebar a11y drawer
# script, regardless of which reference sub-tree (spark/ or meta/) it's in.
grep -F 'data-shuffle-reference-a11y' "$SPARK_INDEX" >/dev/null
grep -F 'data-shuffle-reference-a11y' "$META_INDEX" >/dev/null

# The symptom router is keyed off the "Severity dots" heading, present only
# on chapters/spark/index.html's mock. Its links are page-relative filenames
# (it's meant for pages living alongside the bottleneck-*.html chapter
# files), not in-page fragments.
grep -F 'data-shuffle-symptom-router' "$SPARK_INDEX" >/dev/null
grep -F 'href="bottleneck-slow-host.html"' "$SPARK_INDEX" >/dev/null
grep -F 'href="bottleneck-skew.html"' "$SPARK_INDEX" >/dev/null
grep -F 'href="bottleneck-failures.html"' "$SPARK_INDEX" >/dev/null
grep -F 'href="spark-architecture.html"' "$SPARK_INDEX" >/dev/null
if grep -F 'data-shuffle-symptom-router' "$META_INDEX" >/dev/null; then
  echo "expected chapters/meta/index.html (no Severity dots heading) to not get the symptom router" >&2
  exit 1
fi

# The router's styles live in the chapter tree's one shared stylesheet
# (docs.css), appended exactly once regardless of how many pages got the
# router markup.
test "$(grep -c '\.symptom-router {' "$DOCS_CSS")" = 1

# The vendored pages' own generic external-link-arrow rule now lives in the
# shared docs.css rather than inline per page; sync must still scope it to
# .content so it doesn't also match the product bar's own GitHub link.
grep -F '.content a[href^="http"]::after' "$DOCS_CSS" >/dev/null

# Both chapter pages and the shared chapters-client.mjs read/write the same
# theme localStorage key landing.html/the rest of the site use, realigned
# from the vendored default.
if grep -F 'spark-tuning-reference-theme' "$SPARK_INDEX" "$META_INDEX" "$CLIENT_SCRIPT" >/dev/null; then
  echo "expected the vendored theme-storage key to be realigned everywhere" >&2
  exit 1
fi
grep -F 'shuffle-works-theme' "$SPARK_INDEX" >/dev/null
grep -F 'shuffle-works-theme' "$META_INDEX" >/dev/null
grep -F 'shuffle-works-theme' "$CLIENT_SCRIPT" >/dev/null

# Every processed page gets the shared favicon, regardless of which
# inject_product_shell branch it took: chapters/spark/index.html and
# chapters/meta/index.html already ship their own product bar-less content
# (the early-return, link-rewrite-only branch); landing.html gets a
# freshly-injected one.
for reference_page in "$SPARK_INDEX" "$META_INDEX" "$LANDING"; do
  grep -F '<link rel="icon" href="/icon.svg" type="image/svg+xml">' "$reference_page" >/dev/null
done

# Open Graph/Twitter tags are built from each page's own <title>/<meta
# name="description">. chapters/spark/index.html's mock has a title but no
# description, so it gets og:title but no og:description;
# chapters/meta/index.html's mock has both.
grep -F '<meta property="og:site_name" content="Shuffle Works">' "$SPARK_INDEX" >/dev/null
grep -F '<meta property="og:title" content="Spark Tuning Reference">' "$SPARK_INDEX" >/dev/null
if grep -F 'og:description' "$SPARK_INDEX" >/dev/null; then
  echo "expected no og:description without a source <meta name=\"description\">" >&2
  exit 1
fi
grep -F '<meta property="og:title" content="How This Site Works">' "$META_INDEX" >/dev/null
grep -F '<meta property="og:description" content="How the Spark Tuning Reference site is built and organized.">' "$META_INDEX" >/dev/null
grep -F '<meta name="twitter:description" content="How the Spark Tuning Reference site is built and organized.">' "$META_INDEX" >/dev/null

# One sitemap for the whole published family.
test -f "$PUBLISHED_ROOT/sitemap.xml"
grep -F '<loc>https://shuffle-works.github.io/sparkforensics/vendor/spark-tuning-reference/landing.html</loc>' "$PUBLISHED_ROOT/sitemap.xml" >/dev/null
grep -F '<loc>https://shuffle-works.github.io/sparkforensics/vendor/spark-tuning-reference/chapters/index.html</loc>' "$PUBLISHED_ROOT/sitemap.xml" >/dev/null
grep -F '<loc>https://shuffle-works.github.io/sparkforensics/vendor/spark-tuning-reference/chapters/spark/index.html</loc>' "$PUBLISHED_ROOT/sitemap.xml" >/dev/null
grep -F '<loc>https://shuffle-works.github.io/sparkforensics/vendor/spark-tuning-reference/chapters/meta/index.html</loc>' "$PUBLISHED_ROOT/sitemap.xml" >/dev/null

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
