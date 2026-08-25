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
      printf '%s\n' '<!doctype html><html><head></head><body><h1>Spark Tuning Reference</h1></body></html>' >"$target_dir/dist/vendor/spark-doc/landing.html"
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
