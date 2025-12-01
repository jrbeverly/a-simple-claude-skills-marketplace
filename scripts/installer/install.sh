#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/config.sh"
config_load_file
config_apply_env

# --- Parse arguments ---
FORCE=0
QUIET=0
VERBOSE=0
JSON_OUT=0
SKILL_REF=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from)
      [ $# -gt 1 ] || { echo "ERROR: --from requires a value" >&2; exit 2; }
      config_set MARKETPLACE_URL "$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -q|--quiet)
      QUIET=1
      VERBOSE=0
      JSON_OUT=0
      shift
      ;;
    -v|--verbose)
      QUIET=0
      VERBOSE=1
      JSON_OUT=0
      shift
      ;;
    --json)
      QUIET=0
      VERBOSE=0
      JSON_OUT=1
      shift
      ;;
    -*)
      echo "ERROR: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [ -z "$SKILL_REF" ]; then
        SKILL_REF="$1"
        shift
      else
        echo "ERROR: unexpected argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

[ -n "$SKILL_REF" ] || { echo "ERROR: skill reference required" >&2; exit 2; }

config_resolve

[ -n "$MARKETPLACE_URL" ] || { echo "ERROR: no marketplace source specified (use --from or set MARKETPLACE_URL)" >&2; exit 2; }

# --- Parse skill reference: <namespace>/<name>[@<version>] ---
if [[ "$SKILL_REF" == *@* ]]; then
  SKILL_VERSION="${SKILL_REF#*@}"
  SKILL_KEY="${SKILL_REF%@*}"
else
  SKILL_VERSION="latest"
  SKILL_KEY="$SKILL_REF"
fi

if ! [[ "$SKILL_KEY" =~ ^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$ ]]; then
  echo "ERROR: invalid skill reference '$SKILL_KEY' (expected <namespace>/<name>)" >&2
  exit 2
fi

NAMESPACE="${SKILL_KEY%%/*}"
NAME="${SKILL_KEY##*/}"

# --- Helpers ---

_err()  { echo "ERROR: $*" >&2; }
_info() { [ "$QUIET" -eq 0 ] && echo "$*" >&2 || true; }
_verb() { [ "$VERBOSE" -eq 1 ] && echo "$*" >&2 || true; }

_json_out() {
  local status="$1" key="$2" version="$3" path="$4"
  jq -n --arg status "$status" --arg key "$key" --arg version "$version" --arg path "$path" \
    '{status: $status, key: $key, version: $version, path: $path}'
}

# --- Source type detection ---
_is_url() { [[ "$1" =~ ^https?:// ]]; }

# --- Fetch catalog and skill from a remote (git) source ---
# Populates CACHE_DIR with the clone. Prints the path to catalog.json.
_fetch_remote() {
  local source="$1" ns="$2" name="$3"

  if ! command -v git >/dev/null 2>&1; then
    _err "git is required for remote marketplace sources"
    exit 3
  fi

  CACHE_DIR="${CACHE_DIR%/}/marketplace"

  if [ -d "$CACHE_DIR" ]; then
    _verb "Updating cached marketplace at $CACHE_DIR..."
    git -C "$CACHE_DIR" fetch --depth 1 origin HEAD 2>/dev/null || {
      _verb "Fetch failed, removing stale cache and re-cloning"
      rm -rf "$CACHE_DIR"
    }
  fi

  if [ ! -d "$CACHE_DIR" ]; then
    _verb "Cloning marketplace from $source..."
    git clone --depth 1 --sparse "$source" "$CACHE_DIR" 2>&1 || {
      _err "failed to clone marketplace from $source"
      exit 5
    }
  fi

  git -C "$CACHE_DIR" sparse-checkout set "index/catalog.json" "skills/$ns/$name" 2>&1 || {
    _err "sparse checkout failed for skills/$ns/$name"
    exit 5
  }

  echo "$CACHE_DIR/index/catalog.json"
}

# --- Copy skill files from source to install directory ---
_copy_skill() {
  local source="$1" skill_path="$2" dest="$3"
  local src_dir

  if _is_url "$MARKETPLACE_URL"; then
    src_dir="${CACHE_DIR%/}/marketplace"
  else
    src_dir="$source"
  fi

  [ -d "$src_dir/$skill_path" ] || { _err "skill directory not found: $skill_path"; exit 5; }
  mkdir -p "$dest"
  cp -r "$src_dir/$skill_path/"* "$dest/"
}

# --- Verify post-install integrity ---
_verify() {
  local dir="$1"
  local manifest="$dir/skill.yaml"

  [ -f "$manifest" ] || { _err "skill.yaml missing after install"; return 1; }

  local ep
  ep=$(yq -r '.entrypoint' "$manifest" 2>/dev/null)
  if [ -z "$ep" ] || [ "$ep" = "null" ]; then
    _err "entrypoint missing or null in manifest"
    return 1
  fi
  [ -f "$dir/$ep" ] || { _err "entrypoint '$ep' not found on disk"; return 1; }

  local mat_ok=0
  while IFS= read -r mat; do
    [ -z "$mat" ] && continue
    [ -f "$dir/$mat" ] || { _err "material '$mat' not found on disk"; return 1; }
    mat_ok=$((mat_ok + 1))
  done < <(yq -r '.materials[].path' "$manifest" 2>/dev/null)

  if [ "$mat_ok" -eq 0 ]; then
    _err "no materials declared in manifest"
    return 1
  fi

  _verb "Integrity OK: manifest, entrypoint, $mat_ok material(s) present"
  return 0
}

# --- Main ---

SKILL_PATH="skills/$NAMESPACE/$NAME"
INSTALL_DIR="$INSTALL_TARGET/$SKILL_KEY"

# Resolve catalog
if _is_url "$MARKETPLACE_URL"; then
  catalog_file=$(_fetch_remote "$MARKETPLACE_URL" "$NAMESPACE" "$NAME")
else
  catalog_file="$MARKETPLACE_URL/index/catalog.json"
  [ -f "$catalog_file" ] || { _err "catalog not found at $catalog_file"; exit 5; }
fi

# Look up skill in catalog
CATALOG_VERSION=$(jq -r ".entries[\"$SKILL_KEY\"].version // empty" "$catalog_file" 2>/dev/null)
[ -n "$CATALOG_VERSION" ] || { _err "skill '$SKILL_KEY' not found in catalog"; exit 4; }

# Determine version
if [ "$SKILL_VERSION" = "latest" ]; then
  SKILL_VERSION="$CATALOG_VERSION"
fi

# Verify version match
if [ "$SKILL_VERSION" != "$CATALOG_VERSION" ]; then
  _err "version $SKILL_VERSION not found (catalog has $CATALOG_VERSION)"
  exit 4
fi

# Check if already installed (no-op for same version)
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/skill.yaml" ]; then
  installed_ver=$(yq -r '.version' "$INSTALL_DIR/skill.yaml" 2>/dev/null || true)
  if [ "$installed_ver" = "$SKILL_VERSION" ]; then
    _info "Skill '$SKILL_KEY@$SKILL_VERSION' is already installed."
    [ "$JSON_OUT" -eq 1 ] && _json_out "already_installed" "$SKILL_KEY" "$SKILL_VERSION" "$INSTALL_DIR"
    exit 0
  fi
  if [ "$FORCE" -ne 1 ]; then
    _err "skill '$SKILL_KEY' already installed (version $installed_ver). Use --force to overwrite."
    exit 6
  fi
  _info "Overwriting $SKILL_KEY (was $installed_ver, now $SKILL_VERSION)"
fi

# Install
_copy_skill "$MARKETPLACE_URL" "$SKILL_PATH" "$INSTALL_DIR"

_verify "$INSTALL_DIR" || {
  _err "install verification failed for $SKILL_KEY"
  rm -rf "$INSTALL_DIR"
  exit 1
}

_info "Installed '$SKILL_KEY@$SKILL_VERSION' to $INSTALL_DIR"
[ "$JSON_OUT" -eq 1 ] && _json_out "installed" "$SKILL_KEY" "$SKILL_VERSION" "$INSTALL_DIR"
exit 0
