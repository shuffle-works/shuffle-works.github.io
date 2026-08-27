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
      mkdir -p "$target_dir/dist/vendor/spark-doc"
      printf '%s\n' 'spark forensics index' >"$target_dir/dist/index.html"
      printf '%s\n' 'worker' >"$target_dir/dist/vendor/worker.js"
      printf '%s\n' '<!doctype html><html><head></head><body><header data-shuffle-product-bar><a href="/spark-tuning-reference/">Spark Tuning Reference</a></header></body></html>' >"$target_dir/dist/vendor/spark-doc/index.html"
      printf '%s\n' 'embedded tuning metadata' >"$target_dir/dist/vendor/spark-doc/meta.html"
      printf '%s\n' '{}' >"$target_dir/dist/vendor/spark-doc/anchors.json"
      printf '%s\n' '<!doctype html><html><head><style>footer{padding:2rem 0}</style></head><body><header class="site-header"><nav class="header-nav" aria-label="Primary navigation"><a href="index.html">Reference</a></nav></header><h1>Spark Tuning Reference</h1><footer><div class="footer-inner"><span>Evidence-first Spark operations.</span></div></footer></body></html>' >"$target_dir/dist/vendor/spark-doc/landing.html"
      if [ "${MOCK_MISSING_EMBEDDED_REFERENCE:-0}" = 1 ]; then
        rm -f "$target_dir/dist/vendor/spark-doc/index.html"
      fi
      if [ "${MOCK_MISSING_EMBEDDED_LANDING:-0}" = 1 ]; then
        rm -f "$target_dir/dist/vendor/spark-doc/landing.html"
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
test -f "$PUBLISHED_ROOT/sparkforensics/index.html"
test -f "$PUBLISHED_ROOT/sparkforensics/vendor/worker.js"
test -f "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/index.html"
test -f "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/meta.html"
test -f "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/anchors.json"
test -f "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/landing.html"
test -f "$PUBLISHED_ROOT/spark-tuning-reference/index.html"
grep -F 'url=/sparkforensics/vendor/spark-doc/landing.html' "$PUBLISHED_ROOT/spark-tuning-reference/index.html" >/dev/null
grep -F 'href="/sparkforensics/vendor/spark-doc/landing.html"' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/index.html" >/dev/null
if grep -F 'href="/spark-tuning-reference/"' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/index.html" >/dev/null; then
  echo "expected embedded reference navigation to use its bundled path" >&2
  exit 1
fi

test -f "$PUBLISHED_ROOT/shuffle-works-footer.css"
grep -F 'href="/shuffle-works-footer.css"' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/landing.html" >/dev/null

# index.html already carries data-shuffle-product-bar from a prior publish
# (the link-rewrite-only branch); it must still get the canonical footer.
grep -F 'data-shuffle-footer' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/index.html" >/dev/null

# landing.html ships with its own bespoke footer; sync must replace it.
grep -F 'data-shuffle-footer' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/landing.html" >/dev/null
if grep -F 'Evidence-first Spark operations.' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/landing.html" >/dev/null; then
  echo "expected the bespoke footer to be replaced by the canonical one" >&2
  exit 1
fi

# landing.html marks its own header nav with data-shuffle-page-controls;
# sync must inject the runtime hoist script so it merges onto the product
# bar's row instead of rendering as a second stacked bar.
grep -F 'data-shuffle-page-controls-hoist' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/landing.html" >/dev/null
grep -F '<nav class="header-nav" aria-label="Primary navigation" data-shuffle-page-controls>' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/landing.html" >/dev/null

# The hoist script is injected on every page unconditionally, not gated on
# finding the marker in the page's own static HTML: a client-rendered page
# (e.g. SparkForensics' React shell) never has data-shuffle-page-controls in
# its source at all, only ever produced by its JS bundle after mount. This
# mock page carries no such marker either, yet must still get the script.
grep -F 'data-shuffle-page-controls-hoist' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/index.html" >/dev/null

# landing.html's own <style> block still carries a bare `footer { padding }`
# tag-selector rule. Since the canonical footer element still matches that
# bare tag selector, its padding would otherwise stack on top of
# .footer-inner's own padding, doubling the footer's height. Sync must append
# an override that always wins, without requiring the source page to scope
# its own rule.
grep -F 'data-shuffle-footer-override' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/landing.html" >/dev/null
grep -F 'footer[data-shuffle-footer]{padding:0!important}' "$PUBLISHED_ROOT/sparkforensics/vendor/spark-doc/landing.html" >/dev/null

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
