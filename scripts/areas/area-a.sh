#!/usr/bin/env bash
# Area A — Local Developer Workflow automation.
#
# Automates the Quarkus Flow Exploratory Testing Guide's Area A: generate a
# Quarkus project via the Maven plugin (no Quarkus CLI dependency), add
# quarkus-flow + rest-jackson, write a minimal Java DSL "hello" workflow and
# REST resource, compile, run it under `quarkus:dev`, verify GET/POST
# behavior and Dev UI reachability, and prove live reload works.
#
# Deliberately does NOT use `set -e`: this script juggles background
# processes, retries, and many command substitutions, where -e's interaction
# with `local var=$(cmd)` and pipelines is a common source of silent bugs.
# Every step instead checks its own exit status explicitly.
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
  # CI runners tend to be slower / have colder caches on first run.
  READY_TIMEOUT_SECONDS=$((READY_TIMEOUT_SECONDS * 2))
  RETRY_MAX_ATTEMPTS=$((RETRY_MAX_ATTEMPTS + 2))
fi

RUN_ID="$(run_id)"
WORKDIR="${REPO_ROOT}/work/area-a/${RUN_ID}"
PROJECT_DIR="${WORKDIR}/${TEST_ARTIFACT_ID}"
EVIDENCE_DIR="${REPO_ROOT}/evidence/area-a/${RUN_ID}"
TEMPLATES_DIR="${REPO_ROOT}/templates/area-a"
BASE_URL="http://localhost:${APP_PORT}"
PACKAGE_PATH="$(java_package_to_path "$TEST_GROUP_ID")"

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
  render_summary "$EVIDENCE_DIR"
}
trap cleanup EXIT INT TERM

# ---- Step functions ----
# Each records its own result(s) and returns 0/1. Steps 1-6 (through compile)
# and starting dev mode are treated as fatal by main(): if any of those fail
# there is nothing meaningful left to check, so the run stops there. The
# per-endpoint checks after that are independent and all run regardless of
# each other's outcome.

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

_mvn_create_project() {
  mvn -B -q io.quarkus.platform:quarkus-maven-plugin:"${QUARKUS_PLATFORM_VERSION}":create \
    -DprojectGroupId="${TEST_GROUP_ID}" \
    -DprojectArtifactId="${TEST_ARTIFACT_ID}" \
    -DplatformVersion="${QUARKUS_PLATFORM_VERSION}" \
    -Dextensions="rest-jackson" \
    -DoutputDirectory="${WORKDIR}" \
    >> "${EVIDENCE_DIR}/create-project.log" 2>&1
}

step_create_project() {
  : > "${EVIDENCE_DIR}/create-project.log"

  if port_in_use "$APP_PORT"; then
    local owner
    owner="$(port_owner_pid "$APP_PORT")"
    record_result create_project "Create Quarkus project" BLOCKED "port ${APP_PORT} already in use${owner:+ (pid ${owner})}"
    return 1
  fi

  ensure_dir "$WORKDIR"
  if ! retry "$RETRY_MAX_ATTEMPTS" "$RETRY_DELAY_SECONDS" _mvn_create_project; then
    record_result create_project "Create Quarkus project" BLOCKED "project generation failed after retries, see create-project.log"
    return 1
  fi

  if [ ! -f "${PROJECT_DIR}/pom.xml" ] || [ ! -x "${PROJECT_DIR}/mvnw" ]; then
    record_result create_project "Create Quarkus project" FAIL "pom.xml or mvnw missing after generation"
    return 1
  fi

  find "$PROJECT_DIR" -type f | sort > "${EVIDENCE_DIR}/initial-files.txt"
  echo "$PROJECT_DIR" > "${EVIDENCE_DIR}/project-path.txt"
  record_result create_project "Create Quarkus project" PASS ""
  return 0
}

_mvn_add_flow_extension() {
  (cd "$PROJECT_DIR" && ./mvnw -B -q quarkus:add-extension \
    -Dextensions="io.quarkiverse.flow:quarkus-flow:${QF_VERSION}") \
    >> "${EVIDENCE_DIR}/add-extension.log" 2>&1
}

step_add_flow_dependency() {
  : > "${EVIDENCE_DIR}/add-extension.log"

  if ! retry "$RETRY_MAX_ATTEMPTS" "$RETRY_DELAY_SECONDS" _mvn_add_flow_extension; then
    record_result add_extension "Add quarkus-flow extension" BLOCKED "extension add failed after retries, see add-extension.log"
    return 1
  fi

  if ! grep -q "quarkus-flow" "${PROJECT_DIR}/pom.xml"; then
    record_result add_extension "Add quarkus-flow extension" FAIL "quarkus-flow not found in pom.xml after add-extension"
    return 1
  fi

  cp "${PROJECT_DIR}/pom.xml" "${EVIDENCE_DIR}/pom.xml"
  grep -n "quarkus-flow\|quarkus-rest-jackson" "${PROJECT_DIR}/pom.xml" > "${EVIDENCE_DIR}/pom-dependencies.txt" || true
  record_result add_extension "Add quarkus-flow extension" PASS ""
  return 0
}

step_write_source_files() {
  local pkg_dir="${PROJECT_DIR}/src/main/java/${PACKAGE_PATH}"
  ensure_dir "$pkg_dir"
  render_template "${TEMPLATES_DIR}/HelloFlow.java" "${pkg_dir}/HelloFlow.java" "PACKAGE=${TEST_GROUP_ID}"
  render_template "${TEMPLATES_DIR}/Message.java" "${pkg_dir}/Message.java" "PACKAGE=${TEST_GROUP_ID}"
  render_template "${TEMPLATES_DIR}/HelloResource.java" "${pkg_dir}/HelloResource.java" "PACKAGE=${TEST_GROUP_ID}"

  if [ ! -f "${pkg_dir}/HelloFlow.java" ] || [ ! -f "${pkg_dir}/Message.java" ] || [ ! -f "${pkg_dir}/HelloResource.java" ]; then
    record_result write_sources "Write workflow + REST source files" FAIL "one or more source files missing after render"
    return 1
  fi

  record_result write_sources "Write workflow + REST source files" PASS ""
  return 0
}

step_compile() {
  if ! (cd "$PROJECT_DIR" && ./mvnw -B clean compile) > "${EVIDENCE_DIR}/compile.log" 2>&1; then
    record_result compile "Compile project" FAIL "compile failed, see compile.log"
    return 1
  fi
  if grep -q "BUILD FAILURE" "${EVIDENCE_DIR}/compile.log"; then
    record_result compile "Compile project" FAIL "BUILD FAILURE found in compile.log despite exit 0"
    return 1
  fi
  record_result compile "Compile project" PASS ""
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

  if ! grep -q "HelloFlow" "${EVIDENCE_DIR}/devmode.log"; then
    record_result start_devmode "Start quarkus:dev" OBSERVATION "port is open but 'HelloFlow' marker not seen in startup log (best-effort check)"
    return 0
  fi

  record_result start_devmode "Start quarkus:dev" PASS ""
  return 0
}

step_verify_port() {
  if wait_for_port localhost "$APP_PORT" 5; then
    record_result verify_port "Verify port ${APP_PORT} is listening" PASS ""
    return 0
  fi
  record_result verify_port "Verify port ${APP_PORT} is listening" FAIL "port not open"
  return 1
}

step_curl_hello_flow() {
  local out="${EVIDENCE_DIR}/hello-flow-response.json"
  http_get "${BASE_URL}/hello-flow" "$out"

  if [ "$CURL_EXIT" -ne 0 ]; then
    record_result get_hello "GET /hello-flow" FAIL "curl exit ${CURL_EXIT} (connection issue — is dev mode listening?)"
    return 1
  fi
  if [ "$HTTP_STATUS" != "200" ]; then
    record_result get_hello "GET /hello-flow" FAIL "expected 200, got ${HTTP_STATUS}"
    return 1
  fi
  if json_field_is_null "$out" "message"; then
    local debug_out="${EVIDENCE_DIR}/hello-flow-debug-diagnosis.json"
    http_get "${BASE_URL}/hello-flow/debug" "$debug_out"
    record_result get_hello "GET /hello-flow" FAIL "message was null; see hello-flow-response.json and hello-flow-debug-diagnosis.json"
    return 1
  fi
  if ! json_field_equals "$out" ".message" "hello world!"; then
    record_result get_hello "GET /hello-flow" FAIL "unexpected message body, see hello-flow-response.json"
    return 1
  fi

  record_result get_hello "GET /hello-flow" PASS ""
  return 0
}

step_curl_debug() {
  local out="${EVIDENCE_DIR}/hello-flow-debug-response.json"
  http_get "${BASE_URL}/hello-flow/debug" "$out"

  if [ "$CURL_EXIT" -ne 0 ] || [ "$HTTP_STATUS" != "200" ]; then
    record_result get_debug "GET /hello-flow/debug" FAIL "curl_exit=${CURL_EXIT} status=${HTTP_STATUS}"
    return 1
  fi
  if ! json_field_equals "$out" ".message" "hello world!"; then
    record_result get_debug "GET /hello-flow/debug" FAIL "unexpected body, see hello-flow-debug-response.json"
    return 1
  fi

  record_result get_debug "GET /hello-flow/debug" PASS ""
  return 0
}

step_curl_post_405() {
  local out="${EVIDENCE_DIR}/hello-flow-post-response.txt"
  http_post "${BASE_URL}/hello-flow" "$out"

  if [ "$HTTP_STATUS" = "405" ]; then
    record_result post_405 "POST /hello-flow rejected" PASS ""
    return 0
  fi
  record_result post_405 "POST /hello-flow rejected" FAIL "expected 405, got ${HTTP_STATUS}"
  return 1
}

step_dev_ui_reachability() {
  local out="${EVIDENCE_DIR}/dev-ui-response.html"
  # Quarkus commonly redirects /q/dev-ui -> /q/dev-ui/ (302); follow it so a
  # bare redirect isn't mistaken for "unreachable".
  http_get "${BASE_URL}/q/dev-ui" "$out" -L

  if [ "$HTTP_STATUS" != "200" ]; then
    record_result dev_ui "Dev UI reachable at /q/dev-ui" FAIL "expected 200, got ${HTTP_STATUS}"
    return 1
  fi

  local note="reachability-only check; screenshot capture failed or was skipped (node/Playwright unavailable), see dev-ui-screenshot.log"
  if capture_screenshot "${BASE_URL}/q/dev-ui/" "${EVIDENCE_DIR}/dev-ui-screenshot.png" "${EVIDENCE_DIR}/dev-ui-screenshot.log"; then
    note="dev-ui-screenshot.png captured for visual verification (workflow listed, diagram renders)"
  fi
  record_result dev_ui "Dev UI reachable at /q/dev-ui" OBSERVATION "$note"
  return 0
}

step_live_reload() {
  local pkg_dir="${PROJECT_DIR}/src/main/java/${PACKAGE_PATH}"
  local target="${pkg_dir}/HelloFlow.java"
  local tmp="${target}.tmp"

  diff -u "${TEMPLATES_DIR}/HelloFlow.java" "${TEMPLATES_DIR}/HelloFlow.live-reload.java" \
    > "${EVIDENCE_DIR}/live-reload.diff" || true

  render_template "${TEMPLATES_DIR}/HelloFlow.live-reload.java" "$tmp" "PACKAGE=${TEST_GROUP_ID}"
  mv "$tmp" "$target"

  local out="${EVIDENCE_DIR}/hello-flow-response-after-reload.json"
  if http_poll_until_json_equals "${BASE_URL}/hello-flow" ".message" "hello from live reload!" \
      "$LIVE_RELOAD_TIMEOUT_SECONDS" "$LIVE_RELOAD_POLL_INTERVAL_SECONDS" "$out"; then
    record_result live_reload "Live reload picks up edited message" PASS ""
    return 0
  fi

  tail -n 80 "${EVIDENCE_DIR}/devmode.log" 2>/dev/null | grep -iE "error|exception|live reload" \
    > "${EVIDENCE_DIR}/live-reload-devmode-log-tail.txt" || true
  record_result live_reload "Live reload picks up edited message" FAIL "new message not observed within ${LIVE_RELOAD_TIMEOUT_SECONDS}s, see hello-flow-response-after-reload.json and live-reload-devmode-log-tail.txt"
  return 1
}

# ---- Orchestration ----

main() {
  log_info "Area A run starting: RUN_ID=${RUN_ID}"
  log_info "Project dir: ${PROJECT_DIR}"
  log_info "Evidence dir: ${EVIDENCE_DIR}"

  step_preflight || exit 1
  step_capture_environment
  step_create_project || exit 1
  step_add_flow_dependency || exit 1
  step_write_source_files || exit 1
  step_compile || exit 1
  step_start_devmode || exit 1

  step_verify_port || true
  step_curl_hello_flow || true
  step_curl_debug || true
  step_curl_post_405 || true
  step_dev_ui_reachability || true
  step_live_reload || true
}

set -m
main "$@"
exit "$(worst_status_exit_code)"
