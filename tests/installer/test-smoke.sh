#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_SCRIPT="$REPO_ROOT/scripts/installer/install.sh"
UPDATE_SCRIPT="$REPO_ROOT/scripts/updater/update.sh"
REMOVE_SCRIPT="$REPO_ROOT/scripts/updater/remove.sh"
LIST_SCRIPT="$REPO_ROOT/scripts/catalog/list.sh"
SKILL_REF="example/code-review"

PASS=0
FAIL=0

assert_exit() {
  local label="$1" expected_rc="$2" actual_rc="$3"
  if [ "$expected_rc" -eq "$actual_rc" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit $expected_rc, got $actual_rc)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (file missing: $path)"
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

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  FAIL: $label (unexpectedly contains: $needle)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  fi
}

run_no_tty() {
  local timeout_sec="${1:-10}"
  shift
  set +e
  local out
  out=$(timeout "$timeout_sec" bash "$@" < /dev/null 2>&1)
  local rc=$?
  set -e
  printf '%s\n' "$out"
  return $rc
}

# --- Setup ---
target=$(mktemp -d)
trap 'rm -rf "$target"' EXIT

# --- Step 1: Install ---
echo "=== Step 1: Install $SKILL_REF from live marketplace ==="

out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
      run_no_tty 30 "$INSTALL_SCRIPT" --from "$REPO_ROOT" "$SKILL_REF") && rc=0 || rc=$?
echo "$out"
assert_exit "install exits 0" 0 "$rc"
assert_file "skill.yaml present" "$target/$SKILL_REF/skill.yaml"
assert_file "entrypoint SKILL.md present" "$target/$SKILL_REF/SKILL.md"
assert_file "material template present" "$target/$SKILL_REF/templates/review-checklist.md"
assert_contains "installed message" "$out" "Installed"
assert_not_contains "no interactive prompts" "$out" "[Y/n]"

# --- Step 2: List ---
echo ""
echo "=== Step 2: List installed skills ==="

out=$(run_no_tty 10 "$LIST_SCRIPT" --from "$REPO_ROOT") && rc=0 || rc=$?
echo "$out"
assert_exit "list exits 0" 0 "$rc"
assert_contains "installed skill appears in catalog list" "$out" "$SKILL_REF"

# --- Step 3: Update (no-op, already current) ---
echo ""
echo "=== Step 3: Update $SKILL_REF (expect already current) ==="

out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
      run_no_tty 30 "$UPDATE_SCRIPT" --from "$REPO_ROOT" "$SKILL_REF") && rc=0 || rc=$?
echo "$out"
assert_exit "update exits 0" 0 "$rc"
assert_contains "already current message" "$out" "already current"
assert_not_contains "no interactive prompts in update" "$out" "[Y/n]"

# --- Step 4: Remove ---
echo ""
echo "=== Step 4: Remove $SKILL_REF ==="

out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      run_no_tty 15 "$REMOVE_SCRIPT" "$SKILL_REF") && rc=0 || rc=$?
echo "$out"
assert_exit "remove exits 0" 0 "$rc"
assert_contains "removed message" "$out" "Removed"
assert_not_contains "no interactive prompts in remove" "$out" "[Y/n]"

# Verify the skill directory is gone
if [ ! -d "$target/$SKILL_REF" ]; then
  echo "  PASS: skill directory removed from disk"
  PASS=$((PASS + 1))
else
  echo "  FAIL: skill directory still exists after remove: $target/$SKILL_REF"
  FAIL=$((FAIL + 1))
fi

# --- Step 5: List again (verify removed skill is gone from catalog) ---
echo ""
echo "=== Step 5: List (verify skill still in catalog, not installed) ==="

out=$(run_no_tty 10 "$LIST_SCRIPT" --from "$REPO_ROOT") && rc=0 || rc=$?
echo "$out"
assert_exit "list exits 0" 0 "$rc"
# The skill is still in the catalog index, just not installed locally.
# list.sh shows catalog contents, so it will still appear.
assert_contains "skill still in catalog index" "$out" "$SKILL_REF"

# --- Step 6: Reinstall to verify clean state ---
echo ""
echo "=== Step 6: Reinstall after remove ==="

out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
      run_no_tty 30 "$INSTALL_SCRIPT" --from "$REPO_ROOT" "$SKILL_REF") && rc=0 || rc=$?
echo "$out"
assert_exit "reinstall exits 0" 0 "$rc"
assert_file "skill.yaml present after reinstall" "$target/$SKILL_REF/skill.yaml"
assert_contains "installed message on reinstall" "$out" "Installed"

# --- Summary ---
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
