#!/usr/bin/env bash
# render-report-html.sh <evidence_dir> <outfile>
#
# Renders a standalone HTML report from a single run's evidence directory
# (same results.tsv that SUMMARY.md is built from), for publishing to
# GitHub Pages. Styled with IBM's Carbon Design System (carbon-components,
# loaded from a CDN — this is a real published page, not a sandboxed
# Claude artifact, so an external stylesheet is fine here).
# Not sourced by area scripts — invoked directly from CI or by hand.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=../lib/result.sh
source "${REPO_ROOT}/lib/result.sh"

EVIDENCE_DIR="${1:?usage: render-report-html.sh <evidence_dir> <outfile>}"
OUT_FILE="${2:?usage: render-report-html.sh <evidence_dir> <outfile>}"
RESULTS_TSV="${EVIDENCE_DIR}/results.tsv"
RUN_ID="$(basename "$EVIDENCE_DIR")"

if [ ! -f "$RESULTS_TSV" ]; then
  echo "No results.tsv found in ${EVIDENCE_DIR}" >&2
  exit 1
fi

# status_tag_color <status> — maps our PASS/OBSERVATION/FAIL/BLOCKED/FOLLOWUP
# statuses onto Carbon's fixed Tag color palette (no direct "yellow"/"amber"
# in Carbon v10 tags, so OBSERVATION gets teal rather than the legend's 🟡).
status_tag_color() {
  case "$1" in
    PASS) echo "green" ;;
    OBSERVATION) echo "teal" ;;
    FAIL) echo "red" ;;
    BLOCKED) echo "gray" ;;
    FOLLOWUP) echo "purple" ;;
    *) echo "cool-gray" ;;
  esac
}

{
  cat <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Quarkus Flow Exploratory — Area A Report</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@300;400;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/carbon-components@10/css/carbon-components.min.css">
<style>
  body { margin: 0; }
  main.bx--content { max-width: 960px; margin: 0 auto; padding: 3rem 1rem 4rem; }
  .run-meta { color: #525252; margin: 0.5rem 0 2.5rem; }
  .run-meta code { font-family: 'IBM Plex Mono', monospace; }
  h1 { margin-bottom: 0; }
  h2 { margin: 2.5rem 0 1rem; }
  .bx--data-table-container { margin-bottom: 1rem; }
  .bx--data-table td { vertical-align: top; }
  img.evidence-shot { max-width: 100%; display: block; margin: 1rem 0; border: 1px solid #e0e0e0; }
  footer { color: #6f6f6f; font-size: 0.75rem; margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid #e0e0e0; max-width: 960px; margin-left: auto; margin-right: auto; padding-left: 1rem; padding-right: 1rem; box-sizing: border-box; }
  footer a { color: inherit; }
</style>
</head>
<body>
<header class="bx--header" role="banner" aria-label="Quarkus Flow Exploratory">
  <a class="bx--header__name" href="https://github.com/mcruzdev/quarkus-flow-exploratory">
    <span class="bx--header__name--prefix">Quarkus&nbsp;Flow&nbsp;</span>&nbsp;Exploratory
  </a>
</header>
<main class="bx--content">
HTML
  echo "<h1>Area A — Exploratory Run Report</h1>"
  echo "<p class=\"run-meta\">Run <code>${RUN_ID}</code> &middot; Generated $(timestamp)</p>"

  echo '<div class="bx--data-table-container">'
  echo '<table class="bx--data-table bx--data-table--zebra">'
  echo "<thead><tr><th>Step</th><th>Description</th><th>Result</th><th>Note</th></tr></thead>"
  echo "<tbody>"
  tail -n +2 "$RESULTS_TSV" | while IFS=$'\t' read -r id desc status note; do
    printf '<tr><td>%s</td><td>%s</td><td><span class="bx--tag bx--tag--%s">%s %s</span></td><td>%s</td></tr>\n' \
      "$id" "$desc" "$(status_tag_color "$status")" "$(status_emoji "$status")" "$(status_label "$status")" "$note"
  done
  echo "</tbody></table></div>"

  if [ -f "${EVIDENCE_DIR}/01-dev-ui-extensions.png" ]; then
    echo "<h2>Dev UI Screenshots</h2>"
    echo "<p>Extensions page, then the Flow extension's Workflows list after clicking through:</p>"
    echo '<img class="evidence-shot" src="01-dev-ui-extensions.png" alt="Quarkus Dev UI Extensions page">'
    echo '<img class="evidence-shot" src="02-dev-ui-workflows.png" alt="Quarkus Dev UI Workflows list">'
  fi

  cat <<'HTML'
<h2>Result Legend</h2>
<div class="bx--data-table-container">
<table class="bx--data-table">
<thead><tr><th>Result</th><th>Meaning</th></tr></thead>
<tbody>
<tr><td><span class="bx--tag bx--tag--green">🟢 Passed</span></td><td>Expected behavior was confirmed.</td></tr>
<tr><td><span class="bx--tag bx--tag--teal">🟡 Passed with observations</span></td><td>Main path worked, but notes, risks, or UX gaps were found.</td></tr>
<tr><td><span class="bx--tag bx--tag--red">🔴 Failed</span></td><td>Expected behavior did not work and needs follow-up.</td></tr>
<tr><td><span class="bx--tag bx--tag--gray">⛔ Blocked</span></td><td>The scenario could not be completed due to environment, dependency, or access issues.</td></tr>
<tr><td><span class="bx--tag bx--tag--purple">🔁 Needs follow-up</span></td><td>More focused testing or automation is required.</td></tr>
</tbody>
</table>
</div>
</main>
<footer>Generated by <a href="https://github.com/mcruzdev/quarkus-flow-exploratory">quarkus-flow-exploratory</a> — automates the <a href="https://docs.quarkiverse.io/quarkus-flow/dev/">Quarkus Flow Exploratory Testing Guide</a>, Area A. Styled with <a href="https://carbondesignsystem.com/">IBM Carbon</a>.</footer>
</body>
</html>
HTML
} > "$OUT_FILE"

echo "Wrote ${OUT_FILE}"
