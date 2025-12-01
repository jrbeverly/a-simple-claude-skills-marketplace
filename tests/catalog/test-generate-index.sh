#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GENERATOR="$REPO_ROOT/scripts/catalog/generate-index.sh"
FIXTURES="$REPO_ROOT/tests/catalog/fixtures"
EXPECTED="$FIXTURES/expected-catalog.json"
PASS=0
FAIL=0

assert_match() {
  local label="$1" expected="$2" actual="$3"
  if diff "$expected" "$actual" >/dev/null 2>&1; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "  Expected:"
    cat "$expected"
    echo "  Got:"
    cat "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_eq() {
  local label="$1" expected="$2" actual="$3"
  if diff <(jq -S . "$expected") <(jq -S . "$actual") >/dev/null 2>&1; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "  Expected:"
    cat "$expected"
    echo "  Got:"
    cat "$actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Snapshot: fixture output matches expected ==="
tmp_out=$(mktemp -d)
SKILLS_DIR="$FIXTURES/skills" INDEX_DIR="$tmp_out" bash "$GENERATOR" >/dev/null
assert_match "fixture output matches expected catalog" "$EXPECTED" "$tmp_out/catalog.json"
rm -rf "$tmp_out"

echo ""
echo "=== Idempotency: two runs produce byte-identical output ==="
run1=$(mktemp -d)
run2=$(mktemp -d)
SKILLS_DIR="$FIXTURES/skills" INDEX_DIR="$run1" bash "$GENERATOR" >/dev/null
SKILLS_DIR="$FIXTURES/skills" INDEX_DIR="$run2" bash "$GENERATOR" >/dev/null
assert_match "two runs produce identical output" "$run1/catalog.json" "$run2/catalog.json"
rm -rf "$run1" "$run2"

echo ""
echo "=== Empty skills directory ==="
empty_skills=$(mktemp -d)
empty_out=$(mktemp -d)
SKILLS_DIR="$empty_skills" INDEX_DIR="$empty_out" bash "$GENERATOR" >/dev/null
empty_expected=$(mktemp)
echo '{"schema_version":"1.0.0","entries":{}}' > "$empty_expected"
assert_json_eq "empty skills/ produces valid empty catalog" "$empty_expected" "$empty_out/catalog.json"
rm -rf "$empty_skills" "$empty_out" "$empty_expected"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
