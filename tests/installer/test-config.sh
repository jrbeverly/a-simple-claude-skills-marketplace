#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_MODULE="$REPO_ROOT/scripts/installer/config.sh"

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

# Source the config module (this also calls config_reset)
source "$CONFIG_MODULE"

echo "=== Default values ==="
config_reset
config_resolve
assert_eq "INSTALL_TARGET defaults to ~/.claude/skills" \
  "$HOME/.claude/skills" "$INSTALL_TARGET"
assert_eq "MARKETPLACE_URL defaults to empty" \
  "" "$MARKETPLACE_URL"
assert_eq "CACHE_DIR defaults to ~/.cache/claude-skills" \
  "${XDG_CACHE_HOME:-$HOME/.cache}/claude-skills" "$CACHE_DIR"
assert_eq "CONFIG_FILE defaults to ~/.config/claude-skills/config" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/claude-skills/config" "$CONFIG_FILE"

echo ""
echo "=== Config file overrides defaults ==="
config_reset
tmp_config=$(mktemp)
cat > "$tmp_config" <<'EOF'
INSTALL_TARGET=/tmp/skills
MARKETPLACE_URL=https://example.com/catalog.json
CACHE_DIR=/tmp/cache
EOF
config_load_file "$tmp_config"
assert_eq "INSTALL_TARGET from file" "/tmp/skills" "$INSTALL_TARGET"
assert_eq "MARKETPLACE_URL from file" "https://example.com/catalog.json" "$MARKETPLACE_URL"
assert_eq "CACHE_DIR from file" "/tmp/cache" "$CACHE_DIR"
rm -f "$tmp_config"

echo ""
echo "=== Partial config file keeps defaults for unset keys ==="
config_reset
tmp_config=$(mktemp)
echo "INSTALL_TARGET=/custom/path" > "$tmp_config"
config_load_file "$tmp_config"
config_resolve
assert_eq "INSTALL_TARGET set from partial file" "/custom/path" "$INSTALL_TARGET"
assert_eq "CACHE_DIR keeps default" "${XDG_CACHE_HOME:-$HOME/.cache}/claude-skills" "$CACHE_DIR"
assert_eq "MARKETPLACE_URL keeps default" "" "$MARKETPLACE_URL"
rm -f "$tmp_config"

echo ""
echo "=== Env vars override config file ==="
config_reset
tmp_config=$(mktemp)
echo "INSTALL_TARGET=/from/file" > "$tmp_config"
config_load_file "$tmp_config"
assert_eq "INSTALL_TARGET set from file before env" "/from/file" "$INSTALL_TARGET"
export CLAUDE_SKILLS_INSTALL_TARGET=/from/env
config_apply_env
assert_eq "env overrides file for INSTALL_TARGET" "/from/env" "$INSTALL_TARGET"
rm -f "$tmp_config"
unset CLAUDE_SKILLS_INSTALL_TARGET

echo ""
echo "=== CLI overrides env vars ==="
config_reset
export CLAUDE_SKILLS_INSTALL_TARGET=/from/env
config_apply_env
assert_eq "env applied" "/from/env" "$INSTALL_TARGET"
config_set INSTALL_TARGET /from/cli
assert_eq "CLI overrides env for INSTALL_TARGET" "/from/cli" "$INSTALL_TARGET"
unset CLAUDE_SKILLS_INSTALL_TARGET

echo ""
echo "=== Full precedence chain: file < env < CLI ==="
config_reset
tmp_config=$(mktemp)
cat > "$tmp_config" <<'EOF'
INSTALL_TARGET=/from/file
CACHE_DIR=/cache/from/file
EOF
config_load_file "$tmp_config"
assert_eq "file loaded for INSTALL_TARGET" "/from/file" "$INSTALL_TARGET"
assert_eq "file loaded for CACHE_DIR" "/cache/from/file" "$CACHE_DIR"
export CLAUDE_SKILLS_INSTALL_TARGET=/from/env
config_apply_env
assert_eq "env overrides file for INSTALL_TARGET" "/from/env" "$INSTALL_TARGET"
assert_eq "CACHE_DIR still from file (no env var set)" "/cache/from/file" "$CACHE_DIR"
config_set INSTALL_TARGET /from/cli
config_set CACHE_DIR /cache/from/cli
assert_eq "CLI overrides env for INSTALL_TARGET" "/from/cli" "$INSTALL_TARGET"
assert_eq "CLI overrides file for CACHE_DIR" "/cache/from/cli" "$CACHE_DIR"
rm -f "$tmp_config"
unset CLAUDE_SKILLS_INSTALL_TARGET

echo ""
echo "=== config_resolve expands tildes ==="
config_reset
INSTALL_TARGET="~/test-skills"
CACHE_DIR="~/test-cache"
config_resolve
assert_eq "tilde expanded in INSTALL_TARGET" "$HOME/test-skills" "$INSTALL_TARGET"
assert_eq "tilde expanded in CACHE_DIR" "$HOME/test-cache" "$CACHE_DIR"

echo ""
echo "=== CONFIG_FILE overridable from env ==="
config_reset
export CLAUDE_SKILLS_CONFIG_FILE=/custom/config/path
config_apply_env
config_resolve
assert_eq "CONFIG_FILE from env" "/custom/config/path" "$CONFIG_FILE"
unset CLAUDE_SKILLS_CONFIG_FILE

echo ""
echo "=== Comments and blank lines in config file ==="
config_reset
tmp_config=$(mktemp)
cat > "$tmp_config" <<'EOF'
# This is a comment
INSTALL_TARGET=/from/file

# Another comment
CACHE_DIR=/tmp/cache

EOF
config_load_file "$tmp_config"
assert_eq "skips comments, reads INSTALL_TARGET" "/from/file" "$INSTALL_TARGET"
assert_eq "skips comments, reads CACHE_DIR" "/tmp/cache" "$CACHE_DIR"
config_resolve
assert_eq "CONFIG_FILE unchanged after resolve" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/claude-skills/config" "$CONFIG_FILE"
rm -f "$tmp_config"

echo ""
echo "=== config_print emits KEY=VALUE lines ==="
config_reset
config_set INSTALL_TARGET /print/test
config_resolve
output=$(config_print)
expected_line="INSTALL_TARGET=/print/test"
if echo "$output" | grep -qFx "$expected_line"; then
  echo "  PASS: config_print includes $expected_line"
  PASS=$((PASS + 1))
else
  echo "  FAIL: config_print missing $expected_line"
  echo "    output:"
  echo "$output"
  FAIL=$((FAIL + 1))
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
else
  echo "$FAIL test(s) failed, $PASS passed."
  exit 1
fi
