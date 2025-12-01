#!/usr/bin/env bash
set -euo pipefail

# Install a set of skills during devcontainer creation.
# Usage: bash examples/postcreate.sh <marketplace-url-or-path>
#
# Example:
#   bash examples/postcreate.sh https://github.com/example/skills-marketplace.git
#   bash examples/postcreate.sh .

MARKETPLACE="${1:?missing marketplace URL or path}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/installer/install.sh"

skills=(
  "example/hello-world"
  "example/code-review"
)

errors=0
for skill in "${skills[@]}"; do
  echo "Installing $skill..." >&2
  if out=$(bash "$INSTALLER" --from "$MARKETPLACE" "$skill" 2>&1); then
    echo "$out" >&2
  else
    rc=$?
    echo "ERROR: failed to install $skill (exit $rc)" >&2
    echo "$out" >&2
    errors=$((errors + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  echo "$errors skill(s) failed to install." >&2
  exit 1
fi

echo "All skills installed." >&2
