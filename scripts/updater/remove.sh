#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$REPO_ROOT/scripts/installer/config.sh"
config_load_file
config_apply_env

# --- Parse arguments ---
QUIET=0
VERBOSE=0
JSON_OUT=0
SKILL_REF=""

while [ $# -gt 0 ]; do
  case "$1" in
    -q|--quiet)
      QUIET=1; VERBOSE=0; JSON_OUT=0
      shift
      ;;
    -v|--verbose)
      QUIET=0; VERBOSE=1; JSON_OUT=0
      shift
      ;;
    --json)
      QUIET=0; VERBOSE=0; JSON_OUT=1
      shift
      ;;
    -*)
      echo "ERROR: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [ -z "$SKILL_REF" ]; then
        SKILL_REF="$1"
        shift
      else
        echo "ERROR: unexpected argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

[ -n "$SKILL_REF" ] || { echo "ERROR: skill reference required" >&2; exit 2; }

config_resolve

# --- Parse skill reference ---
if ! [[ "$SKILL_REF" =~ ^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$ ]]; then
  echo "ERROR: invalid skill reference '$SKILL_REF' (expected <namespace>/<name>)" >&2
  exit 2
fi

# --- Helpers ---
_err()  { echo "ERROR: $*" >&2; }
_info() { [ "$QUIET" -eq 0 ] && echo "$*" >&2 || true; }
_verb() { [ "$VERBOSE" -eq 1 ] && echo "$*" >&2 || true; }

_json_out() {
  local status="$1" key="$2" path="$3"
  jq -n --arg status "$status" --arg key "$key" --arg path "$path" \
    '{status: $status, key: $key, path: $path}'
}

# --- Main ---
INSTALL_DIR="$INSTALL_TARGET/$SKILL_REF"

if [ ! -d "$INSTALL_DIR" ]; then
  _info "Skill '$SKILL_REF' is not installed."
  [ "$JSON_OUT" -eq 1 ] && _json_out "not_installed" "$SKILL_REF" "$INSTALL_DIR"
  exit 6
fi

_verb "Removing $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"

_info "Removed '$SKILL_REF' from $INSTALL_DIR"
[ "$JSON_OUT" -eq 1 ] && _json_out "removed" "$SKILL_REF" "$INSTALL_DIR"
exit 0
