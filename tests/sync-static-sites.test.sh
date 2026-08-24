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
      printf '%s\n' 'spark forensics index' >"$target_dir/dist/index.html"
      printf '%s\n' 'worker' >"$target_dir/dist/vendor/worker.js"
      exit 0
      ;;
    shuffle-works/spark-tuning-reference)
      mkdir -p "$target_dir"
      printf '%s\n' 'tuning index' >"$target_dir/index.html"
      printf '%s\n' 'tuning metadata' >"$target_dir/meta.html"
      if [ "${MOCK_MISSING_TUNING_INDEX:-0}" = 1 ]; then
        rm -f "$target_dir/index.html"
      fi
      if [ "${MOCK_MISSING_TUNING_META:-0}" = 1 ]; then
        rm -f "$target_dir/meta.html"
      fi
      printf '%s\n' '{}' >"$target_dir/anchors.json"
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
  expected_tuning="$3"

  actual="$(tail -n 3 "$MOCK_LOG")"
  printf '%s\n' "$actual" | sed -n '1p' | grep -Fx "$expected_auth" >/dev/null
  printf '%s\n' "$actual" | sed -n '2p' | grep -Ex "$expected_forensics" >/dev/null
  printf '%s\n' "$actual" | sed -n '3p' | grep -Ex "$expected_tuning" >/dev/null
}

run_sync "$PUBLISHED_ROOT"
assert_last_invocations \
  "gh auth status" \
  "gh repo clone shuffle-works/sparkforensics .*/checkout/SparkForensics -- --depth 1 --branch main" \
  "gh repo clone shuffle-works/spark-tuning-reference .*/checkout/spark-tuning-reference -- --depth 1 --branch master"
test -f "$PUBLISHED_ROOT/sparkforensics/index.html"
test -f "$PUBLISHED_ROOT/sparkforensics/vendor/worker.js"
test -f "$PUBLISHED_ROOT/spark-tuning-reference/index.html"
test -f "$PUBLISHED_ROOT/spark-tuning-reference/meta.html"
test -f "$PUBLISHED_ROOT/spark-tuning-reference/anchors.json"

run_sync "$TEST_ROOT/one-ref" SparkForensics
assert_last_invocations \
  "gh auth status" \
  "gh repo clone shuffle-works/sparkforensics .*/checkout/SparkForensics -- --depth 1 --branch SparkForensics" \
  "gh repo clone shuffle-works/spark-tuning-reference .*/checkout/spark-tuning-reference -- --depth 1 --branch master"

FORensics_REF="sparkforensics-ref"
TUNING_REF="tuning-ref"
run_sync "$TEST_ROOT/two-refs" "$FORensics_REF" "$TUNING_REF"
assert_last_invocations \
  "gh auth status" \
  "gh repo clone shuffle-works/sparkforensics .*/checkout/SparkForensics -- --depth 1 --branch $FORensics_REF" \
  "gh repo clone shuffle-works/spark-tuning-reference .*/checkout/spark-tuning-reference -- --depth 1 --branch $TUNING_REF"

mkdir -p "$TEST_ROOT/unchanged/sparkforensics" "$TEST_ROOT/unchanged/spark-tuning-reference"
printf '%s\n' 'old forensics' >"$TEST_ROOT/unchanged/sparkforensics/index.html"
printf '%s\n' 'old tuning' >"$TEST_ROOT/unchanged/spark-tuning-reference/index.html"

if MOCK_MISSING_TUNING_INDEX=1 PUBLISH_ROOT="$TEST_ROOT/unchanged" PATH="$MOCK_BIN:$PATH" \
  "$REPO_ROOT/scripts/sync-static-sites.sh"
then
  echo "expected missing source artifact to fail" >&2
  exit 1
fi

test "$(cat "$TEST_ROOT/unchanged/sparkforensics/index.html")" = "old forensics"
test "$(cat "$TEST_ROOT/unchanged/spark-tuning-reference/index.html")" = "old tuning"

printf '%s\n' 'old tuning metadata' >"$TEST_ROOT/unchanged/spark-tuning-reference/meta.html"
if MOCK_MISSING_TUNING_META=1 PUBLISH_ROOT="$TEST_ROOT/unchanged" PATH="$MOCK_BIN:$PATH" \
  "$REPO_ROOT/scripts/sync-static-sites.sh"
then
  echo "expected missing tuning metadata to fail" >&2
  exit 1
fi

test "$(cat "$TEST_ROOT/unchanged/spark-tuning-reference/meta.html")" = "old tuning metadata"
