#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UPDATE_SCRIPT="$REPO_ROOT/scripts/updater/update.sh"
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

run_update() {
  local target="$1" source="$2"
  shift 2
  set +e
  local out
  out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
        CLAUDE_SKILLS_MARKETPLACE_URL="" \
        CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
        bash "$UPDATE_SCRIPT" --from "$source" "$@" 2>&1)
  local rc=$?
  set -e
  printf '%s\n' "$out"
  return $rc
}

# --- Setup: install v1.0.0 ---
target=$(mktemp -d)
trap 'rm -rf "$target"' EXIT

CLAUDE_SKILLS_INSTALL_TARGET="$target" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

installed_ver=$(yq -r '.version' "$target/example/hello-world/skill.yaml")
assert_eq "initial install version is 1.0.0" "1.0.0" "$installed_ver"

# --- Create v2.0.0 fixture ---
v2_fixture=$(mktemp -d)
trap 'rm -rf "$v2_fixture"' EXIT

mkdir -p "$v2_fixture/index"
mkdir -p "$v2_fixture/skills/example/hello-world/prompts"

cat > "$v2_fixture/index/catalog.json" <<'EOF'
{
  "schema_version": "1.0.0",
  "entries": {
    "example/hello-world": {
      "version": "2.0.0",
      "description": "A simple hello world skill for testing the updater (v2).",
      "tags": ["hello", "test"],
      "categories": ["development"],
      "path": "skills/example/hello-world",
      "manifest_hash": "sha256:c2ab1b59cdd744c50691d1bd5f66f2a585d3e79d94bac60f57c3a9cb5ea38045"
    }
  }
}
EOF

cat > "$v2_fixture/skills/example/hello-world/skill.yaml" <<'EOF'
name: hello-world
version: 2.0.0
description: A simple hello world skill for testing the updater (v2).
entrypoint: run.sh

materials:
  - path: prompts/greet.md
    type: prompt
    description: A greeting prompt template

tags:
  - hello
  - test

categories:
  - development
EOF

echo "#!/usr/bin/env bash" > "$v2_fixture/skills/example/hello-world/run.sh"
echo 'echo "Hello, world! v2"' >> "$v2_fixture/skills/example/hello-world/run.sh"
echo "# Greeting prompt v2" > "$v2_fixture/skills/example/hello-world/prompts/greet.md"

echo "=== Update with change: v1 → v2 ==="
out=$(run_update "$target" "$v2_fixture" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "update exits 0" 0 "$rc"
assert_contains "reports updated" "$out" "Updated"
updated_ver=$(yq -r '.version' "$target/example/hello-world/skill.yaml")
assert_eq "installed version is now 2.0.0" "2.0.0" "$updated_ver"
assert_file "entrypoint still present after update" "$target/example/hello-world/run.sh"
assert_file "material still present after update" "$target/example/hello-world/prompts/greet.md"

echo ""
echo "=== Update with no change: already current ==="
manifest_ts=$(stat -c %Y "$target/example/hello-world/skill.yaml")
out=$(run_update "$target" "$v2_fixture" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "update no-change exits 0" 0 "$rc"
assert_contains "reports already current" "$out" "already current"
new_manifest_ts=$(stat -c %Y "$target/example/hello-world/skill.yaml")
assert_eq "manifest not modified on no-change update" "$manifest_ts" "$new_manifest_ts"

echo ""
echo "=== Update with --force when already current ==="
out=$(run_update "$target" "$v2_fixture" --force "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "update --force exits 0" 0 "$rc"
assert_contains "reports updated with --force" "$out" "Updated"

echo ""
echo "=== Update non-installed skill ==="
out=$(run_update "$target" "$v2_fixture" "example/nonexistent") && rc=0 || rc=$?
echo "$out"
assert_exit "update non-installed exits 6 (CONFLICT)" 6 "$rc"
assert_contains "reports not installed" "$out" "not installed"

echo ""
echo "=== Update invalid skill reference ==="
out=$(run_update "$target" "$v2_fixture" "badformat") && rc=0 || rc=$?
echo "$out"
assert_exit "update invalid ref exits 2 (INVALID_USAGE)" 2 "$rc"

echo ""
echo "=== Update missing source ==="
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      bash "$UPDATE_SCRIPT" "example/hello-world" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "update missing source exits 2" 2 "$rc"

echo ""
echo "=== Update skill not in catalog ==="
# Create a fixture marketplace without the target skill
empty_catalog_fixture=$(mktemp -d)
trap 'rm -rf "$empty_catalog_fixture"' EXIT
mkdir -p "$empty_catalog_fixture/index"
echo '{"schema_version":"1.0.0","entries":{}}' > "$empty_catalog_fixture/index/catalog.json"
# First install a skill, then try to update it from a catalog that doesn't have it
target2=$(mktemp -d)
trap 'rm -rf "$target2"' EXIT
CLAUDE_SKILLS_INSTALL_TARGET="$target2" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$target2/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target2" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$target2/.cache" \
      bash "$UPDATE_SCRIPT" --from "$empty_catalog_fixture" "example/hello-world" 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "update skill not in catalog exits 4 (INPUT_INVALID)" 4 "$rc"
rm -rf "$target2" "$empty_catalog_fixture"

echo ""
echo "=== Update --json output ==="
# Reset to v1, then update to v2 with --json
target3=$(mktemp -d)
trap 'rm -rf "$target3"' EXIT
CLAUDE_SKILLS_INSTALL_TARGET="$target3" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$target3/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

set +e
json_out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target3" \
           CLAUDE_SKILLS_MARKETPLACE_URL="" \
           CLAUDE_SKILLS_CACHE_DIR="$target3/.cache" \
           bash "$UPDATE_SCRIPT" --from "$v2_fixture" --json "example/hello-world" 2>/dev/null)
rc=$?
set -e
assert_exit "--json update exits 0" 0 "$rc"
echo "$json_out" | jq -e '.status == "updated"' >/dev/null 2>&1
jq_rc=$?
assert_eq "--json output is valid JSON with status=updated" "0" "$jq_rc"
assert_contains "--json output has old_version" "$json_out" '"old_version": "1.0.0"'
assert_contains "--json output has new_version" "$json_out" '"new_version": "2.0.0"'
rm -rf "$target3"

echo ""
echo "=== Update --json already current ==="
target4=$(mktemp -d)
trap 'rm -rf "$target4"' EXIT
CLAUDE_SKILLS_INSTALL_TARGET="$target4" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$target4/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

set +e
json_out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target4" \
           CLAUDE_SKILLS_MARKETPLACE_URL="" \
           CLAUDE_SKILLS_CACHE_DIR="$target4/.cache" \
           bash "$UPDATE_SCRIPT" --from "$MARKETPLACE" --json "example/hello-world" 2>/dev/null)
rc=$?
set -e
assert_exit "--json already current exits 0" 0 "$rc"
echo "$json_out" | jq -e '.status == "already_current"' >/dev/null 2>&1
jq_rc=$?
assert_eq "--json already current has correct status" "0" "$jq_rc"
rm -rf "$target4"

echo ""
echo "=== Update --quiet mode produces no stdout ==="
target5=$(mktemp -d)
trap 'rm -rf "$target5"' EXIT
CLAUDE_SKILLS_INSTALL_TARGET="$target5" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$target5/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

set +e
quiet_out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target5" \
            CLAUDE_SKILLS_MARKETPLACE_URL="" \
            CLAUDE_SKILLS_CACHE_DIR="$target5/.cache" \
            bash "$UPDATE_SCRIPT" --from "$v2_fixture" --quiet "example/hello-world" 2>/dev/null)
rc=$?
set -e
assert_exit "--quiet update exits 0" 0 "$rc"
assert_eq "--quiet produces empty stdout" "" "$quiet_out"
updated_ver=$(yq -r '.version' "$target5/example/hello-world/skill.yaml")
assert_eq "--quiet still updated to 2.0.0" "2.0.0" "$updated_ver"
rm -rf "$target5"

echo ""
echo "=== Update --all ==="
target6=$(mktemp -d)
trap 'rm -rf "$target6"' EXIT

# Install hello-world v1 from the base fixture
CLAUDE_SKILLS_INSTALL_TARGET="$target6" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$target6/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target6" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$target6/.cache" \
      bash "$UPDATE_SCRIPT" --from "$v2_fixture" --all 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "--all exits 0" 0 "$rc"
assert_contains "--all reports updated" "$out" "Updated"
updated_ver=$(yq -r '.version' "$target6/example/hello-world/skill.yaml")
assert_eq "--all updated to 2.0.0" "2.0.0" "$updated_ver"

# Re-run --all: should report already current
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target6" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$target6/.cache" \
      bash "$UPDATE_SCRIPT" --from "$v2_fixture" --all 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "--all re-run exits 0" 0 "$rc"
assert_contains "--all re-run reports already current" "$out" "already current"
rm -rf "$target6"

echo ""
echo "=== Update --all with no installed skills ==="
target7=$(mktemp -d)
trap 'rm -rf "$target7"' EXIT
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target7" \
      bash "$UPDATE_SCRIPT" --from "$v2_fixture" --all 2>&1) && rc=0 || rc=$?
echo "$out"
assert_exit "--all empty exits 0" 0 "$rc"
rm -rf "$target7"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
