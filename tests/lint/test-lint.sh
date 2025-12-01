#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LINT_SCRIPT="$REPO_ROOT/scripts/lint/lint.sh"
FIXTURES="$REPO_ROOT/tests/lint/fixtures"
PASS=0
FAIL=0

# Ensure yq is on PATH
export PATH="$REPO_ROOT/.local/bin:$PATH"

run_lint() {
  local skills_dir="$1" scripts_dir="$2" tests_dir="$3"
  shift 3
  set +e
  local out
  out=$(SKILLS_DIR="$skills_dir" SCRIPTS_DIR="$scripts_dir" TESTS_DIR="$tests_dir" bash "$LINT_SCRIPT" "$@" 2>&1)
  local rc=$?
  set -e
  printf '%s\n' "$out"
  return $rc
}

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

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected to contain: $needle)"
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

# --- Test: pass fixture (clean repo) ---
echo "=== Pass fixture: clean repo ==="

pass_skills="$FIXTURES/pass/skills"
pass_scripts="$FIXTURES/pass/scripts"
pass_tests="$FIXTURES/pass/tests"

out=$(run_lint "$pass_skills" "$pass_scripts" "$pass_tests" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "clean repo exits 0" 0 "$rc"
assert_contains "clean repo reports no violations" "$out" "No violations found"

# --- Test: pass fixture --json ---
echo ""
echo "=== Pass fixture: --json output ==="
out=$(run_lint "$pass_skills" "$pass_scripts" "$pass_tests" --json) && rc=0 || rc=$?
assert_exit "--json exits 0 on clean" 0 "$rc"
assert_contains "--json is valid JSON (has schema_version)" "$out" "schema_version"
assert_contains "--json has zero total" "$out" '"total": 0'

# --- Test: pass fixture --quiet ---
echo ""
echo "=== Pass fixture: --quiet output ==="
out=$(run_lint "$pass_skills" "$pass_scripts" "$pass_tests" --quiet) && rc=0 || rc=$?
assert_exit "--quiet exits 0 on clean" 0 "$rc"
assert_not_contains "--quiet produces no stdout" "$out" "violations"

# --- Test: fail-duplicate fixture ---
echo ""
echo "=== Fail-duplicate fixture ==="

dup_skills="$FIXTURES/fail-duplicate/skills"
dup_scripts="$FIXTURES/fail-duplicate/scripts"
dup_tests="$FIXTURES/fail-duplicate/tests"

out=$(run_lint "$dup_skills" "$dup_scripts" "$dup_tests" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "duplicate skill exits 1" 1 "$rc"
assert_contains "duplicate reported as DUPLICATE_SKILL" "$out" "DUPLICATE_SKILL"

# --- Test: fail-orphan fixture ---
echo ""
echo "=== Fail-orphan fixture ==="

orphan_skills="$FIXTURES/fail-orphan/skills"
orphan_scripts="$FIXTURES/fail-orphan/scripts"
orphan_tests="$FIXTURES/fail-orphan/tests"

out=$(run_lint "$orphan_skills" "$orphan_scripts" "$orphan_tests" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "orphan file exits 1" 1 "$rc"
assert_contains "orphan reported as ORPHAN_FILE" "$out" "ORPHAN_FILE"
assert_contains "orphan references stray.txt" "$out" "stray.txt"

# --- Test: fail-integrity fixture ---
echo ""
echo "=== Fail-integrity fixture ==="

integ_skills="$FIXTURES/fail-integrity/skills"
integ_scripts="$FIXTURES/fail-integrity/scripts"
integ_tests="$FIXTURES/fail-integrity/tests"

out=$(run_lint "$integ_skills" "$integ_scripts" "$integ_tests" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "integrity violations exit 1" 1 "$rc"
assert_contains "missing SKILL.md detected" "$out" "MISSING_SKILL_MD"
assert_contains "entrypoint not found detected" "$out" "ENTRYPOINT_NOT_FOUND"
assert_contains "material not found detected" "$out" "MATERIAL_PATH_NOT_FOUND"
assert_contains "parent traversal detected" "$out" "PARENT_TRAVERSAL"

# --- Test: fail-structure fixture ---
echo ""
echo "=== Fail-structure fixture ==="

struct_skills="$FIXTURES/fail-structure/skills"
struct_scripts="$FIXTURES/fail-structure/scripts"
struct_tests="$FIXTURES/fail-structure/tests"

out=$(run_lint "$struct_skills" "$struct_scripts" "$struct_tests" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "structure violation exits 1" 1 "$rc"
assert_contains "structure violation detected" "$out" "STRUCTURE_VIOLATION"

# --- Test: fail fixture --json output ---
echo ""
echo "=== Fail fixture: --json output ==="
out=$(run_lint "$dup_skills" "$dup_scripts" "$dup_tests" --json) && rc=0 || rc=$?
assert_exit "--json exits 1 on violations" 1 "$rc"
assert_contains "--json is valid JSON" "$out" "schema_version"
assert_contains "--json contains violation code" "$out" "DUPLICATE_SKILL"
assert_contains "--json has summary" "$out" '"by_code"'

# --- Test: --quiet on violations ---
echo ""
echo "=== Quiet mode on violations ==="
out=$(run_lint "$dup_skills" "$dup_scripts" "$dup_tests" --quiet) && rc=0 || rc=$?
assert_exit "--quiet exits 1 on violations" 1 "$rc"
assert_not_contains "--quiet produces no stdout" "$out" "DUPLICATE"

# --- Test: no interactive constructs ---
echo ""
echo "=== Static: no interactive constructs ==="
if grep -q '\bread -[a-zA-Z]*p\b' "$LINT_SCRIPT" 2>/dev/null; then
  echo "  FAIL: lint.sh contains forbidden 'read -p'"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: lint.sh has no 'read -p'"
  PASS=$((PASS + 1))
fi
if grep -q '/dev/tty' "$LINT_SCRIPT" 2>/dev/null; then
  echo "  FAIL: lint.sh references /dev/tty"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: lint.sh has no /dev/tty"
  PASS=$((PASS + 1))
fi
if head -1 "$LINT_SCRIPT" | grep -q '#!/usr/bin/env bash' && \
   grep -q 'set -euo pipefail' "$LINT_SCRIPT"; then
  echo "  PASS: lint.sh has strict mode preamble"
  PASS=$((PASS + 1))
else
  echo "  FAIL: lint.sh missing strict mode preamble"
  FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
