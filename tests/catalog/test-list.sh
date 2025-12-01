#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIST_SCRIPT="$REPO_ROOT/scripts/catalog/list.sh"
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

run_list() {
  set +e
  local out
  out=$(bash "$LIST_SCRIPT" "$@" 2>&1)
  local rc=$?
  set -e
  printf '%s\n' "$out"
  return $rc
}

echo "=== Table output: all skills listed ==="
out=$(run_list --from "$CATALOG")
rc=$?
assert_exit "list exits 0" 0 "$rc"
assert_contains "contains code-review" "$out" "example/code-review"
assert_contains "contains git-helpers" "$out" "example/git-helpers"
assert_contains "contains code-review version" "$out" "1.2.0"
assert_contains "contains git-helpers version" "$out" "1.0.0"
assert_contains "has SKILL header" "$out" "SKILL"
assert_contains "has VERSION header" "$out" "VERSION"
assert_contains "has DESCRIPTION header" "$out" "DESCRIPTION"
# Verify sorted order: code-review before git-helpers
first=$(echo "$out" | grep -n "example/code-review" | head -1 | cut -d: -f1)
second=$(echo "$out" | grep -n "example/git-helpers" | head -1 | cut -d: -f1)
if [ "$first" -lt "$second" ]; then
  echo "  PASS: skills are sorted alphabetically"
  PASS=$((PASS + 1))
else
  echo "  FAIL: skills are not sorted alphabetically"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== JSON output: valid and contains expected keys ==="
out=$(run_list --from "$CATALOG" --json)
rc=$?
assert_exit "list --json exits 0" 0 "$rc"
# Validate JSON
if echo "$out" | jq -e . >/dev/null 2>&1; then
  echo "  PASS: --json output is valid JSON"
  PASS=$((PASS + 1))
else
  echo "  FAIL: --json output is not valid JSON"
  FAIL=$((FAIL + 1))
fi
count=$(echo "$out" | jq -r 'length')
assert_eq "two skills in JSON" "2" "$count"
first_key=$(echo "$out" | jq -r '.[0].key')
assert_eq "first entry is code-review" "example/code-review" "$first_key"
# Verify each entry has required fields
code_review=$(echo "$out" | jq -r '.[] | select(.key == "example/code-review")')
assert_contains "code-review has version" "$code_review" '"version": "1.2.0"'
assert_contains "code-review has description" "$code_review" '"description"'
assert_contains "code-review has tags" "$code_review" '"tags"'
assert_contains "code-review has categories" "$code_review" '"categories"'

echo ""
echo "=== Empty catalog: clean exit, no output ==="
empty_catalog=$(mktemp)
echo '{"schema_version":"1.0.0","entries":{}}' > "$empty_catalog"
out=$(run_list --from "$empty_catalog")
rc=$?
assert_exit "empty catalog exits 0" 0 "$rc"
assert_eq "empty catalog produces no stdout" "" "$out"
rm -f "$empty_catalog"

echo ""
echo "=== --from with marketplace root directory ==="
# Create a temporary marketplace root with index/catalog.json
marketplace=$(mktemp -d)
mkdir -p "$marketplace/index"
cp "$CATALOG" "$marketplace/index/catalog.json"
out=$(run_list --from "$marketplace")
rc=$?
assert_exit "list from marketplace root exits 0" 0 "$rc"
assert_contains "finds code-review from marketplace root" "$out" "example/code-review"
rm -rf "$marketplace"

echo ""
echo "=== Error: catalog not found ==="
out=$(run_list --from /nonexistent/path 2>&1) || rc=$?
assert_exit "nonexistent catalog exits 5" 5 "$rc"

echo ""
echo "=== Error: unknown flag ==="
out=$(run_list --badflag 2>&1) || rc=$?
assert_exit "unknown flag exits 2" 2 "$rc"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
