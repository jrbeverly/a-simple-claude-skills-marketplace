#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$REPO_ROOT/scripts/installer/config.sh"
config_load_file
config_apply_env

# --- Parse arguments ---
FORCE=0
QUIET=0
VERBOSE=0
JSON_OUT=0
ALL=0
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
    --all)
      ALL=1
      shift
      ;;
    -q|--quiet)
      QUIET=1; VERBOSE=0; JSON_OUT=0
      shift
      ;;
    -v|--verbose)
      QUIET=0; VERBOSE=1; JSON_OUT=0
      shift
      ;;
    --json)
      QUIET=0; VERBOSE=0; JSON_OUT=1
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

config_resolve

if [ "$ALL" -eq 0 ]; then
  [ -n "$SKILL_REF" ] || { echo "ERROR: skill reference required (or use --all)" >&2; exit 2; }
fi

[ -n "$MARKETPLACE_URL" ] || { echo "ERROR: no marketplace source specified (use --from or set MARKETPLACE_URL)" >&2; exit 2; }

# --- Helpers ---
_err()  { echo "ERROR: $*" >&2; }
_info() { [ "$QUIET" -eq 0 ] && echo "$*" >&2 || true; }
_verb() { [ "$VERBOSE" -eq 1 ] && echo "$*" >&2 || true; }

_json_out() {
  local status="$1" key="$2" old_version="$3" new_version="$4" path="$5"
  jq -n --arg status "$status" --arg key "$key" --arg old_version "$old_version" --arg new_version "$new_version" --arg path "$path" \
    '{status: $status, key: $key, old_version: $old_version, new_version: $new_version, path: $path}'
}

_is_url() { [[ "$1" =~ ^https?:// ]]; }

# --- Fetch remote marketplace (clone/fetch with sparse checkout) ---
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
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -r "$src_dir/$skill_path/"* "$dest/"
}

# --- Verify post-update integrity ---
_verify() {
  local dir="$1"
  local manifest="$dir/skill.yaml"

  [ -f "$manifest" ] || { _err "skill.yaml missing after update"; return 1; }

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

# --- Update a single skill ---
_update_one() {
  local skill_key="$1"

  if ! [[ "$skill_key" =~ ^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$ ]]; then
    _err "invalid skill reference '$skill_key' (expected <namespace>/<name>)"
    return 2
  fi

  local namespace="${skill_key%%/*}"
  local name="${skill_key##*/}"
  local skill_path="skills/$namespace/$name"
  local install_dir="$INSTALL_TARGET/$skill_key"

  if [ ! -d "$install_dir" ] || [ ! -f "$install_dir/skill.yaml" ]; then
    _err "skill '$skill_key' is not installed"
    return 6
  fi

  local installed_ver
  installed_ver=$(yq -r '.version' "$install_dir/skill.yaml" 2>/dev/null || true)

  # Resolve catalog
  local catalog_file
  if _is_url "$MARKETPLACE_URL"; then
    catalog_file=$(_fetch_remote "$MARKETPLACE_URL" "$namespace" "$name")
  else
    catalog_file="$MARKETPLACE_URL/index/catalog.json"
    [ -f "$catalog_file" ] || { _err "catalog not found at $catalog_file"; return 5; }
  fi

  # Look up skill in catalog
  local catalog_version
  catalog_version=$(jq -r ".entries[\"$skill_key\"].version // empty" "$catalog_file" 2>/dev/null)
  [ -n "$catalog_version" ] || { _err "skill '$skill_key' not found in catalog"; return 4; }

  # Check if update needed
  if [ "$installed_ver" = "$catalog_version" ] && [ "$FORCE" -ne 1 ]; then
    _info "Skill '$skill_key@$installed_ver' is already current."
    [ "$JSON_OUT" -eq 1 ] && _json_out "already_current" "$skill_key" "$installed_ver" "$installed_ver" "$install_dir"
    return 0
  fi

  _info "Updating '$skill_key' from $installed_ver to $catalog_version..."

  _copy_skill "$MARKETPLACE_URL" "$skill_path" "$install_dir"

  _verify "$install_dir" || {
    _err "update verification failed for $skill_key"
    return 1
  }

  _info "Updated '$skill_key' to $catalog_version"
  [ "$JSON_OUT" -eq 1 ] && _json_out "updated" "$skill_key" "$installed_ver" "$catalog_version" "$install_dir"
  return 0
}

# --- Main ---
if [ "$ALL" -eq 1 ]; then
  overall_rc=0
  updated=0
  current=0
  failed=0

  if [ ! -d "$INSTALL_TARGET" ]; then
    _info "No skills installed."
    exit 0
  fi

  while IFS= read -r -d '' manifest; do
    rel="${manifest#$INSTALL_TARGET/}"
    ns="${rel%%/*}"
    rest="${rel#*/}"
    nm="${rest%%/*}"
    skill_key="$ns/$nm"

    _update_one "$skill_key" || {
      rc=$?
      failed=$((failed + 1))
      overall_rc=$rc
      continue
    }
    # Check if it was updated or already current by looking at message
    # (we don't get the return value distinction here easily)
  done < <(find "$INSTALL_TARGET" -name "skill.yaml" -type f -print0 2>/dev/null | sort -z)

  if [ "$failed" -gt 0 ]; then
    _err "$failed skill(s) failed to update"
    exit $overall_rc
  fi
  exit 0
else
  _update_one "$SKILL_REF"
fi
