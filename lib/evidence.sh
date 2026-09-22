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

# capture_dev_ui_flow <base_url> <evidence_dir> <log_file> — best-effort
# Playwright walk through the Dev UI (Extensions -> Flow's Workflows link ->
# workflows list actually rendering a row), writing
# 01-dev-ui-extensions.png and 02-dev-ui-workflows.png into evidence_dir.
# Returns 1 (without failing the caller's step) if node isn't installed,
# dependencies aren't installed, or the flow errors out — same "degrade to
# an observation, don't fail the run" pattern as the jq fallback described
# in the README.
capture_dev_ui_flow() {
  local url="$1" evidence_dir="$2" log_file="$3"
  if ! command -v node >/dev/null 2>&1; then
    log_warn "node not found, skipping Dev UI screenshot flow"
    return 1
  fi
  if ! node "${REPO_ROOT}/scripts/playwright/area-a-dev-ui-flow.mjs" "$url" "$evidence_dir" >"$log_file" 2>&1; then
    log_warn "Dev UI screenshot flow failed, see $(basename "$log_file")"
    return 1
  fi
  [ -f "${evidence_dir}/01-dev-ui-extensions.png" ] && [ -f "${evidence_dir}/02-dev-ui-workflows.png" ]
}
