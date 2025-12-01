#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
CATALOG="$REPO_ROOT/tests/catalog/fixtures/expected-catalog.json"
INSTALL_SCRIPT="$REPO_ROOT/scripts/installer/install.sh"
LIST_SCRIPT="$REPO_ROOT/scripts/catalog/list.sh"
SEARCH_SCRIPT="$REPO_ROOT/scripts/catalog/search.sh"
GENERATOR="$REPO_ROOT/scripts/catalog/generate-index.sh"
MARKETPLACE_FIXTURE="$REPO_ROOT/tests/installer/fixtures/marketplace"

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

# Run a command with stdin from /dev/null and a timeout, capturing both
# stdout and stderr combined. Exit code is returned; callers must use
#   out=$(run_no_tty ...) && rc=0 || rc=$?
# to avoid set -e firing on expected non-zero exits.
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

# Run a command with --json and verify the stdout is valid parseable JSON.
# stderr is discarded so that only the primary output reaches jq.
assert_json_valid() {
  local label="$1" timeout_sec="$2"
  shift 2
  set +e
  local out
  out=$(timeout "$timeout_sec" bash "$@" < /dev/null 2>/dev/null)
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ] && echo "$out" | jq -e . >/dev/null 2>&1; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (rc=$rc, not valid JSON or timed out)"
    echo "    output: $out"
    FAIL=$((FAIL + 1))
  fi
}

# ── Static checks ────────────────────────────────────────────────

echo "=== Static: forbidden interactive constructs ==="

grep_forbidden() {
  local label="$1" pattern="$2"
  local matches
  matches=$(grep -rn "$pattern" "$SCRIPTS_DIR" --include="*.sh" 2>/dev/null || true)
  if [ -z "$matches" ]; then
    echo "  PASS: no '$label' in scripts/"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: forbidden '$label' found:"
    echo "$matches"
    FAIL=$((FAIL + 1))
  fi
}

grep_forbidden "read -p" '\bread -[a-zA-Z]*p\b'
grep_forbidden "/dev/tty" '/dev/tty'
grep_forbidden "terminal escape \\033" '\\033\['

# Detect bare `read` lines that do not also contain `while` (while-read
# loops with explicit redirection are safe).
bare_read=$(grep -rn '\bread\b' "$SCRIPTS_DIR" --include="*.sh" 2>/dev/null | grep -v 'while' || true)
if [ -z "$bare_read" ]; then
  echo "  PASS: no bare 'read' outside while loops"
  PASS=$((PASS + 1))
else
  echo "  FAIL: bare 'read' (reads stdin, may hang without TTY):"
  echo "$bare_read"
  FAIL=$((FAIL + 1))
fi

# ── Dynamic: no-TTY execution ────────────────────────────────────

echo ""
echo "=== Dynamic: commands complete without TTY (no hang) ==="

# list.sh ─────────────────────────────────────────────────────────

echo ""
echo "--- list.sh ---"

out=$(run_no_tty 5 "$LIST_SCRIPT" --from "$CATALOG") && rc=0 || rc=$?
assert_exit "list completes" 0 "$rc"
assert_not_contains "no prompt in list output" "$out" "[Y/n]"
assert_not_contains "no password prompt in list output" "$out" "Password"
assert_contains "contains code-review" "$out" "example/code-review"
assert_contains "contains git-helpers" "$out" "example/git-helpers"

out=$(run_no_tty 5 "$LIST_SCRIPT" --from /nonexistent/path) && rc=0 || rc=$?
assert_exit "list nonexistent catalog exits 5 (RESOURCE_UNAVAILABLE)" 5 "$rc"

out=$(run_no_tty 5 "$LIST_SCRIPT" --badflag) && rc=0 || rc=$?
assert_exit "list unknown flag exits 2 (INVALID_USAGE)" 2 "$rc"

assert_json_valid "list --json is valid JSON" 5 "$LIST_SCRIPT" --from "$CATALOG" --json

echo ""
echo "--- list.sh determinism ---"
tmp1=$(mktemp)
tmp2=$(mktemp)
bash "$LIST_SCRIPT" --from "$CATALOG" < /dev/null > "$tmp1" 2>/dev/null
bash "$LIST_SCRIPT" --from "$CATALOG" < /dev/null > "$tmp2" 2>/dev/null
if diff "$tmp1" "$tmp2" >/dev/null 2>&1; then
  echo "  PASS: list produces deterministic output"
  PASS=$((PASS + 1))
else
  echo "  FAIL: list output differs between runs"
  FAIL=$((FAIL + 1))
fi
rm -f "$tmp1" "$tmp2"

# search.sh ───────────────────────────────────────────────────────

echo ""
echo "--- search.sh ---"

out=$(run_no_tty 5 "$SEARCH_SCRIPT" --from "$CATALOG" "code-review") && rc=0 || rc=$?
assert_exit "search completes" 0 "$rc"
assert_not_contains "no prompt in search output" "$out" "[Y/n]"
assert_not_contains "no password prompt in search output" "$out" "Password"
assert_contains "finds code-review" "$out" "example/code-review"

out=$(run_no_tty 5 "$SEARCH_SCRIPT" --from "$CATALOG") && rc=0 || rc=$?
assert_exit "search missing query exits 2 (INVALID_USAGE)" 2 "$rc"

out=$(run_no_tty 5 "$SEARCH_SCRIPT" --from /nonexistent "query") && rc=0 || rc=$?
assert_exit "search nonexistent catalog exits 5 (RESOURCE_UNAVAILABLE)" 5 "$rc"

assert_json_valid "search --json is valid JSON" 5 "$SEARCH_SCRIPT" --from "$CATALOG" --json "review"

echo ""
echo "--- search.sh determinism ---"
tmp1=$(mktemp)
tmp2=$(mktemp)
bash "$SEARCH_SCRIPT" --from "$CATALOG" "example/" < /dev/null > "$tmp1" 2>/dev/null
bash "$SEARCH_SCRIPT" --from "$CATALOG" "example/" < /dev/null > "$tmp2" 2>/dev/null
if diff "$tmp1" "$tmp2" >/dev/null 2>&1; then
  echo "  PASS: search produces deterministic output"
  PASS=$((PASS + 1))
else
  echo "  FAIL: search output differs between runs"
  FAIL=$((FAIL + 1))
fi
rm -f "$tmp1" "$tmp2"

# install.sh ──────────────────────────────────────────────────────

echo ""
echo "--- install.sh ---"

# Error cases that exercise argument parsing without needing yq

out=$(run_no_tty 5 "$INSTALL_SCRIPT" "invalidref") && rc=0 || rc=$?
assert_exit "install invalid ref exits 2 (INVALID_USAGE)" 2 "$rc"
assert_not_contains "no prompt in install error output" "$out" "[Y/n]"

out=$(run_no_tty 5 "$INSTALL_SCRIPT") && rc=0 || rc=$?
assert_exit "install missing arg exits 2 (INVALID_USAGE)" 2 "$rc"

out=$(run_no_tty 5 "$INSTALL_SCRIPT" --badflag "example/thing") && rc=0 || rc=$?
assert_exit "install unknown flag exits 2 (INVALID_USAGE)" 2 "$rc"

# With a valid ref but no source configured: should fail cleanly, not hang
target=$(mktemp -d)
out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
      CLAUDE_SKILLS_MARKETPLACE_URL="" \
      run_no_tty 10 "$INSTALL_SCRIPT" "example/thing") && rc=0 || rc=$?
rm -rf "$target"
# Either exits 2 (no source) or exits 5 (resource unavailable)
if [ "$rc" -eq 2 ] || [ "$rc" -eq 5 ]; then
  echo "  PASS: install with no source exits $rc (reserved code)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: install with no source exited $rc (expected 2 or 5)"
  FAIL=$((FAIL + 1))
fi
assert_not_contains "no prompt from install" "$out" "[Y/n]"

# Happy-path install test (requires yq, conditional)
if command -v yq >/dev/null 2>&1; then
  echo ""
  echo "--- install.sh with yq available ---"

  target=$(mktemp -d)
  out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
        CLAUDE_SKILLS_MARKETPLACE_URL="" \
        CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
        run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE_FIXTURE" "example/hello-world") && rc=0 || rc=$?
  assert_exit "install completes" 0 "$rc"
  assert_not_contains "no prompt in install output" "$out" "[Y/n]"
  assert_contains "installed hello-world" "$out" "Installed"
  rm -rf "$target"

  # No-op reinstall exits 0, no hang
  target=$(mktemp -d)
  CLAUDE_SKILLS_INSTALL_TARGET="$target" \
    CLAUDE_SKILLS_MARKETPLACE_URL="" \
    CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
    run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE_FIXTURE" "example/hello-world" > /dev/null 2>&1 || true
  out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
        CLAUDE_SKILLS_MARKETPLACE_URL="" \
        CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
        run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE_FIXTURE" "example/hello-world") && rc=0 || rc=$?
  assert_exit "reinstall no-op exits 0" 0 "$rc"
  assert_contains "no-op message" "$out" "already installed"
  rm -rf "$target"

  # --json output is valid JSON (stdout only: JSON, stderr: diagnostics)
  target=$(mktemp -d)
  set +e
  json_out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
             CLAUDE_SKILLS_MARKETPLACE_URL="" \
             CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
             timeout 15 bash "$INSTALL_SCRIPT" --from "$MARKETPLACE_FIXTURE" --json "example/hello-world" < /dev/null 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] && echo "$json_out" | jq -e '.status' >/dev/null 2>&1; then
    echo "  PASS: install --json is valid JSON with status field"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: install --json output not valid (rc=$rc)"
    echo "    output: $json_out"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$target"

  # Nonexistent skill exits 4 (INPUT_INVALID)
  target=$(mktemp -d)
  out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
        CLAUDE_SKILLS_MARKETPLACE_URL="" \
        CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
        run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE_FIXTURE" "example/nonexistent") && rc=0 || rc=$?
  assert_exit "install nonexistent skill exits 4 (INPUT_INVALID)" 4 "$rc"
  rm -rf "$target"

  # Unknown version exits 4 (INPUT_INVALID)
  target=$(mktemp -d)
  out=$(CLAUDE_SKILLS_INSTALL_TARGET="$target" \
        CLAUDE_SKILLS_MARKETPLACE_URL="" \
        CLAUDE_SKILLS_CACHE_DIR="$target/.cache" \
        run_no_tty 15 "$INSTALL_SCRIPT" --from "$MARKETPLACE_FIXTURE" "example/hello-world@9.9.9") && rc=0 || rc=$?
  assert_exit "install unknown version exits 4 (INPUT_INVALID)" 4 "$rc"
  rm -rf "$target"
else
  echo ""
  echo "--- install.sh (yq not available, skipping happy-path TTY tests) ---"
fi

# generate-index.sh ───────────────────────────────────────────────

echo ""
echo "--- generate-index.sh ---"

if command -v yq >/dev/null 2>&1; then
  out_dir=$(mktemp -d)
  skills_dir="$REPO_ROOT/tests/catalog/fixtures/skills"
  out=$(SKILLS_DIR="$skills_dir" INDEX_DIR="$out_dir" run_no_tty 10 "$GENERATOR") && rc=0 || rc=$?
  assert_exit "generate-index completes" 0 "$rc"
  assert_not_contains "no prompt in generator output" "$out" "[Y/n]"
  assert_contains "confirmation message on stderr" "$out" "Catalog index written"
  [ -f "$out_dir/catalog.json" ] || { echo "  FAIL: catalog.json not created"; FAIL=$((FAIL + 1)); }
  [ -f "$out_dir/catalog.json" ] && { echo "  PASS: catalog.json created"; PASS=$((PASS + 1)); }
  rm -rf "$out_dir"

  # Idempotency: two runs produce identical output
  echo ""
  echo "--- generate-index.sh determinism ---"
  run1=$(mktemp -d)
  run2=$(mktemp -d)
  SKILLS_DIR="$skills_dir" INDEX_DIR="$run1" bash "$GENERATOR" < /dev/null > /dev/null 2>&1
  SKILLS_DIR="$skills_dir" INDEX_DIR="$run2" bash "$GENERATOR" < /dev/null > /dev/null 2>&1
  if diff "$run1/catalog.json" "$run2/catalog.json" >/dev/null 2>&1; then
    echo "  PASS: generate-index produces deterministic output"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: generate-index output differs between runs"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$run1" "$run2"

  # Empty skills directory produces valid empty catalog
  empty_skills=$(mktemp -d)
  empty_out=$(mktemp -d)
  set +e
  SKILLS_DIR="$empty_skills" INDEX_DIR="$empty_out" bash "$GENERATOR" < /dev/null > /dev/null 2>&1
  rc=$?
  set -e
  assert_exit "empty skills exits 0" 0 "$rc"
  if jq -e '.entries == {}' "$empty_out/catalog.json" >/dev/null 2>&1; then
    echo "  PASS: empty skills produces empty entries"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: empty skills catalog has non-empty entries"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$empty_skills" "$empty_out"
else
  echo "  yq not available, skipping generate-index dynamic tests"
fi

# ── Prompt detection: verify no command emits interactive prompts ─

echo ""
echo "=== Prompt detection: no interactive prompts in any output ==="

prompt_patterns=(
  '[Y/n]'
  '[y/N]'
  'Password:'
  'Press any key'
  'Continue?'
  'Confirm?'
  'yes/no'
)

combined_out="$(
  run_no_tty 5 "$LIST_SCRIPT" --from "$CATALOG" 2>/dev/null || true
  run_no_tty 5 "$SEARCH_SCRIPT" --from "$CATALOG" "test" 2>/dev/null || true
  run_no_tty 5 "$INSTALL_SCRIPT" "invalidref" 2>/dev/null || true
)"

for pat in "${prompt_patterns[@]}"; do
  if echo "$combined_out" | grep -qiF "$pat"; then
    echo "  FAIL: output contains interactive prompt pattern: $pat"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: no prompt pattern '$pat' in command output"
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
