#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SEARCH_SCRIPT="$REPO_ROOT/scripts/catalog/search.sh"
FIXTURES="$REPO_ROOT/tests/catalog/fixtures"
CATALOG="$FIXTURES/expected-catalog.json"

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

run_search() {
  set +e
  local out
  out=$(bash "$SEARCH_SCRIPT" "$@" 2>&1)
  local rc=$?
  set -e
  printf '%s\n' "$out"
  return $rc
}

echo "=== Match by skill name ==="
out=$(run_search --from "$CATALOG" code-review)
rc=$?
assert_exit "name match exits 0" 0 "$rc"
assert_contains "finds code-review by name" "$out" "example/code-review"
assert_not_contains "excludes non-matching skills" "$out" "example/git-helpers"

echo ""
echo "=== Match by description ==="
out=$(run_search --from "$CATALOG" "branching")
rc=$?
assert_exit "description match exits 0" 0 "$rc"
assert_contains "finds git-helpers by description" "$out" "example/git-helpers"
assert_not_contains "excludes code-review" "$out" "example/code-review"

echo ""
echo "=== Match by tag ==="
out=$(run_search --from "$CATALOG" git)
rc=$?
assert_exit "tag match exits 0" 0 "$rc"
assert_contains "finds git-helpers by tag" "$out" "example/git-helpers"
assert_not_contains "excludes code-review" "$out" "example/code-review"

echo ""
echo "=== Match by category ==="
out=$(run_search --from "$CATALOG" maintenance)
rc=$?
assert_exit "category match exits 0" 0 "$rc"
assert_contains "finds code-review by category" "$out" "example/code-review"
assert_not_contains "excludes git-helpers" "$out" "example/git-helpers"

echo ""
echo "=== Case-insensitive match ==="
out=$(run_search --from "$CATALOG" "SECURITY")
rc=$?
assert_exit "uppercase search exits 0" 0 "$rc"
assert_contains "finds code-review by uppercase tag" "$out" "example/code-review"

echo ""
echo "=== Search with no matches: clean exit, no output ==="
out=$(run_search --from "$CATALOG" zzznonexistent)
rc=$?
assert_exit "no-match exits 0" 0 "$rc"
assert_eq "no-match produces no stdout" "" "$out"

echo ""
echo "=== JSON output ==="
out=$(run_search --from "$CATALOG" --json "review")
rc=$?
assert_exit "search --json exits 0" 0 "$rc"
if echo "$out" | jq -e . >/dev/null 2>&1; then
  echo "  PASS: --json output is valid JSON"
  PASS=$((PASS + 1))
else
  echo "  FAIL: --json output is not valid JSON"
  FAIL=$((FAIL + 1))
fi
count=$(echo "$out" | jq -r 'length')
assert_eq "one result for review" "1" "$count"
key=$(echo "$out" | jq -r '.[0].key')
assert_eq "result is code-review" "example/code-review" "$key"

echo ""
echo "=== Search by partial key match ==="
out=$(run_search --from "$CATALOG" "example/")
rc=$?
assert_exit "partial key match exits 0" 0 "$rc"
assert_contains "finds code-review by namespace" "$out" "example/code-review"
assert_contains "finds git-helpers by namespace" "$out" "example/git-helpers"

echo ""
echo "=== JSON empty result is empty array ==="
out=$(run_search --from "$CATALOG" --json "zzznonexistent")
rc=$?
assert_exit "empty JSON result exits 0" 0 "$rc"
empty=$(echo "$out" | jq -r '.')
assert_eq "empty result is []" "[]" "$empty"

echo ""
echo "=== Error: missing query ==="
out=$(run_search --from "$CATALOG" 2>&1) || rc=$?
assert_exit "missing query exits 2" 2 "$rc"

echo ""
echo "=== Error: catalog not found ==="
out=$(run_search --from /nonexistent searchterm 2>&1) || rc=$?
assert_exit "nonexistent catalog exits 5" 5 "$rc"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
