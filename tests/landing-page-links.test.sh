#!/usr/bin/env bash
set -euo pipefail

page=index.html

rg -F '<a href="/sparkforensics/">Open SparkForensics &rarr;</a>' "$page"
rg -F '<a href="/sparkforensics/vendor/spark-doc/landing.html">Open Spark Tuning Reference &rarr;</a>' "$page"
rg -F '<a href="https://github.com/shuffle-works/sparkforensics" target="_blank" rel="noopener">Source on GitHub' "$page"
rg -F '<a href="https://github.com/shuffle-works/spark-tuning-reference" target="_blank" rel="noopener">Source on GitHub' "$page"

if rg -F '<a href="/sparkforensics/" target=' "$page" || \
  rg -F '<a href="/sparkforensics/vendor/spark-doc/landing.html" target=' "$page"; then
  echo 'error: published-site links must remain normal internal anchors' >&2
  exit 1
fi
