#!/usr/bin/env bash
set -euo pipefail

page=index.html

rg -F '<a href="/sparkforensics/">Open SparkForensics &rarr;</a>' "$page"
rg -F '<a href="/sparkforensics/docs/tuning-reference/">Open Spark Tuning Reference &rarr;</a>' "$page"
rg -F '<a href="https://github.com/shuffle-works/sparkforensics" target="_blank" rel="noopener">Source on GitHub' "$page"
rg -F '<a href="https://github.com/shuffle-works/spark-tuning-reference" target="_blank" rel="noopener">Source on GitHub' "$page"

if rg -F '<a href="/sparkforensics/" target=' "$page" || \
  rg -F '<a href="/sparkforensics/docs/tuning-reference/" target=' "$page"; then
  echo 'error: published-site links must remain normal internal anchors' >&2
  exit 1
fi

not_found_page=404.html

rg -F '<a class="org-link" href="/sparkforensics/docs/tuning-reference/">Spark Tuning Reference</a>' "$not_found_page"
