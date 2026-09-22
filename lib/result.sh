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

# render_summary <evidence_dir> <area_id> — writes SUMMARY.md and echoes
# it. area_id looks up the area's display title in config/areas.tsv
# (falls back to area_id itself if not found or the file is missing).
render_summary() {
  local dir="$1" area_id="${2:-}"
  local summary="${dir}/SUMMARY.md"

  if [ ! -f "$RESULTS_FILE" ]; then
    return
  fi

  local area_title="$area_id"
  local areas_tsv="${REPO_ROOT:-}/config/areas.tsv"
  if [ -n "$area_id" ] && [ -f "$areas_tsv" ]; then
    local found_title
    found_title="$(awk -F'\t' -v id="$area_id" '$1==id {print $2}' "$areas_tsv")"
    [ -n "$found_title" ] && area_title="$found_title"
  fi

  {
    echo "# ${area_title} — Exploratory Run Summary"
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

    if [ -f "${dir}/java-version.txt" ] || [ -f "${dir}/maven-version.txt" ] || [ -f "${dir}/os-info.txt" ]; then
      # GitHub (and any CommonMark renderer) renders raw <details>/<summary>
      # in Markdown, so this collapses by default without any JS. The blank
      # lines after each tag are required for the nested Markdown (bold
      # text, code fences) to render instead of being treated as raw HTML.
      echo "<details>"
      echo "<summary>Captured environment</summary>"
      echo
      for pair in "java-version.txt:Java" "maven-version.txt:Maven" "os-info.txt:OS"; do
        local file="${dir}/${pair%%:*}" label="${pair##*:}"
        if [ -f "$file" ]; then
          echo "**${label}**"
          echo
          echo '```'
          tail -n +5 "$file"
          echo '```'
          echo
        fi
      done
      echo "</details>"
      echo
    fi

    if [ -f "${dir}/01-dev-ui-extensions.png" ]; then
      echo "## Dev UI Screenshots"
      echo
      echo "Extensions page, then the Flow extension's Workflows list after clicking through:"
      echo
      echo "![Dev UI Extensions](01-dev-ui-extensions.png)"
      echo
      echo "![Dev UI Workflows](02-dev-ui-workflows.png)"
      echo
      if [ -f "${dir}/03-dev-ui-execute-valid.png" ]; then
        echo "Executing from the Dev UI with valid, then malformed, input:"
        echo
        echo "![Dev UI Execute — Valid Input](03-dev-ui-execute-valid.png)"
        echo
        [ -f "${dir}/04-dev-ui-execute-invalid.png" ] && echo "![Dev UI Execute — Invalid Input](04-dev-ui-execute-invalid.png)" && echo
      fi
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
