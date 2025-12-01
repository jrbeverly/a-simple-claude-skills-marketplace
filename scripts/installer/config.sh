#!/usr/bin/env bash
# Installer configuration with documented precedence:
#   CLI flag > environment variable > config file > built-in default
#
# Config file: ~/.config/claude-skills/config (key=value format)
# Environment: CLAUDE_SKILLS_* prefix
# CLI: --install-target, --marketplace-url, --cache-dir, --config-file
#
# Configurable values:
#
# | Key              | Env Variable                    | CLI Flag            | Default                              |
# |------------------|---------------------------------|---------------------|--------------------------------------|
# | INSTALL_TARGET   | CLAUDE_SKILLS_INSTALL_TARGET    | --install-target    | ~/.claude/skills                     |
# | MARKETPLACE_URL  | CLAUDE_SKILLS_MARKETPLACE_URL   | --marketplace-url   | (empty)                              |
# | CACHE_DIR        | CLAUDE_SKILLS_CACHE_DIR         | --cache-dir         | ~/.cache/claude-skills               |
# | CONFIG_FILE      | CLAUDE_SKILLS_CONFIG_FILE       | --config-file       | ~/.config/claude-skills/config       |
#
# Usage (from an installer script):
#   source scripts/installer/config.sh     # sets defaults
#   config_load_file                       # apply config file overrides
#   config_apply_env                       # apply environment overrides
#   config_set INSTALL_TARGET /custom      # apply CLI overrides (one per flag)
#   config_resolve                         # expand tildes, finalize
set -euo pipefail

# Built-in defaults
_CONFIG_DEFAULT_INSTALL_TARGET="$HOME/.claude/skills"
_CONFIG_DEFAULT_MARKETPLACE_URL=""
_CONFIG_DEFAULT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-skills"
_CONFIG_DEFAULT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-skills/config"

# Runtime state
INSTALL_TARGET=""
MARKETPLACE_URL=""
CACHE_DIR=""
CONFIG_FILE=""

# Expand a leading ~ to $HOME.
_expand_tilde() {
  local path="$1"
  if [[ "$path" == "~"* ]]; then
    printf '%s' "${HOME}${path:1}"
  else
    printf '%s' "$path"
  fi
}

# Reset all values to built-in defaults.
config_reset() {
  INSTALL_TARGET="$_CONFIG_DEFAULT_INSTALL_TARGET"
  MARKETPLACE_URL="$_CONFIG_DEFAULT_MARKETPLACE_URL"
  CACHE_DIR="$_CONFIG_DEFAULT_CACHE_DIR"
  CONFIG_FILE="$_CONFIG_DEFAULT_CONFIG_FILE"
}

# Load values from a key=value config file.  Blank lines and #-comments
# are ignored.  Optional single or double quotes around values are stripped.
config_load_file() {
  local file
  file="$(_expand_tilde "${1:-$CONFIG_FILE}")"
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      value="${value#\"}"; value="${value%\"}"
      value="${value#\'}"; value="${value%\'}"
      case "$key" in
        INSTALL_TARGET)   INSTALL_TARGET="$value" ;;
        MARKETPLACE_URL)  MARKETPLACE_URL="$value" ;;
        CACHE_DIR)        CACHE_DIR="$value" ;;
      esac
    fi
  done < "$file"
}

# Apply environment variable overrides (CLAUDE_SKILLS_* prefix).
config_apply_env() {
  [ -n "${CLAUDE_SKILLS_INSTALL_TARGET:-}" ]  && INSTALL_TARGET="$CLAUDE_SKILLS_INSTALL_TARGET"
  [ -n "${CLAUDE_SKILLS_MARKETPLACE_URL:-}" ] && MARKETPLACE_URL="$CLAUDE_SKILLS_MARKETPLACE_URL"
  [ -n "${CLAUDE_SKILLS_CACHE_DIR:-}" ]       && CACHE_DIR="$CLAUDE_SKILLS_CACHE_DIR"
  [ -n "${CLAUDE_SKILLS_CONFIG_FILE:-}" ]     && CONFIG_FILE="$CLAUDE_SKILLS_CONFIG_FILE"
  return 0
}

# Set a single config value (for CLI overrides, highest precedence).
config_set() {
  local key="$1" value="$2"
  case "$key" in
    INSTALL_TARGET)   INSTALL_TARGET="$value" ;;
    MARKETPLACE_URL)  MARKETPLACE_URL="$value" ;;
    CACHE_DIR)        CACHE_DIR="$value" ;;
    CONFIG_FILE)      CONFIG_FILE="$value" ;;
  esac
}

# Expand tildes in path values.
config_resolve() {
  INSTALL_TARGET="$(_expand_tilde "$INSTALL_TARGET")"
  CACHE_DIR="$(_expand_tilde "$CACHE_DIR")"
  CONFIG_FILE="$(_expand_tilde "$CONFIG_FILE")"
}

# Print resolved configuration as KEY=VALUE lines on stdout.
config_print() {
  printf 'INSTALL_TARGET=%s\n' "$INSTALL_TARGET"
  printf 'MARKETPLACE_URL=%s\n' "$MARKETPLACE_URL"
  printf 'CACHE_DIR=%s\n' "$CACHE_DIR"
  printf 'CONFIG_FILE=%s\n' "$CONFIG_FILE"
}

# Initialize to defaults on source
config_reset
