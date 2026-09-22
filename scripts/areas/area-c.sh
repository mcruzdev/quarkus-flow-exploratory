#!/usr/bin/env bash
# Area C — Dev UI and Local Tracing automation.
#
# Automates the Quarkus Flow Exploratory Testing Guide's Area C: on top of
# Area A's base project (reused via lib/bootstrap.sh), add a second,
# richer Java DSL workflow ("traced": set -> function -> function, three
# tasks so the Dev UI graph and trace log are meaningful), compile, run
# under `quarkus:dev`, verify REST execution and trace log output, execute
# the workflow from the Dev UI itself with valid and invalid JSON input,
# and prove live reload works.
#
# Deliberately does NOT use `set -e` — see area-a.sh's header comment for
# why; the same reasoning applies here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=../../lib/http.sh
source "${REPO_ROOT}/lib/http.sh"
# shellcheck source=../../lib/process.sh
source "${REPO_ROOT}/lib/process.sh"
# shellcheck source=../../lib/evidence.sh
source "${REPO_ROOT}/lib/evidence.sh"
# shellcheck source=../../lib/result.sh
source "${REPO_ROOT}/lib/result.sh"
# shellcheck source=../../lib/bootstrap.sh
source "${REPO_ROOT}/lib/bootstrap.sh"

if [ -f "${REPO_ROOT}/config/defaults.env" ]; then
  # shellcheck source=../../config/defaults.env
  source "${REPO_ROOT}/config/defaults.env"
fi

# ---- Configuration (env-overridable; defaults.env already applied above) ----
: "${QF_VERSION:=1.1.0}"
: "${QUARKUS_PLATFORM_VERSION:=3.37.4}"
: "${TEST_GROUP_ID:=org.acme}"
: "${TEST_ARTIFACT_ID:=hello-flow}"
: "${APP_PORT:=8080}"
: "${READY_TIMEOUT_SECONDS:=180}"
: "${LIVE_RELOAD_TIMEOUT_SECONDS:=30}"
: "${LIVE_RELOAD_POLL_INTERVAL_SECONDS:=2}"
: "${HTTP_TIMEOUT_SECONDS:=10}"
: "${GRACEFUL_STOP_SECONDS:=10}"
: "${RETRY_MAX_ATTEMPTS:=3}"
: "${RETRY_DELAY_SECONDS:=5}"
export HTTP_TIMEOUT_SECONDS

if is_ci; then
  READY_TIMEOUT_SECONDS=$((READY_TIMEOUT_SECONDS * 2))
  RETRY_MAX_ATTEMPTS=$((RETRY_MAX_ATTEMPTS + 2))
fi

RUN_ID="$(run_id)"
WORKDIR="${REPO_ROOT}/work/area-c/${RUN_ID}"
PROJECT_DIR="${WORKDIR}/${TEST_ARTIFACT_ID}"
EVIDENCE_DIR="${REPO_ROOT}/evidence/area-c/${RUN_ID}"
BOOTSTRAP_TEMPLATES_DIR="${REPO_ROOT}/templates/area-a"
TEMPLATES_DIR="${REPO_ROOT}/templates/area-c"
BASE_URL="http://localhost:${APP_PORT}"
PACKAGE_PATH="$(java_package_to_path "$TEST_GROUP_ID")"

# Namespace/version the Java DSL builder defaults to (confirmed live against
# Dev UI in Area A/C exploration: group id org.acme -> namespace org-acme,
# version defaults to 0.0.1) — needed to build the Dev UI run-button id.
TRACED_NAMESPACE="$(echo "$TEST_GROUP_ID" | tr '.' '-')"
TRACED_VERSION="0.0.1"

init_evidence_dir "$EVIDENCE_DIR"
RUN_LOG="${EVIDENCE_DIR}/run.log"
init_results "${EVIDENCE_DIR}/results.tsv"
ensure_dir "$WORKDIR"

CLEANED_UP=false
cleanup() {
  $CLEANED_UP && return
  CLEANED_UP=true
  if [ -n "${DEVMODE_PID:-}" ]; then
    stop_background "$DEVMODE_PID" "$DEVMODE_PGID" "$GRACEFUL_STOP_SECONDS"
  fi
  render_summary "$EVIDENCE_DIR" "area-c"
}
trap cleanup EXIT INT TERM

# ---- Step functions ----
# Same fatal-vs-independent split as area-a.sh: setup through starting dev
# mode is fatal; the checks after that are independent of each other.

step_preflight() {
  if ! require_cmd java mvn curl git; then
    record_result preflight "Preflight tool check" BLOCKED "missing required command(s), see run.log"
    return 1
  fi
  local jv
  jv="$(java_major_version)"
  if [ -z "$jv" ] || [ "$jv" -lt 17 ]; then
    record_result preflight "Preflight tool check" BLOCKED "Java 17+ required, found: ${jv:-unknown}"
    return 1
  fi
  record_result preflight "Preflight tool check" PASS "java=${jv}"
  return 0
}

step_capture_environment() {
  capture_cmd "Java version" "${EVIDENCE_DIR}/java-version.txt" java -version
  capture_cmd "Maven version" "${EVIDENCE_DIR}/maven-version.txt" mvn -version
  capture_cmd "OS info" "${EVIDENCE_DIR}/os-info.txt" uname -a
  record_result capture_env "Capture environment info" PASS ""
  return 0
}

step_write_traced_workflow() {
  local pkg_dir="${PROJECT_DIR}/src/main/java/${PACKAGE_PATH}"
  ensure_dir "$pkg_dir"
  render_template "${TEMPLATES_DIR}/TracedFlow.java" "${pkg_dir}/TracedFlow.java" "PACKAGE=${TEST_GROUP_ID}"
  render_template "${TEMPLATES_DIR}/TracedResult.java" "${pkg_dir}/TracedResult.java" "PACKAGE=${TEST_GROUP_ID}"
  render_template "${TEMPLATES_DIR}/TracedResource.java" "${pkg_dir}/TracedResource.java" "PACKAGE=${TEST_GROUP_ID}"

  if [ ! -f "${pkg_dir}/TracedFlow.java" ] || [ ! -f "${pkg_dir}/TracedResult.java" ] || [ ! -f "${pkg_dir}/TracedResource.java" ]; then
    record_result write_traced "Write traced workflow + REST source files" FAIL "one or more source files missing after render"
    return 1
  fi

  record_result write_traced "Write traced workflow + REST source files" PASS ""
  return 0
}

step_start_devmode() {
  if port_in_use "$APP_PORT"; then
    local owner
    owner="$(port_owner_pid "$APP_PORT")"
    record_result start_devmode "Start quarkus:dev" BLOCKED "port ${APP_PORT} already in use${owner:+ (pid ${owner})}"
    return 1
  fi

  start_background "$PROJECT_DIR" "${EVIDENCE_DIR}/devmode.log" ./mvnw -B quarkus:dev

  if ! wait_for_devmode_ready "${EVIDENCE_DIR}/devmode.log" "$APP_PORT" "$DEVMODE_PID" "$READY_TIMEOUT_SECONDS" 2; then
    record_result start_devmode "Start quarkus:dev" FAIL "dev mode did not become ready within ${READY_TIMEOUT_SECONDS}s, see devmode.log"
    return 1
  fi

  if ! grep -q "Warming up 2 WorkflowDefinition beans" "${EVIDENCE_DIR}/devmode.log"; then
    record_result start_devmode "Start quarkus:dev" OBSERVATION "port is open but the expected 'Warming up 2 WorkflowDefinition beans' marker (hello + traced) was not seen in startup log (best-effort check)"
    return 0
  fi

  record_result start_devmode "Start quarkus:dev" PASS ""
  return 0
}

step_curl_traced_flow() {
  local out="${EVIDENCE_DIR}/traced-flow-response.json"
  http_get "${BASE_URL}/traced-flow" "$out"

  if [ "$CURL_EXIT" -ne 0 ]; then
    record_result curl_traced "GET /traced-flow" FAIL "curl exit ${CURL_EXIT} (connection issue — is dev mode listening?)"
    return 1
  fi
  if [ "$HTTP_STATUS" != "200" ]; then
    record_result curl_traced "GET /traced-flow" FAIL "expected 200, got ${HTTP_STATUS}"
    return 1
  fi
  if ! json_field_equals "$out" ".shout" "HELLO"; then
    record_result curl_traced "GET /traced-flow" FAIL "unexpected 'shout' field, see traced-flow-response.json"
    return 1
  fi

  record_result curl_traced "GET /traced-flow" PASS ""
  return 0
}

# step_verify_traces — relies on step ordering: it must run immediately
# after step_curl_traced_flow and before any other step that starts a
# workflow instance (the Dev UI execute steps below), so the only trace
# lines in devmode.log so far belong to the single 'traced' instance that
# curl just triggered.
step_verify_traces() {
  local log="${EVIDENCE_DIR}/devmode.log"
  local missing=()

  grep -qE "Workflow name=traced instanceId=[^ ]+ started" "$log" || missing+=("workflow started")
  grep -q "Task '.*' started" "$log" || missing+=("task started")
  grep -q "Task '.*' completed" "$log" || missing+=("task completed")
  grep -qE "Workflow name=traced instanceId=[^ ]+ completed" "$log" || missing+=("workflow completed")

  if [ "${#missing[@]}" -gt 0 ]; then
    local joined
    joined="$(IFS=,; echo "${missing[*]}")"
    record_result verify_traces "Verify trace log output for 'traced' workflow" FAIL "missing trace line(s): ${joined}, see devmode.log"
    return 1
  fi

  record_result verify_traces "Verify trace log output for 'traced' workflow" PASS ""
  return 0
}

step_dev_ui_workflows() {
  local out="${EVIDENCE_DIR}/dev-ui-response.html"
  http_get "${BASE_URL}/q/dev-ui" "$out" -L

  if [ "$HTTP_STATUS" != "200" ]; then
    record_result dev_ui_workflows "Dev UI reachable at /q/dev-ui" FAIL "expected 200, got ${HTTP_STATUS}"
    return 1
  fi

  local note="reachability-only check; screenshot flow failed or was skipped (node/Playwright unavailable), see dev-ui-flow.log"
  if capture_dev_ui_flow "$BASE_URL" "$EVIDENCE_DIR" "${EVIDENCE_DIR}/dev-ui-flow.log"; then
    note="clicked Extensions -> Flow's Workflows link and confirmed the list renders both 'hello' and 'traced'; see 01-dev-ui-extensions.png and 02-dev-ui-workflows.png"
  fi
  record_result dev_ui_workflows "Dev UI lists both workflows" OBSERVATION "$note"
  return 0
}

step_dev_ui_execute_valid() {
  local output_file="${EVIDENCE_DIR}/dev-ui-execute-valid-output.txt"
  local screenshot="03-dev-ui-execute-valid.png"

  if ! capture_dev_ui_execute "$BASE_URL" "$TRACED_NAMESPACE" "traced" "$TRACED_VERSION" '{"name":"World"}' \
      "$EVIDENCE_DIR" "$screenshot" "$output_file" "${EVIDENCE_DIR}/dev-ui-execute-valid.log"; then
    record_result dev_ui_execute_valid "Execute 'traced' from Dev UI with valid input" OBSERVATION "flow failed or was skipped (node/Playwright unavailable), see dev-ui-execute-valid.log"
    return 0
  fi

  local output
  output="$(cat "$output_file")"
  if echo "$output" | grep -q "^# Error"; then
    record_result dev_ui_execute_valid "Execute 'traced' from Dev UI with valid input" FAIL "valid input {\"name\":\"World\"} produced an error in the output panel, see ${screenshot} and dev-ui-execute-valid-output.txt"
    return 1
  fi
  if ! echo "$output" | grep -q "HELLO WORLD"; then
    record_result dev_ui_execute_valid "Execute 'traced' from Dev UI with valid input" FAIL "expected 'HELLO WORLD' not found in output, see ${screenshot} and dev-ui-execute-valid-output.txt"
    return 1
  fi

  record_result dev_ui_execute_valid "Execute 'traced' from Dev UI with valid input" PASS "see ${screenshot}"
  return 0
}

step_dev_ui_execute_invalid() {
  local output_file="${EVIDENCE_DIR}/dev-ui-execute-invalid-output.txt"
  local screenshot="04-dev-ui-execute-invalid.png"

  if ! capture_dev_ui_execute "$BASE_URL" "$TRACED_NAMESPACE" "traced" "$TRACED_VERSION" '{not valid json' \
      "$EVIDENCE_DIR" "$screenshot" "$output_file" "${EVIDENCE_DIR}/dev-ui-execute-invalid.log"; then
    record_result dev_ui_execute_invalid "Execute 'traced' from Dev UI with malformed input" OBSERVATION "flow failed or was skipped (node/Playwright unavailable), see dev-ui-execute-invalid.log"
    return 0
  fi

  local output
  output="$(cat "$output_file")"
  if echo "$output" | grep -q "^# Error"; then
    record_result dev_ui_execute_invalid "Execute 'traced' from Dev UI with malformed input" PASS "malformed input was clearly reported as an error in the output panel, see ${screenshot}"
    return 0
  fi

  record_result dev_ui_execute_invalid "Execute 'traced' from Dev UI with malformed input" OBSERVATION "no visible error for malformed input; output panel note: see ${screenshot} and dev-ui-execute-invalid-output.txt"
  return 0
}

step_live_reload() {
  local pkg_dir="${PROJECT_DIR}/src/main/java/${PACKAGE_PATH}"
  local target="${pkg_dir}/TracedFlow.java"
  local tmp="${target}.tmp"

  diff -u "${TEMPLATES_DIR}/TracedFlow.java" "${TEMPLATES_DIR}/TracedFlow.live-reload.java" \
    > "${EVIDENCE_DIR}/live-reload.diff" || true

  render_template "${TEMPLATES_DIR}/TracedFlow.live-reload.java" "$tmp" "PACKAGE=${TEST_GROUP_ID}"
  mv "$tmp" "$target"

  local out="${EVIDENCE_DIR}/traced-flow-response-after-reload.json"
  if http_poll_until_json_equals "${BASE_URL}/traced-flow" ".greeting" "hello from live reload" \
      "$LIVE_RELOAD_TIMEOUT_SECONDS" "$LIVE_RELOAD_POLL_INTERVAL_SECONDS" "$out"; then
    record_result live_reload "Live reload picks up edited workflow" PASS ""
    return 0
  fi

  tail -n 80 "${EVIDENCE_DIR}/devmode.log" 2>/dev/null | grep -iE "error|exception|live reload" \
    > "${EVIDENCE_DIR}/live-reload-devmode-log-tail.txt" || true
  record_result live_reload "Live reload picks up edited workflow" FAIL "new greeting not observed within ${LIVE_RELOAD_TIMEOUT_SECONDS}s, see traced-flow-response-after-reload.json and live-reload-devmode-log-tail.txt"
  return 1
}

# ---- Orchestration ----

main() {
  log_info "Area C run starting: RUN_ID=${RUN_ID}"
  log_info "Project dir: ${PROJECT_DIR}"
  log_info "Evidence dir: ${EVIDENCE_DIR}"

  step_preflight || exit 1
  step_capture_environment
  bootstrap_create_project || exit 1
  bootstrap_add_flow_extension || exit 1
  # bootstrap_write_java_dsl_sources is the only bootstrap function that
  # reads TEMPLATES_DIR — point it at Area A's templates just for this one
  # call (reusing HelloFlow/Message/HelloResource verbatim), then the
  # script's own TEMPLATES_DIR (templates/area-c) applies again below.
  TEMPLATES_DIR="$BOOTSTRAP_TEMPLATES_DIR" bootstrap_write_java_dsl_sources || exit 1
  step_write_traced_workflow || exit 1
  bootstrap_compile || exit 1
  step_start_devmode || exit 1

  step_curl_traced_flow || true
  step_verify_traces || true
  step_dev_ui_workflows || true
  step_dev_ui_execute_valid || true
  step_dev_ui_execute_invalid || true
  step_live_reload || true
}

set -m
main "$@"
exit "$(worst_status_exit_code)"
