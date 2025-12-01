#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_SCRIPT="$REPO_ROOT/scripts/installer/install.sh"
FIXTURES="$REPO_ROOT/tests/installer/fixtures"
MARKETPLACE="$FIXTURES/marketplace"

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

run_install() {
  # Run install.sh in a subshell with clean config state.
  # Return exit code via stdout (last line) to avoid masking by set -e.
  local target="$1" source="$2" ref="$3"
  shift 3
  local out
  set +e
  out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
        CLAUDE_SKILLS_MARKETPLACE_URL="" \
        CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
        bash "$INSTALL_SCRIPT" --from "$source" "$ref" "$@" 2>&1)
  local rc=$?
  set -e
  printf '%s\n' "$out"
  return $rc
}

echo "=== Happy path: install from local source ==="
target=$(mktemp -d)
trap "rm -rf $target" EXIT

if out=$(run_install "$target" "$MARKETPLACE" "example/hello-world" 2>&1); then
  rc=0
else
  rc=$?
fi
echo "$out"
assert_exit "install exits 0" 0 "$rc"
assert_file "skill.yaml present" "$target/example/hello-world/skill.yaml"
assert_file "entrypoint present" "$target/example/hello-world/run.sh"
assert_file "material present" "$target/example/hello-world/prompts/greet.md"

# Verify content matches
installed_ver=$(yq -r '.version' "$target/example/hello-world/skill.yaml")
assert_eq "installed version is 1.0.0" "1.0.0" "$installed_ver"

echo ""
echo "=== No-op: re-install same version ==="
# Capture timestamp before re-install to verify no filesystem change
manifest_ts=$(stat -c %Y "$target/example/hello-world/skill.yaml")

if out=$(run_install "$target" "$MARKETPLACE" "example/hello-world" 2>&1); then
  rc=0
else
  rc=$?
fi
echo "$out"
assert_exit "re-install exits 0" 0 "$rc"
new_manifest_ts=$(stat -c %Y "$target/example/hello-world/skill.yaml")
assert_eq "manifest not modified (same mtime)" "$manifest_ts" "$new_manifest_ts"

echo ""
echo "=== No-op with explicit version ==="
if out=$(run_install "$target" "$MARKETPLACE" "example/hello-world@1.0.0" 2>&1); then
  rc=0
else
  rc=$?
fi
echo "$out"
assert_exit "explicit version re-install exits 0" 0 "$rc"

echo ""
echo "=== Failure: skill not found in catalog ==="
if out=$(run_install "$target" "$MARKETPLACE" "example/nonexistent" 2>&1); then
  rc=0
else
  rc=$?
fi
echo "$out"
assert_exit "nonexistent skill exits 4" 4 "$rc"

echo ""
echo "=== Failure: invalid skill reference ==="
if out=$(run_install "$target" "$MARKETPLACE" "badformat" 2>&1); then
  rc=0
else
  rc=$?
fi
echo "$out"
assert_exit "invalid ref exits 2" 2 "$rc"

echo ""
echo "=== Failure: no source specified ==="
if out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
          CLAUDE_SKILLS_MARKETPLACE_URL="" \
          bash "$INSTALL_SCRIPT" "example/hello-world" 2>&1); then
  rc=0
else
  rc=$?
fi
echo "$out"
assert_exit "no source exits 2" 2 "$rc"

echo ""
echo "=== Failure: unknown version ==="
if out=$(run_install "$target" "$MARKETPLACE" "example/hello-world@9.9.9" 2>&1); then
  rc=0
else
  rc=$?
fi
echo "$out"
assert_exit "unknown version exits 4" 4 "$rc"

echo ""
echo "=== --json output mode ==="
target2=$(mktemp -d)
trap "rm -rf $target2" EXIT

set +e
json_out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target2" \
           CLAUDE_SKILLS_MARKETPLACE_URL="" \
           CLAUDE_SKILLS_CACHE_DIR="$target2/.cache" \
           bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" --json "example/hello-world" 2>/dev/null)
rc=$?
set -e
assert_exit "--json install exits 0" 0 "$rc"
echo "$json_out" | jq -e '.status == "installed"' >/dev/null 2>&1
jq_rc=$?
assert_eq "--json output is valid JSON with status=installed" "0" "$jq_rc"

rm -rf "$target2"

echo ""
echo "=== --quiet mode produces no stdout ==="
target3=$(mktemp -d)
trap "rm -rf $target3" EXIT

set +e
quiet_out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target3" \
            CLAUDE_SKILLS_MARKETPLACE_URL="" \
            CLAUDE_SKILLS_CACHE_DIR="$target3/.cache" \
            bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" --quiet "example/hello-world" 2>/dev/null)
rc=$?
set -e
assert_exit "--quiet install exits 0" 0 "$rc"
assert_eq "--quiet produces empty stdout" "" "$quiet_out"
assert_file "files still installed in quiet mode" "$target3/example/hello-world/skill.yaml"

rm -rf "$target3"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
