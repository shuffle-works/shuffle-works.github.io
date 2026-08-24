#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLISH_ROOT="${PUBLISH_ROOT:-$REPO_ROOT}"

if [ "$#" -gt 2 ]; then
  echo "error: expected at most two refs" >&2
  exit 64
fi

FORENSICS_REF="${1:-main}"
TUNING_REF="${2:-master}"

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

FORENSICS_CHECKOUT="$CHECKOUT_DIR/SparkForensics"
TUNING_CHECKOUT="$CHECKOUT_DIR/spark-tuning-reference"
clone_repo "shuffle-works/sparkforensics" "$FORENSICS_CHECKOUT" "$FORENSICS_REF"
clone_repo "shuffle-works/spark-tuning-reference" "$TUNING_CHECKOUT" "$TUNING_REF"

if [ ! -f "$FORENSICS_CHECKOUT/dist/index.html" ]; then
  echo "error: SparkForensics at ref $FORENSICS_REF is missing dist/index.html" >&2
  exit 1
fi

if [ ! -f "$TUNING_CHECKOUT/index.html" ] || [ ! -f "$TUNING_CHECKOUT/meta.html" ] || [ ! -f "$TUNING_CHECKOUT/anchors.json" ]; then
  echo "error: spark-tuning-reference at ref $TUNING_REF is missing required artifacts" >&2
  exit 1
fi

stage_tree "$FORENSICS_CHECKOUT/dist" "$STAGED_DIR/sparkforensics"
mkdir -p "$STAGED_DIR/spark-tuning-reference"
cp "$TUNING_CHECKOUT/index.html" "$TUNING_CHECKOUT/meta.html" "$TUNING_CHECKOUT/anchors.json" \
  "$STAGED_DIR/spark-tuning-reference/"

mkdir -p "$PUBLISH_ROOT"
rm -rf "$PUBLISH_ROOT/sparkforensics" "$PUBLISH_ROOT/spark-tuning-reference"
mv "$STAGED_DIR/sparkforensics" "$PUBLISH_ROOT/sparkforensics"
mv "$STAGED_DIR/spark-tuning-reference" "$PUBLISH_ROOT/spark-tuning-reference"

printf 'Published SparkForensics (%s) and spark-tuning-reference (%s)\n' \
  "$FORENSICS_REF" "$TUNING_REF"
