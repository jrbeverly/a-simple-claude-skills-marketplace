#!/usr/bin/env bash
set -euo pipefail

# Upgrade all installed skills to the latest version from a catalog.
# Usage: bash examples/upgrade-all.sh --from <marketplace-url-or-path>
#
# Example:
#   bash examples/upgrade-all.sh --from https://github.com/example/skills-marketplace.git
#   bash examples/upgrade-all.sh --from .

MARKETPLACE_URL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from)
      [ $# -gt 1 ] || { echo "ERROR: --from requires a value" >&2; exit 2; }
      MARKETPLACE_URL="$2"
      shift 2
      ;;
    -*)
      echo "ERROR: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      echo "ERROR: unexpected argument: $1" >&2
      exit 2
      ;;
  esac
done

[ -n "$MARKETPLACE_URL" ] || { echo "ERROR: --from is required" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/installer/install.sh"
INSTALL_TARGET="${CLAUDE_SKILLS_INSTALL_TARGET:-$HOME/.claude/skills}"

if [ ! -d "$INSTALL_TARGET" ]; then
  echo "No skills installed (directory $INSTALL_TARGET not found)." >&2
  exit 0
fi

upgraded=0
skipped=0

for skill_dir in "$INSTALL_TARGET"/*/*; do
  [ -d "$skill_dir" ] || continue
  [ -f "$skill_dir/skill.yaml" ] || continue
  skill_key="${skill_dir#$INSTALL_TARGET/}"
  echo "Upgrading $skill_key..." >&2
  if out=$(bash "$INSTALLER" --from "$MARKETPLACE_URL" --force "$skill_key" 2>&1); then
    echo "$out" >&2
    if echo "$out" | grep -q 'already installed'; then
      skipped=$((skipped + 1))
    else
      upgraded=$((upgraded + 1))
    fi
  else
    rc=$?
    echo "WARNING: upgrade of $skill_key failed (exit $rc)" >&2
    echo "$out" >&2
  fi
done

echo "Upgrade complete ($upgraded upgraded, $skipped skipped)." >&2
