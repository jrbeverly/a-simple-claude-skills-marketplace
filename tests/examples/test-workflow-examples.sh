#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_SCRIPT="$REPO_ROOT/scripts/installer/install.sh"
POSTCREATE_SCRIPT="$REPO_ROOT/examples/postcreate.sh"
UPGRADE_ALL_SCRIPT="$REPO_ROOT/examples/upgrade-all.sh"
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

# ── Recipe 1: One-liner install ──────────────────────────────────

echo "=== Recipe 1: One-liner install ==="

target=$(mktemp -d)
trap 'rm -rf "$target"' EXIT

out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
      run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "one-liner install exits 0" 0 "$rc"
assert_file "skill.yaml present after one-liner install" "$target/example/hello-world/skill.yaml"
assert_file "entrypoint present after one-liner install" "$target/example/hello-world/run.sh"
assert_file "material present after one-liner install" "$target/example/hello-world/prompts/greet.md"
assert_contains "installed message" "$out" "Installed"

echo ""
echo "--- One-liner: idempotent re-run ---"
manifest_ts=$(stat -c %Y "$target/example/hello-world/skill.yaml")
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
      run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "re-install exits 0" 0 "$rc"
assert_contains "already installed message" "$out" "already installed"
new_manifest_ts=$(stat -c %Y "$target/example/hello-world/skill.yaml")
assert_eq "manifest not modified on re-install" "$manifest_ts" "$new_manifest_ts"
assert_not_contains "no [Y/n] prompt on re-run" "$out" "[Y/n]"

echo ""
echo "--- One-liner: with version pin ---"
target2=$(mktemp -d)
trap 'rm -rf "$target2"' EXIT
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target2" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$target2/.cache" \
      run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world@1.0.0") && rc=0 || rc=$?
echo "$out"
assert_exit "version-pinned install exits 0" 0 "$rc"
assert_file "skill installed at pinned version" "$target2/example/hello-world/skill.yaml"
installed_ver=$(yq -r '.version' "$target2/example/hello-world/skill.yaml")
assert_eq "installed version is 1.0.0" "1.0.0" "$installed_ver"
rm -rf "$target2"

echo ""
echo "--- One-liner: invalid skill ref ---"
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      run_no_tty 10 "$INSTALL_SCRIPT" "badformat") && rc=0 || rc=$?
assert_exit "invalid ref exits 2" 2 "$rc"

rm -rf "$target"

# ── Recipe 2: CI snippet ─────────────────────────────────────────

echo ""
echo "=== Recipe 2: CI snippet ==="

ci_target=$(mktemp -d)
trap 'rm -rf "$ci_target"' EXIT

echo "--- CI: install with CLAUDE_SKILLS_INSTALL_TARGET ---"
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$ci_target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$ci_target/.cache" \
      run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "CI-style install exits 0" 0 "$rc"
assert_file "CI install creates skill.yaml" "$ci_target/example/hello-world/skill.yaml"
assert_not_contains "no prompts in CI output" "$out" "[Y/n]"

installed_version=$(yq -r '.version' "$ci_target/example/hello-world/skill.yaml")
assert_eq "CI verify: correct version" "1.0.0" "$installed_version"

echo ""
echo "--- CI: re-run is safe (idempotent) ---"
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$ci_target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$ci_target/.cache" \
      run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "CI re-run exits 0" 0 "$rc"
assert_contains "CI re-run says already installed" "$out" "already installed"

echo ""
echo "--- CI: inspect installed skill ---"
out=$(cat "$ci_target/example/hello-world/skill.yaml")
assert_contains "CI inspect: manifest has name" "$out" "hello-world"
assert_contains "CI inspect: manifest has entrypoint" "$out" "run.sh"

rm -rf "$ci_target"

# ── Recipe 3: Devcontainer postCreate ────────────────────────────

echo ""
echo "=== Recipe 3: Devcontainer postCreate ==="

dc_target=$(mktemp -d)
trap 'rm -rf "$dc_target"' EXIT

echo "--- postcreate: install multiple skills ---"
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$dc_target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$dc_target/.cache" \
      run_no_tty 15 "$POSTCREATE_SCRIPT" "$MARKETPLACE") && rc=0 || rc=$?
echo "$out"
# code-review is listed but not in fixture, so postcreate exits 1 after
# installing hello-world and failing on code-review.
assert_exit "postcreate exits 1 (code-review missing from fixture)" 1 "$rc"
assert_file "postcreate: hello-world installed" "$dc_target/example/hello-world/skill.yaml"
assert_contains "postcreate: installed hello-world" "$out" "Installed"
assert_contains "postcreate: reports code-review failure" "$out" "failed to install"
assert_not_contains "postcreate: no prompts" "$out" "[Y/n]"

echo ""
echo "--- postcreate: re-run is safe (idempotent) ---"
# Re-run with a fixture that has only the skills that exist.
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$dc_target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$dc_target/.cache" \
      run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "postcreate re-run exits 0" 0 "$rc"
assert_contains "postcreate re-run says already installed" "$out" "already installed"

# Test the inline devcontainer pattern
echo ""
echo "--- Devcontainer inline: direct install commands ---"
dc2_target=$(mktemp -d)
trap 'rm -rf "$dc2_target"' EXIT
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$dc2_target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$dc2_target/.cache" \
      run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world") && rc=0 || rc=$?
echo "$out"
assert_exit "inline devcontainer install exits 0" 0 "$rc"
assert_file "inline devcontainer: skill.yaml present" "$dc2_target/example/hello-world/skill.yaml"
rm -rf "$dc2_target"

rm -rf "$dc_target"

# ── Recipe 4: Upgrade all installed skills ────────────────────────

echo ""
echo "=== Recipe 4: Upgrade all installed skills ==="

up_target=$(mktemp -d)
trap 'rm -rf "$up_target"' EXIT

# Install hello-world at version 1.0.0 from the base fixture
CLAUDE_SKILLS_INSTALL_TARGET="$up_target" \
  CLAUDE_SKILLS_MARKETPLACE_URL="" \
  CLAUDE_SKILLS_CACHE_DIR="$up_target/.cache" \
  bash "$INSTALL_SCRIPT" --from "$MARKETPLACE" "example/hello-world" < /dev/null > /dev/null 2>&1

installed_ver=$(yq -r '.version' "$up_target/example/hello-world/skill.yaml")
assert_eq "upgrade: initial version is 1.0.0" "1.0.0" "$installed_ver"

# Create an updated fixture with version 2.0.0
up_fixture=$(mktemp -d)
trap 'rm -rf "$up_fixture"' EXIT

mkdir -p "$up_fixture/index"
mkdir -p "$up_fixture/skills/example/hello-world/prompts"

cat > "$up_fixture/index/catalog.json" <<'EOF'
{
  "schema_version": "1.0.0",
  "entries": {
    "example/hello-world": {
      "version": "2.0.0",
      "description": "A simple hello world skill for testing the installer (updated).",
      "tags": ["hello", "test"],
      "categories": ["development"],
      "path": "skills/example/hello-world",
      "manifest_hash": "sha256:c2ab1b59cdd744c50691d1bd5f66f2a585d3e79d94bac60f57c3a9cb5ea38045"
    }
  }
}
EOF

cat > "$up_fixture/skills/example/hello-world/skill.yaml" <<'EOF'
name: hello-world
version: 2.0.0
description: A simple hello world skill for testing the installer (updated).
entrypoint: run.sh

materials:
  - path: prompts/greet.md
    type: prompt
    description: A greeting prompt template

tags:
  - test
  - hello

categories:
  - development
EOF

echo "#!/usr/bin/env bash" > "$up_fixture/skills/example/hello-world/run.sh"
echo 'echo "Hello, world! v2"' >> "$up_fixture/skills/example/hello-world/run.sh"
chmod +x "$up_fixture/skills/example/hello-world/run.sh"
echo "# Greeting prompt v2" > "$up_fixture/skills/example/hello-world/prompts/greet.md"

echo "--- upgrade-all: upgrade from v1 to v2 ---"
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$up_target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$up_target/.cache" \
      run_no_tty 15 "$UPGRADE_ALL_SCRIPT" --from "$up_fixture") && rc=0 || rc=$?
echo "$out"
assert_exit "upgrade-all exits 0" 0 "$rc"
assert_contains "upgrade-all: performed upgrade" "$out" "1 upgraded"
assert_contains "upgrade-all: installed message" "$out" "Installed"

upgraded_ver=$(yq -r '.version' "$up_target/example/hello-world/skill.yaml")
assert_eq "upgrade-all: version is now 2.0.0" "2.0.0" "$upgraded_ver"

echo ""
echo "--- upgrade-all: re-run is safe (idempotent, already latest) ---"
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$up_target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      CLAUDE_SKILLS_CACHE_DIR="$up_target/.cache" \
      run_no_tty 15 "$UPGRADE_ALL_SCRIPT" --from "$up_fixture") && rc=0 || rc=$?
echo "$out"
assert_exit "upgrade-all re-run exits 0" 0 "$rc"
assert_contains "upgrade-all re-run: already installed" "$out" "already installed"

echo ""
echo "--- upgrade-all: no installed skills is a no-op ---"
empty_target=$(mktemp -d)
trap 'rm -rf "$empty_target"' EXIT
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$empty_target" \
      run_no_tty 10 "$UPGRADE_ALL_SCRIPT" --from "$up_fixture") && rc=0 || rc=$?
echo "$out"
assert_exit "upgrade-all with no skills exits 0" 0 "$rc"
rm -rf "$empty_target"

echo ""
echo "--- upgrade-all: non-interactive check ---"
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$up_target" \
      run_no_tty 10 "$UPGRADE_ALL_SCRIPT" --from "$up_fixture") && rc=0 || rc=$?
assert_not_contains "upgrade-all has no prompts" "$out" "[Y/n]"

rm -rf "$up_target" "$up_fixture"

# ── Static checks on example scripts ──────────────────────────────

echo ""
echo "=== Static: example scripts use strict mode ==="

for script in "$POSTCREATE_SCRIPT" "$UPGRADE_ALL_SCRIPT"; do
  script_name=$(basename "$script")
  if head -1 "$script" | grep -q '#!/usr/bin/env bash' && \
     grep -q 'set -euo pipefail' "$script"; then
    echo "  PASS: $script_name has strict mode preamble"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $script_name missing strict mode preamble"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "=== Static: example scripts are non-interactive ==="

for script in "$POSTCREATE_SCRIPT" "$UPGRADE_ALL_SCRIPT"; do
  script_name=$(basename "$script")
  if grep -q '\bread -[a-zA-Z]*p\b' "$script" 2>/dev/null; then
    echo "  FAIL: $script_name contains forbidden 'read -p'"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $script_name has no 'read -p'"
    PASS=$((PASS + 1))
  fi
  if grep -q '/dev/tty' "$script" 2>/dev/null; then
    echo "  FAIL: $script_name references /dev/tty"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $script_name has no /dev/tty"
    PASS=$((PASS + 1))
  fi
done

# ── Summary ──────────────────────────────────────────────────────

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
