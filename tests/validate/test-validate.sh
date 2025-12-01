#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATE_SCRIPT="$REPO_ROOT/scripts/validate/validate.sh"
FIXTURES="$REPO_ROOT/tests/validate/fixtures"
PASS=0
FAIL=0

export PATH="$REPO_ROOT/.local/bin:$PATH"

run_validate() {
  local skills_dir="$1"
  shift
  set +e
  local out
  out=$(SKILLS_DIR="$skills_dir" bash "$VALIDATE_SCRIPT" "$@" 2>&1)
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

# --- Test: pass fixture ---
echo "=== Pass fixture: valid skill ==="

pass_skills="$FIXTURES/pass/skills"
out=$(run_validate "$pass_skills") && rc=0 || rc=$?
echo "$out"
assert_exit "valid skill exits 0" 0 "$rc"
assert_contains "valid skill reports all good" "$out" "All manifests valid"

# --- Test: pass fixture --json ---
echo ""
echo "=== Pass fixture: --json output ==="
out=$(run_validate "$pass_skills" --json) && rc=0 || rc=$?
assert_exit "--json exits 0 on valid" 0 "$rc"
assert_contains "--json has schema_version" "$out" "schema_version"
assert_contains "--json has zero total" "$out" '"total": 0'

# --- Test: pass fixture --quiet ---
echo ""
echo "=== Pass fixture: --quiet output ==="
out=$(run_validate "$pass_skills" --quiet) && rc=0 || rc=$?
assert_exit "--quiet exits 0 on valid" 0 "$rc"
assert_not_contains "--quiet produces no output" "$out" "violations"

# --- Test: missing required field ---
echo ""
echo "=== Fail: missing required field ==="
ffv_skills="$FIXTURES/fail-field-validation/skills"
out=$(run_validate "$ffv_skills" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "missing required exits 4" 4 "$rc"
assert_contains "MISSING_REQUIRED_FIELD reported" "$out" "MISSING_REQUIRED_FIELD"
assert_contains "missing description detected" "$out" "description"

# --- Test: invalid name format ---
assert_contains "INVALID_NAME_FORMAT reported" "$out" "INVALID_NAME_FORMAT"

# --- Test: invalid SemVer ---
assert_contains "INVALID_SEMVER reported" "$out" "INVALID_SEMVER"

# --- Test: invalid category ---
assert_contains "INVALID_CATEGORY reported" "$out" "INVALID_CATEGORY"

# --- Test: invalid tag ---
assert_contains "INVALID_TAG_FORMAT reported" "$out" "INVALID_TAG_FORMAT"

# --- Test: invalid material type ---
assert_contains "INVALID_MATERIAL_TYPE reported" "$out" "INVALID_MATERIAL_TYPE"

# --- Test: empty materials ---
assert_contains "EMPTY_MATERIALS reported" "$out" "EMPTY_MATERIALS"

# --- Test: too long name ---
assert_contains "FIELD_TOO_LONG for name" "$out" "FIELD_TOO_LONG"

# --- Test: too many tags ---
assert_contains "TOO_MANY_ITEMS for tags" "$out" "TOO_MANY_ITEMS"

# --- Test: fail-path-validation fixture ---
echo ""
echo "=== Fail-path-validation fixture ==="

fpv_skills="$FIXTURES/fail-path-validation/skills"
out=$(run_validate "$fpv_skills" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "path validation exits 4" 4 "$rc"
assert_contains "PATH_NOT_FOUND for entrypoint" "$out" "PATH_NOT_FOUND"
assert_contains "PARENT_TRAVERSAL reported" "$out" "PARENT_TRAVERSAL"

# --- Test: single skill via positional argument ---
echo ""
echo "=== Single skill via positional arg ==="
out=$(run_validate "" "$FIXTURES/pass/skills/example/hello-world" 2>&1) && rc=0 || rc=$?
assert_exit "single skill exits 0" 0 "$rc"

# --- Test: fail fixture --json output ---
echo ""
echo "=== Fail fixture: --json output ==="
out=$(run_validate "$ffv_skills" --json) && rc=0 || rc=$?
assert_exit "--json exits 4 on violations" 4 "$rc"
assert_contains "--json is valid JSON" "$out" "schema_version"
assert_contains "--json has violation code" "$out" "MISSING_REQUIRED_FIELD"
assert_contains "--json has summary" "$out" '"by_code"'

# --- Test: --quiet on violations ---
echo ""
echo "=== Quiet mode on violations ==="
out=$(run_validate "$ffv_skills" --quiet) && rc=0 || rc=$?
assert_exit "--quiet exits 4 on violations" 4 "$rc"
assert_not_contains "--quiet produces no violation output" "$out" "MISSING_REQUIRED"

# --- Test: validate on all real skills ---
echo ""
echo "=== Real skills pass ==="
out=$(run_validate "$REPO_ROOT/skills" 2>&1) && rc=0 || rc=$?
assert_exit "all real skills exit 0" 0 "$rc"
assert_contains "all real skills valid" "$out" "All manifests valid"

# --- Test: no interactive constructs ---
echo ""
echo "=== Static: no interactive constructs ==="
if grep -q '\bread -[a-zA-Z]*p\b' "$VALIDATE_SCRIPT" 2>/dev/null; then
  echo "  FAIL: validate.sh contains forbidden 'read -p'"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: validate.sh has no 'read -p'"
  PASS=$((PASS + 1))
fi
if grep -q '/dev/tty' "$VALIDATE_SCRIPT" 2>/dev/null; then
  echo "  FAIL: validate.sh references /dev/tty"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: validate.sh has no /dev/tty"
  PASS=$((PASS + 1))
fi
if head -1 "$VALIDATE_SCRIPT" | grep -q '#!/usr/bin/env bash' && \
   grep -q 'set -euo pipefail' "$VALIDATE_SCRIPT"; then
  echo "  PASS: validate.sh has strict mode preamble"
  PASS=$((PASS + 1))
else
  echo "  FAIL: validate.sh missing strict mode preamble"
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
