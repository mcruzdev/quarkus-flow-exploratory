#!/usr/bin/env bash
# HTTP + TCP port helpers. Uses bash's built-in /dev/tcp for port checks so
# there is no hard dependency on lsof/nc — matters for portability across
# macOS and GitHub Actions' ubuntu-latest runners.
# Sourced by area scripts — do not execute directly.

HTTP_STATUS=""
CURL_EXIT=0

# http_get <url> <out_file> [extra curl args...]
http_get() {
  local url="$1" out="$2"
  shift 2
  HTTP_STATUS="$(curl -sS -o "$out" -w '%{http_code}' --max-time "${HTTP_TIMEOUT_SECONDS:-10}" "$@" "$url" 2>"${out}.stderr")"
  CURL_EXIT=$?
}

# http_post <url> <out_file> [extra curl args...]
http_post() {
  local url="$1" out="$2"
  shift 2
  HTTP_STATUS="$(curl -sS -X POST -o "$out" -w '%{http_code}' --max-time "${HTTP_TIMEOUT_SECONDS:-10}" "$@" "$url" 2>"${out}.stderr")"
  CURL_EXIT=$?
}

# http_body_contains <file> <substring> — plain substring check, used where
# an exact JSON field match isn't the point (e.g. POST error bodies).
http_body_contains() {
  local file="$1" needle="$2"
  grep -F -q -- "$needle" "$file" 2>/dev/null
}

# json_field_equals <file> <jq_filter> <expected>
# Uses jq when available for a real JSON-aware comparison; falls back to a
# quoted substring grep otherwise (jq is recommended, not required).
json_field_equals() {
  local file="$1" filter="$2" expected="$3"
  if command -v jq >/dev/null 2>&1; then
    local actual
    actual="$(jq -r "$filter" "$file" 2>/dev/null)"
    [ "$actual" = "$expected" ]
  else
    grep -F -q "\"${expected}\"" "$file" 2>/dev/null
  fi
}

# json_field_is_null <file> <field>
json_field_is_null() {
  local file="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    [ "$(jq -r ".${field}" "$file" 2>/dev/null)" = "null" ]
  else
    grep -Eq "\"${field}\"[[:space:]]*:[[:space:]]*null" "$file" 2>/dev/null
  fi
}

# wait_for_port <host> <port> <timeout_seconds>
wait_for_port() {
  local host="$1" port="$2" timeout="$3"
  local end=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$end" ]; do
    if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; then
      exec 3>&- 3<&- 2>/dev/null || true
      return 0
    fi
    sleep 1
  done
  return 1
}

# port_in_use <port> — 0 (success) if something is listening on 127.0.0.1:port.
port_in_use() {
  local port="$1"
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null
  local rc=$?
  exec 3>&- 3<&- 2>/dev/null || true
  return $rc
}

# port_owner_pid <port> — best-effort PID of the listener, empty if unknown
# (only attempted when lsof happens to be present; never required).
port_owner_pid() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1
  fi
}

# http_poll_until_json_equals <url> <jq_filter> <expected> <timeout_s> <interval_s> <out_file>
# Treats connection errors / stray non-200s as "keep retrying" within the
# window — only a full timeout without ever seeing the expected value fails.
http_poll_until_json_equals() {
  local url="$1" filter="$2" expected="$3" timeout="$4" interval="$5" out="$6"
  local end=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$end" ]; do
    http_get "$url" "$out"
    if [ "$HTTP_STATUS" = "200" ] && json_field_equals "$out" "$filter" "$expected"; then
      return 0
    fi
    sleep "$interval"
  done
  return 1
}
