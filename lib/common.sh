#!/usr/bin/env bash
# Shared logging, preflight, and small utility helpers.
# Sourced by area scripts — do not execute directly.

RUN_LOG="${RUN_LOG:-}"

_log() {
  local prefix="$1"
  shift
  local line
  line="$(timestamp) ${prefix} $*"
  echo "$line"
  if [ -n "$RUN_LOG" ]; then
    echo "$line" >> "$RUN_LOG" 2>/dev/null || true
  fi
}

log_info()  { _log "ℹ️ " "$@"; }
log_warn()  { _log "⚠️ " "$@"; }
log_error() { _log "❌" "$@" 1>&2; }
log_step()  { _log "▶️ " "$@"; }

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
run_id()    { date -u +"%Y%m%dT%H%M%SZ"; }

die() {
  log_error "$@"
  exit 1
}

# require_cmd <cmd> [cmd...] — logs every missing command before returning,
# rather than failing on the first one, so a single preflight run surfaces
# the whole gap.
require_cmd() {
  local missing=() cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log_error "Missing required command(s): ${missing[*]}"
    return 1
  fi
  return 0
}

ensure_dir() { mkdir -p "$1"; }

# java_major_version — prints e.g. "17" or "21" regardless of old "1.8"-style
# version strings.
java_major_version() {
  java -version 2>&1 | head -1 | sed -nE 's/.*"([0-9]+)(\.[0-9]+)?.*/\1/p'
}

# java_package_to_path org.acme -> org/acme
java_package_to_path() {
  echo "$1" | tr '.' '/'
}

# render_template <src> <dest> [KEY=VALUE ...]
# Copies src to dest, replacing every @@KEY@@ token with VALUE.
render_template() {
  local src="$1" dest="$2"
  shift 2
  ensure_dir "$(dirname "$dest")"
  cp "$src" "$dest"
  local kv key value tmp
  for kv in "$@"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    tmp="$(mktemp)"
    sed "s|@@${key}@@|${value}|g" "$dest" > "$tmp"
    mv "$tmp" "$dest"
  done
}

# retry <max_attempts> <delay_seconds> <cmd...>
retry() {
  local max="$1" delay="$2"
  shift 2
  local attempt=1
  until "$@"; do
    if [ "$attempt" -ge "$max" ]; then
      log_error "Command failed after ${attempt} attempt(s): $*"
      return 1
    fi
    log_warn "Attempt ${attempt}/${max} failed, retrying in ${delay}s: $*"
    sleep "$delay"
    attempt=$((attempt + 1))
  done
  return 0
}

# is_ci — true when running under GitHub Actions (or any CI setting the
# conventional CI=true env var), used to widen timeouts/retries.
is_ci() {
  [ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ]
}
