#!/usr/bin/env bash
# commit-msg hook — validates that the commit message follows Conventional Commits.
# Install: copy to .git/hooks/commit-msg and make executable.
#
# The hook receives a single argument: the path to a file containing the
# proposed commit message.  It exits 0 (accept) or 1 (reject).
set -euo pipefail

COMMIT_MSG_FILE="$1"

# Read the first line (subject) of the commit message.
read -r subject < "$COMMIT_MSG_FILE"

# Conventional Commits pattern:
#   <type>[optional !][optional (scope)]: <description>
#   ^[a-z]+[!]?(\([a-zA-Z0-9._-]+\))?: [a-z]
pattern='^[a-z]+[!]?(\([a-zA-Z0-9._-]+\))?: [a-z]'

if ! [[ "$subject" =~ $pattern ]]; then
  cat >&2 <<EOF
ERROR: Commit message does not follow Conventional Commits.

Expected format:
  <type>[optional scope]: <description>

Examples:
  feat: add user authentication
  fix(cache): resolve race condition on key expiry
  docs: update API reference for v2 endpoints

Received:
  $subject

Valid types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
EOF
  exit 1
fi

# Reject descriptions that end with a period.
if [[ "$subject" =~ \.$ ]]; then
  cat >&2 <<EOF
ERROR: Commit message description must not end with a period.

Received:
  $subject
EOF
  exit 1
fi

exit 0
