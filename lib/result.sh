#!/usr/bin/env bash
# Result tracking using the exploratory guide's own Result Legend
# (🟢 Passed / 🟡 Passed with observations / 🔴 Failed / ⛔ Blocked / 🔁 Needs follow-up).
#
# Results are tracked in an append-only TSV file rather than an in-memory
# associative array, so the suite stays bash-3.2-compatible (macOS's stock
# /bin/bash) and the file doubles as an evidence artifact.
# Sourced by area scripts — do not execute directly.

RESULTS_FILE=""

# init_results <file>
init_results() {
  RESULTS_FILE="$1"
  printf 'step_id\tdescription\tstatus\tnote\n' > "$RESULTS_FILE"
}

status_emoji() {
  case "$1" in
    PASS) echo "🟢" ;;
    OBSERVATION) echo "🟡" ;;
    FAIL) echo "🔴" ;;
    BLOCKED) echo "⛔" ;;
    FOLLOWUP) echo "🔁" ;;
    *) echo "❓" ;;
  esac
}

status_label() {
  case "$1" in
    PASS) echo "Passed" ;;
    OBSERVATION) echo "Passed with observations" ;;
    FAIL) echo "Failed" ;;
    BLOCKED) echo "Blocked" ;;
    FOLLOWUP) echo "Needs follow-up" ;;
    *) echo "Unknown" ;;
  esac
}

# record_result <step_id> <description> <status> [note]
record_result() {
  local id="$1" desc="$2" status="$3" note="${4:-}"
  printf '%s\t%s\t%s\t%s\n' "$id" "$desc" "$status" "$note" >> "$RESULTS_FILE"
  echo "$(status_emoji "$status") [${id}] ${desc}${note:+ — ${note}}"
}

# worst_status_exit_code — 0 unless any recorded step is FAIL or BLOCKED.
worst_status_exit_code() {
  if [ ! -f "$RESULTS_FILE" ]; then
    echo 1
    return
  fi
  if awk -F'\t' 'NR>1 && ($3=="FAIL" || $3=="BLOCKED")' "$RESULTS_FILE" | grep -q .; then
    echo 1
  else
    echo 0
  fi
}

# render_summary <evidence_dir> — writes SUMMARY.md and echoes it.
render_summary() {
  local dir="$1"
  local summary="${dir}/SUMMARY.md"

  if [ ! -f "$RESULTS_FILE" ]; then
    return
  fi

  {
    echo "# Area A — Exploratory Run Summary"
    echo
    echo "Run: $(basename "$dir")"
    echo "Date: $(timestamp)"
    echo
    echo "| Step | Description | Result | Note |"
    echo "|---|---|---|---|"
    tail -n +2 "$RESULTS_FILE" | while IFS=$'\t' read -r id desc status note; do
      printf '| %s | %s | %s %s | %s |\n' "$id" "$desc" "$(status_emoji "$status")" "$(status_label "$status")" "$note"
    done
    echo

    if [ -f "${dir}/dev-ui-screenshot.png" ]; then
      echo "## Dev UI Screenshot"
      echo
      echo "![Dev UI](dev-ui-screenshot.png)"
      echo
    fi

    echo "## Result Legend"
    echo
    echo "| Result | Meaning |"
    echo "|---|---|"
    echo "| 🟢 Passed | Expected behavior was confirmed. |"
    echo "| 🟡 Passed with observations | Main path worked, but notes, risks, or UX gaps were found. |"
    echo "| 🔴 Failed | Expected behavior did not work and needs follow-up. |"
    echo "| ⛔ Blocked | The scenario could not be completed due to environment, dependency, or access issues. |"
    echo "| 🔁 Needs follow-up | More focused testing or automation is required. |"
  } > "$summary"

  echo
  cat "$summary"
  echo
}
