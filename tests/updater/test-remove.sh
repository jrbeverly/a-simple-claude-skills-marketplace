#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REMOVE_SCRIPT="$REPO_ROOT/scripts/updater/remove.sh"
INSTALL_SCRIPT="$REPO_ROOT/scripts/installer/install.sh"
MARKETPLACE="$REPO_ROOT/tests/installer/fixtures/marketplace"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    got:      $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local label="$1" expected_rc="$2" actual_rc="$3"
  if [ "$expected_rc" -eq "$actual_rc" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected exit: $expected_rc"
    echo "    got exit:      $actual_rc"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_missing() {
  local label="$1" path="$2"
  if [ ! -d "$path" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (directory still exists: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    output:"
    echo "$haystack"
    FAIL=$((FAIL + 1))
  fi
}

run_remove() {
  local target="$1"
  shift
  set +e
  local out
  out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
        bash "$REMOVE_SCRIPT" "$@" 2>&1)
  local rc=$?
  set -e
  printf '%s\n' "$out"
  return $rc
}

echo "=== Remove installed skill ==="
target=$(mktemp -d)
trap 'rm -rf "$target"' EXIT

CLAUDE_SKILLS_INSTALL_TARGET="$target" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

out=$(run_remove "$target" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "remove exits 0" 0 "$rc"
assert_contains "reports removed" "$out" "Removed"
assert_dir_missing "skill directory removed" "$target/example/hello-world"

echo ""
echo "=== Remove non-installed skill ==="
out=$(run_remove "$target" "example/nonexistent") && rc=0 || rc=$?
echo "$out"
assert_exit "remove non-installed exits 6 (CONFLICT)" 6 "$rc"
assert_contains "reports not installed" "$out" "not installed"

echo ""
echo "=== Remove already removed skill (idempotent) ==="
out=$(run_remove "$target" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "remove already removed exits 6 (CONFLICT)" 6 "$rc"
assert_contains "reports not installed on second remove" "$out" "not installed"

echo ""
echo "=== Remove invalid skill reference ==="
out=$(run_remove "$target" "badformat") && rc=0 || rc=$?
echo "$out"
assert_exit "remove invalid ref exits 2 (INVALID_USAGE)" 2 "$rc"

echo ""
echo "=== Remove missing argument ==="
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      bash "$REMOVE_SCRIPT" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "remove missing arg exits 2" 2 "$rc"

echo ""
echo "=== Remove --json output ==="
target2=$(mktemp -d)
trap 'rm -rf "$target2"' EXIT

CLAUDE_SKILLS_INSTALL_TARGET="$target2" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$target2/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

set +e
json_out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target2" \
           bash "$REMOVE_SCRIPT" --json "example/hello-world" 2>/dev/null)
rc=$?
set -e
assert_exit "--json remove exits 0" 0 "$rc"
echo "$json_out" | jq -e '.status == "removed"' >/dev/null 2>&1
jq_rc=$?
assert_eq "--json output is valid JSON with status=removed" "0" "$jq_rc"
assert_contains "--json output has key" "$json_out" '"key": "example/hello-world"'
assert_dir_missing "skill directory removed after --json" "$target2/example/hello-world"
rm -rf "$target2"

echo ""
echo "=== Remove --json non-installed ==="
target3=$(mktemp -d)
trap 'rm -rf "$target3"' EXIT

set +e
json_out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target3" \
           bash "$REMOVE_SCRIPT" --json "example/nonexistent" 2>/dev/null)
rc=$?
set -e
assert_exit "--json non-installed exits 6" 6 "$rc"
echo "$json_out" | jq -e '.status == "not_installed"' >/dev/null 2>&1
jq_rc=$?
assert_eq "--json non-installed has correct status" "0" "$jq_rc"
rm -rf "$target3"

echo ""
echo "=== Remove --quiet mode produces no stdout ==="
target4=$(mktemp -d)
trap 'rm -rf "$target4"' EXIT

CLAUDE_SKILLS_INSTALL_TARGET="$target4" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$target4/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

set +e
quiet_out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target4" \
            bash "$REMOVE_SCRIPT" --quiet "example/hello-world" 2>/dev/null)
rc=$?
set -e
assert_exit "--quiet remove exits 0" 0 "$rc"
assert_eq "--quiet produces empty stdout" "" "$quiet_out"
assert_dir_missing "skill directory removed in quiet mode" "$target4/example/hello-world"
rm -rf "$target4"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
