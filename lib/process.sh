#!/usr/bin/env bash
# Background process lifecycle for `mvnw quarkus:dev`.
#
# `mvnw` forks a child JVM, so a bare `kill $PID` can orphan it. The caller
# is expected to have run `set -m` so the backgrounded job becomes its own
# process group leader; we then signal the whole group, with an individual
# process-tree sweep as defense-in-depth.
# Sourced by area scripts — do not execute directly.

DEVMODE_PID=""
DEVMODE_PGID=""

# start_background <workdir> <logfile> <cmd...>
start_background() {
  local workdir="$1" logfile="$2"
  shift 2
  ensure_dir "$(dirname "$logfile")"
  (
    cd "$workdir" || exit 1
    exec "$@"
  ) >"$logfile" 2>&1 &
  DEVMODE_PID=$!
  DEVMODE_PGID="$(ps -o pgid= -p "$DEVMODE_PID" 2>/dev/null | tr -d ' ')"
  [ -n "$DEVMODE_PGID" ] || DEVMODE_PGID="$DEVMODE_PID"
}

is_alive() {
  kill -0 "$1" 2>/dev/null
}

# process_tree_pids <root_pid> — prints root + all descendant PIDs.
process_tree_pids() {
  local root="$1"
  echo "$root"
  local child
  for child in $(pgrep -P "$root" 2>/dev/null); do
    process_tree_pids "$child"
  done
}

# stop_background <pid> <pgid> [graceful_seconds]
stop_background() {
  local pid="$1" pgid="$2" graceful="${3:-10}"
  [ -n "$pid" ] || return 0
  if ! is_alive "$pid"; then
    return 0
  fi

  log_info "Stopping quarkus:dev process group ${pgid} (pid ${pid})"
  kill -TERM "-${pgid}" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true

  local waited=0
  while [ "$waited" -lt "$graceful" ] && is_alive "$pid"; do
    sleep 1
    waited=$((waited + 1))
  done

  if is_alive "$pid"; then
    log_warn "Process ${pid} still alive after ${graceful}s, sending SIGKILL"
    kill -KILL "-${pgid}" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  fi

  # Defense-in-depth: sweep any remaining descendants individually, in case
  # the process group signal missed a re-parented child.
  local leftover
  for leftover in $(process_tree_pids "$pid"); do
    if is_alive "$leftover"; then
      kill -KILL "$leftover" 2>/dev/null || true
    fi
  done
}

# wait_for_devmode_ready <logfile> <port> <pid> <timeout_s> <interval_s>
# Distinguishes "process died" (fail fast) from "still starting" (keep
# waiting up to timeout).
wait_for_devmode_ready() {
  local logfile="$1" port="$2" pid="$3" timeout="$4" interval="$5"
  local end=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$end" ]; do
    if ! is_alive "$pid"; then
      log_error "quarkus:dev process died during startup, see devmode.log"
      return 1
    fi
    if port_in_use "$port" && grep -qE "Listening on:|started in" "$logfile" 2>/dev/null; then
      return 0
    fi
    sleep "$interval"
  done
  log_error "Timed out after ${timeout}s waiting for quarkus:dev to become ready"
  return 1
}
