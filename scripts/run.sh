#!/usr/bin/env bash
# Thin dispatcher so the suite has one stable entrypoint as more areas are
# added. Each area script under scripts/areas/ also remains independently
# runnable on its own.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage: $0 <area> [args...]"
  echo
  echo "Available areas:"
  for f in "${SCRIPT_DIR}"/areas/*.sh; do
    [ -e "$f" ] || continue
    echo "  - $(basename "$f" .sh)"
  done
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

area="$1"
shift
target="${SCRIPT_DIR}/areas/${area}.sh"

if [ ! -f "$target" ]; then
  echo "Unknown area: ${area}" 1>&2
  usage
  exit 1
fi

exec "$target" "$@"
