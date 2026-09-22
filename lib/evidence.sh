#!/usr/bin/env bash
# Evidence-directory setup and command-output capture helpers.
# Sourced by area scripts — do not execute directly.

# init_evidence_dir <dir> — refuses to reuse a non-empty directory so runs
# never clobber each other; callers are expected to pass a timestamped path.
init_evidence_dir() {
  local dir="$1"
  if [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    echo "❌ Evidence directory already exists and is not empty: $dir" 1>&2
    exit 1
  fi
  ensure_dir "$dir"
}

# capture_cmd <description> <outfile> <cmd...>
capture_cmd() {
  local desc="$1" outfile="$2"
  shift 2
  log_info "Capturing: ${desc} -> $(basename "$outfile")"
  {
    echo "# ${desc}"
    echo "# command: $*"
    echo "# captured: $(timestamp)"
    echo "---"
    "$@"
  } >"$outfile" 2>&1 || true
}
