#!/usr/bin/env bash
set -euo pipefail


REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS_DIR="${SKILLS_DIR:-$REPO_ROOT/skills}"

# --- Dependency check ---
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed" >&2
  exit 3
fi
if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq is required but not installed" >&2
  exit 3
fi

# --- Flag parsing ---
QUIET=0
VERBOSE=0
JSON_OUT=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
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
      if [ -z "$TARGET" ]; then
        TARGET="$1"
        shift
      else
        echo "ERROR: unexpected argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

# --- Helpers ---
_err()  { echo "ERROR: $*" >&2; }
_info() { [ "$QUIET" -eq 0 ] && echo "$*" >&2 || true; }
_verb() { [ "$VERBOSE" -eq 1 ] && echo "$*" >&2 || true; }

violations_tmp=$(mktemp)
trap 'rm -f "$violations_tmp"' EXIT
violation_count=0

record_violation() {
  local code="$1" file="$2" message="$3"
  jq -n --arg code "$code" --arg severity "error" --arg file "$file" --arg message "$message" \
    '{code: $code, severity: $severity, file: $file, message: $message}' \
    >> "$violations_tmp"
  violation_count=$((violation_count + 1))
}

# --- Reserved categories ---
RESERVED_CATEGORIES="review|planning|docs|behaviours|development|testing|deployment|maintenance"

# --- is_kebab_case ---
# Validates kebab-case: starts with letter, only a-z0-9-, no consecutive hyphens, no trailing hyphen.
is_kebab_case() {
  local val="$1"
  if ! [[ "$val" =~ ^[a-z][a-z0-9-]*$ ]]; then
    return 1
  fi
  if [[ "$val" == *"--"* ]]; then
    return 1
  fi
  if [[ "$val" == *- ]]; then
    return 1
  fi
  return 0
}

# --- check_path_safety ---
# Checks a path for parent traversal and depth > 2.
# Returns 0 if safe, 1 if unsafe (violation recorded).
check_path_safety() {
  local path="$1" field="$2" manifest_file="$3"

  if [[ "$path" == *".."* ]]; then
    record_violation "PARENT_TRAVERSAL" "$manifest_file" \
      "${field} '${path}' contains parent traversal"
    return 1
  fi

  if [[ "$path" == /* ]]; then
    record_violation "INVALID_FIELD_VALUE" "$manifest_file" \
      "${field} '${path}' is an absolute path; must be relative"
    return 1
  fi

  local depth
  depth=$(echo "$path" | tr -cd '/' | wc -c)
  depth=$((depth + 1))
  if [ "$depth" -gt 2 ]; then
    record_violation "EXCESSIVE_DEPTH" "$manifest_file" \
      "${field} '${path}' exceeds depth 2 (found ${depth})"
    return 1
  fi

  return 0
}

# --- validate_manifest ---
# Validates a single skill.yaml against the schema.
validate_manifest() {
  local manifest_path="$1"
  local skill_dir="$2"
  local manifest_file="$3"

  _verb "Validating $manifest_file..."

  # --- name ---
  local name
  name=$(yq -r '.name // ""' "$manifest_path" 2>/dev/null || true)
  if [ -z "$name" ] || [ "$name" = "null" ]; then
    record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
      "Required field 'name' is missing or null"
  else
    local name_type
    name_type=$(yq -r '.name | type' "$manifest_path" 2>/dev/null || true)
    if [ "$name_type" != "!!str" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'name' must be a string (got ${name_type})"
    else
      local name_len=${#name}
      if [ "$name_len" -lt 1 ]; then
        record_violation "FIELD_TOO_SHORT" "$manifest_file" \
          "Field 'name' must be at least 1 character (got ${name_len})"
      elif [ "$name_len" -gt 64 ]; then
        record_violation "FIELD_TOO_LONG" "$manifest_file" \
          "Field 'name' must be at most 64 characters (got ${name_len})"
      elif ! is_kebab_case "$name"; then
        record_violation "INVALID_NAME_FORMAT" "$manifest_file" \
          "Field 'name' value '${name}' does not match kebab-case pattern"
      fi
    fi
  fi

  # --- version ---
  local version
  version=$(yq -r '.version // ""' "$manifest_path" 2>/dev/null || true)
  if [ -z "$version" ] || [ "$version" = "null" ]; then
    record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
      "Required field 'version' is missing or null"
  else
    local version_type
    version_type=$(yq -r '.version | type' "$manifest_path" 2>/dev/null || true)
    if [ "$version_type" != "!!str" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'version' must be a string (got ${version_type})"
    elif ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
      record_violation "INVALID_SEMVER" "$manifest_file" \
        "Field 'version' value '${version}' is not valid SemVer"
    elif [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      : # strict MAJOR.MINOR.PATCH — valid
    elif [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
      : # with pre-release or build metadata — valid
    else
      record_violation "INVALID_SEMVER" "$manifest_file" \
        "Field 'version' value '${version}' is not valid SemVer"
    fi
  fi

  # --- description ---
  local description
  description=$(yq -r '.description // ""' "$manifest_path" 2>/dev/null || true)
  if [ -z "$description" ] || [ "$description" = "null" ]; then
    record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
      "Required field 'description' is missing or null"
  else
    local desc_type
    desc_type=$(yq -r '.description | type' "$manifest_path" 2>/dev/null || true)
    if [ "$desc_type" != "!!str" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'description' must be a string (got ${desc_type})"
    else
      local desc_len=${#description}
      if [ "$desc_len" -lt 1 ]; then
        record_violation "FIELD_TOO_SHORT" "$manifest_file" \
          "Field 'description' must be at least 1 character"
      elif [ "$desc_len" -gt 200 ]; then
        record_violation "FIELD_TOO_LONG" "$manifest_file" \
          "Field 'description' must be at most 200 characters (got ${desc_len})"
      fi
    fi
  fi

  # --- entrypoint ---
  local entrypoint
  entrypoint=$(yq -r '.entrypoint // ""' "$manifest_path" 2>/dev/null || true)
  if [ -z "$entrypoint" ] || [ "$entrypoint" = "null" ]; then
    record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
      "Required field 'entrypoint' is missing or null"
  else
    local ep_type
    ep_type=$(yq -r '.entrypoint | type' "$manifest_path" 2>/dev/null || true)
    if [ "$ep_type" != "!!str" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'entrypoint' must be a string (got ${ep_type})"
    else
      local ep_len=${#entrypoint}
      if [ "$ep_len" -lt 1 ]; then
        record_violation "FIELD_TOO_SHORT" "$manifest_file" \
          "Field 'entrypoint' must be at least 1 character"
      elif [ "$ep_len" -gt 255 ]; then
        record_violation "FIELD_TOO_LONG" "$manifest_file" \
          "Field 'entrypoint' must be at most 255 characters (got ${ep_len})"
      elif check_path_safety "$entrypoint" "entrypoint" "$manifest_file"; then
        if [ ! -f "$skill_dir/$entrypoint" ]; then
          record_violation "PATH_NOT_FOUND" "$manifest_file" \
            "Entrypoint '${entrypoint}' does not exist on disk"
        fi
      fi
    fi
  fi

  # --- materials ---
  local mat_type
  mat_type=$(yq -r '.materials | type' "$manifest_path" 2>/dev/null || true)
  if [ "$mat_type" = "!!null" ] || [ "$mat_type" = "null" ] || [ -z "$mat_type" ]; then
    record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
      "Required field 'materials' is missing or null"
  elif [ "$mat_type" != "!!seq" ]; then
    record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
      "Field 'materials' must be an array (got ${mat_type})"
  else
    local mat_count
    mat_count=$(yq -r '.materials | length' "$manifest_path" 2>/dev/null || true)
    if [ -z "$mat_count" ] || [ "$mat_count" = "null" ] || [ "$mat_count" -eq 0 ]; then
      record_violation "EMPTY_MATERIALS" "$manifest_file" \
        "Field 'materials' must have at least 1 entry"
    else
      local idx=0
      while [ "$idx" -lt "$mat_count" ]; do
        # --- material path ---
        local mat_path
        mat_path=$(yq -r ".materials[$idx].path // \"\"" "$manifest_path" 2>/dev/null || true)
        if [ -z "$mat_path" ] || [ "$mat_path" = "null" ]; then
          record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
            "materials[$idx]: required field 'path' is missing or null"
        else
          local mp_type
          mp_type=$(yq -r ".materials[$idx].path | type" "$manifest_path" 2>/dev/null || true)
          if [ "$mp_type" != "!!str" ]; then
            record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
              "materials[$idx].path must be a string (got ${mp_type})"
          else
            local mp_len=${#mat_path}
            if [ "$mp_len" -lt 1 ]; then
              record_violation "FIELD_TOO_SHORT" "$manifest_file" \
                "materials[$idx].path must be at least 1 character"
            elif [ "$mp_len" -gt 255 ]; then
              record_violation "FIELD_TOO_LONG" "$manifest_file" \
                "materials[$idx].path must be at most 255 characters (got ${mp_len})"
            elif check_path_safety "$mat_path" "materials[$idx].path" "$manifest_file"; then
              if [ ! -f "$skill_dir/$mat_path" ]; then
                record_violation "PATH_NOT_FOUND" "$manifest_file" \
                  "materials[$idx].path '${mat_path}' does not exist on disk"
              fi
            fi
          fi
        fi

        # --- material type ---
        local mat_val
        mat_val=$(yq -r ".materials[$idx].type // \"\"" "$manifest_path" 2>/dev/null || true)
        if [ -z "$mat_val" ] || [ "$mat_val" = "null" ]; then
          record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
            "materials[$idx]: required field 'type' is missing or null"
        else
          local mt_type
          mt_type=$(yq -r ".materials[$idx].type | type" "$manifest_path" 2>/dev/null || true)
          if [ "$mt_type" != "!!str" ]; then
            record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
              "materials[$idx].type must be a string (got ${mt_type})"
          else
            case "$mat_val" in
              prompt|script|template|reference|other) ;;
              *)
                record_violation "INVALID_MATERIAL_TYPE" "$manifest_file" \
                  "materials[$idx].type '${mat_val}' is not a valid material type (expected: prompt, script, template, reference, other)"
                ;;
            esac
          fi
        fi

        # --- material description (optional) ---
        local mat_desc
        mat_desc=$(yq -r ".materials[$idx].description // \"\"" "$manifest_path" 2>/dev/null || true)
        if [ -n "$mat_desc" ] && [ "$mat_desc" != "null" ]; then
          local md_len=${#mat_desc}
          if [ "$md_len" -gt 200 ]; then
            record_violation "FIELD_TOO_LONG" "$manifest_file" \
              "materials[$idx].description must be at most 200 characters (got ${md_len})"
          fi
        fi

        idx=$((idx + 1))
      done
    fi
  fi

  # --- tags (optional) ---
  local tags_type
  tags_type=$(yq -r '.tags | type' "$manifest_path" 2>/dev/null || true)
  if [ -n "$tags_type" ] && [ "$tags_type" != "!!null" ] && [ "$tags_type" != "null" ]; then
    if [ "$tags_type" != "!!seq" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'tags' must be an array (got ${tags_type})"
    else
      local tags_count
      tags_count=$(yq -r '.tags | length' "$manifest_path" 2>/dev/null || true)
      if [ -n "$tags_count" ] && [ "$tags_count" != "null" ]; then
        if [ "$tags_count" -gt 20 ]; then
          record_violation "TOO_MANY_ITEMS" "$manifest_file" \
            "Field 'tags' has ${tags_count} items (max 20)"
        fi
        local ti=0
        while [ "$ti" -lt "$tags_count" ]; do
          local tag
          tag=$(yq -r ".tags[$ti] // \"\"" "$manifest_path" 2>/dev/null || true)
          if [ -n "$tag" ] && [ "$tag" != "null" ]; then
            local tag_type
            tag_type=$(yq -r ".tags[$ti] | type" "$manifest_path" 2>/dev/null || true)
            if [ "$tag_type" != "!!str" ]; then
              record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
                "tags[$ti] must be a string (got ${tag_type})"
            else
              local tag_len=${#tag}
              if [ "$tag_len" -lt 1 ]; then
                record_violation "FIELD_TOO_SHORT" "$manifest_file" \
                  "tags[$ti] must be at least 1 character"
              elif [ "$tag_len" -gt 30 ]; then
                record_violation "FIELD_TOO_LONG" "$manifest_file" \
                  "tags[$ti] value '${tag}' must be at most 30 characters (got ${tag_len})"
              elif ! is_kebab_case "$tag"; then
                record_violation "INVALID_TAG_FORMAT" "$manifest_file" \
                  "tags[$ti] value '${tag}' does not match required pattern"
              fi
            fi
          fi
          ti=$((ti + 1))
        done
      fi
    fi
  fi

  # --- categories (optional) ---
  local cats_type
  cats_type=$(yq -r '.categories | type' "$manifest_path" 2>/dev/null || true)
  if [ -n "$cats_type" ] && [ "$cats_type" != "!!null" ] && [ "$cats_type" != "null" ]; then
    if [ "$cats_type" != "!!seq" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'categories' must be an array (got ${cats_type})"
    else
      local cats_count
      cats_count=$(yq -r '.categories | length' "$manifest_path" 2>/dev/null || true)
      if [ -n "$cats_count" ] && [ "$cats_count" != "null" ]; then
        if [ "$cats_count" -gt 10 ]; then
          record_violation "TOO_MANY_ITEMS" "$manifest_file" \
            "Field 'categories' has ${cats_count} items (max 10)"
        fi
        local ci=0
        while [ "$ci" -lt "$cats_count" ]; do
          local cat
          cat=$(yq -r ".categories[$ci] // \"\"" "$manifest_path" 2>/dev/null || true)
          if [ -n "$cat" ] && [ "$cat" != "null" ]; then
            if ! echo "$cat" | grep -qE "^(${RESERVED_CATEGORIES})$"; then
              record_violation "INVALID_CATEGORY" "$manifest_file" \
                "categories[$ci] value '${cat}' is not a reserved category"
            fi
          fi
          ci=$((ci + 1))
        done
      fi
    fi
  fi

  # --- homepage (optional) ---
  local homepage
  homepage=$(yq -r '.homepage // ""' "$manifest_path" 2>/dev/null || true)
  if [ -n "$homepage" ] && [ "$homepage" != "null" ]; then
    local hp_type
    hp_type=$(yq -r '.homepage | type' "$manifest_path" 2>/dev/null || true)
    if [ "$hp_type" != "!!str" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'homepage' must be a string (got ${hp_type})"
    else
      local hp_len=${#homepage}
      if [ "$hp_len" -gt 255 ]; then
        record_violation "FIELD_TOO_LONG" "$manifest_file" \
          "Field 'homepage' must be at most 255 characters (got ${hp_len})"
      elif ! [[ "$homepage" =~ ^https:// ]]; then
        record_violation "INVALID_URL" "$manifest_file" \
          "Field 'homepage' must be an https:// URL (got '${homepage}')"
      fi
    fi
  fi

  # --- license (optional) ---
  local license
  license=$(yq -r '.license // ""' "$manifest_path" 2>/dev/null || true)
  if [ -n "$license" ] && [ "$license" != "null" ]; then
    local lic_type
    lic_type=$(yq -r '.license | type' "$manifest_path" 2>/dev/null || true)
    if [ "$lic_type" != "!!str" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'license' must be a string (got ${lic_type})"
    else
      local lic_len=${#license}
      if [ "$lic_len" -gt 64 ]; then
        record_violation "FIELD_TOO_LONG" "$manifest_file" \
          "Field 'license' must be at most 64 characters (got ${lic_len})"
      fi
    fi
  fi

  # --- authors (optional) ---
  local auth_type
  auth_type=$(yq -r '.authors | type' "$manifest_path" 2>/dev/null || true)
  if [ -n "$auth_type" ] && [ "$auth_type" != "!!null" ] && [ "$auth_type" != "null" ]; then
    if [ "$auth_type" != "!!seq" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'authors' must be an array (got ${auth_type})"
    else
      local auth_count
      auth_count=$(yq -r '.authors | length' "$manifest_path" 2>/dev/null || true)
      if [ -n "$auth_count" ] && [ "$auth_count" != "null" ]; then
        if [ "$auth_count" -gt 50 ]; then
          record_violation "TOO_MANY_ITEMS" "$manifest_file" \
            "Field 'authors' has ${auth_count} items (max 50)"
        fi
        local ai=0
        while [ "$ai" -lt "$auth_count" ]; do
          # author name (required)
          local aname
          aname=$(yq -r ".authors[$ai].name // \"\"" "$manifest_path" 2>/dev/null || true)
          if [ -z "$aname" ] || [ "$aname" = "null" ]; then
            record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
              "authors[$ai]: required field 'name' is missing or null"
          else
            local an_len=${#aname}
            if [ "$an_len" -lt 1 ]; then
              record_violation "FIELD_TOO_SHORT" "$manifest_file" \
                "authors[$ai].name must be at least 1 character"
            elif [ "$an_len" -gt 100 ]; then
              record_violation "FIELD_TOO_LONG" "$manifest_file" \
                "authors[$ai].name must be at most 100 characters (got ${an_len})"
            fi
          fi

          # author email (optional)
          local aemail
          aemail=$(yq -r ".authors[$ai].email // \"\"" "$manifest_path" 2>/dev/null || true)
          if [ -n "$aemail" ] && [ "$aemail" != "null" ]; then
            local ae_len=${#aemail}
            if [ "$ae_len" -gt 254 ]; then
              record_violation "FIELD_TOO_LONG" "$manifest_file" \
                "authors[$ai].email must be at most 254 characters (got ${ae_len})"
            elif ! [[ "$aemail" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
              record_violation "INVALID_EMAIL" "$manifest_file" \
                "authors[$ai].email '${aemail}' is not a valid email address"
            fi
          fi

          # author url (optional)
          local aurl
          aurl=$(yq -r ".authors[$ai].url // \"\"" "$manifest_path" 2>/dev/null || true)
          if [ -n "$aurl" ] && [ "$aurl" != "null" ]; then
            local au_len=${#aurl}
            if [ "$au_len" -gt 255 ]; then
              record_violation "FIELD_TOO_LONG" "$manifest_file" \
                "authors[$ai].url must be at most 255 characters (got ${au_len})"
            elif ! [[ "$aurl" =~ ^https:// ]]; then
              record_violation "INVALID_URL" "$manifest_file" \
                "authors[$ai].url must be an https:// URL (got '${aurl}')"
            fi
          fi

          ai=$((ai + 1))
        done
      fi
    fi
  fi

  # --- dependencies (optional) ---
  local deps_type
  deps_type=$(yq -r '.dependencies | type' "$manifest_path" 2>/dev/null || true)
  if [ -n "$deps_type" ] && [ "$deps_type" != "!!null" ] && [ "$deps_type" != "null" ]; then
    if [ "$deps_type" != "!!seq" ]; then
      record_violation "INVALID_FIELD_TYPE" "$manifest_file" \
        "Field 'dependencies' must be an array (got ${deps_type})"
    else
      local deps_count
      deps_count=$(yq -r '.dependencies | length' "$manifest_path" 2>/dev/null || true)
      if [ -n "$deps_count" ] && [ "$deps_count" != "null" ]; then
        if [ "$deps_count" -gt 50 ]; then
          record_violation "TOO_MANY_ITEMS" "$manifest_file" \
            "Field 'dependencies' has ${deps_count} items (max 50)"
        fi
        local di=0
        while [ "$di" -lt "$deps_count" ]; do
          # dep name (required)
          local dname
          dname=$(yq -r ".dependencies[$di].name // \"\"" "$manifest_path" 2>/dev/null || true)
          if [ -z "$dname" ] || [ "$dname" = "null" ]; then
            record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
              "dependencies[$di]: required field 'name' is missing or null"
          else
            local dn_len=${#dname}
            if [ "$dn_len" -gt 64 ]; then
              record_violation "FIELD_TOO_LONG" "$manifest_file" \
                "dependencies[$di].name must be at most 64 characters (got ${dn_len})"
            fi
          fi

          # dep version (required)
          local dver
          dver=$(yq -r ".dependencies[$di].version // \"\"" "$manifest_path" 2>/dev/null || true)
          if [ -z "$dver" ] || [ "$dver" = "null" ]; then
            record_violation "MISSING_REQUIRED_FIELD" "$manifest_file" \
              "dependencies[$di]: required field 'version' is missing or null"
          fi

          # dep repository (optional)
          local drepo
          drepo=$(yq -r ".dependencies[$di].repository // \"\"" "$manifest_path" 2>/dev/null || true)
          if [ -n "$drepo" ] && [ "$drepo" != "null" ]; then
            local dr_len=${#drepo}
            if [ "$dr_len" -gt 255 ]; then
              record_violation "FIELD_TOO_LONG" "$manifest_file" \
                "dependencies[$di].repository must be at most 255 characters (got ${dr_len})"
            elif ! [[ "$drepo" =~ ^https:// ]]; then
              record_violation "INVALID_URL" "$manifest_file" \
                "dependencies[$di].repository must be an https:// URL (got '${drepo}')"
            fi
          fi

          di=$((di + 1))
        done
      fi
    fi
  fi
}

# --- Collect manifests to validate ---
declare -a manifest_tasks=()

if [ -n "$TARGET" ]; then
  if [ -f "$TARGET" ] && [ "$(basename "$TARGET")" = "skill.yaml" ]; then
    _target_dir="${TARGET%/*}"
    _target_rel="${_target_dir#$SKILLS_DIR/}"
    if [ "$_target_rel" = "$_target_dir" ]; then
      _target_rel="$(basename "$(dirname "$_target_dir")")/$(basename "$_target_dir")"
    fi
    manifest_tasks+=("$TARGET|$_target_dir|skills/$_target_rel")
  elif [ -d "$TARGET" ]; then
    _target_manifest="$TARGET/skill.yaml"
    if [ -f "$_target_manifest" ]; then
      _target_rel="${TARGET#$SKILLS_DIR/}"
      if [ "$_target_rel" = "$TARGET" ]; then
        _target_rel="$(basename "$(dirname "$TARGET")")/$(basename "$TARGET")"
      fi
      manifest_tasks+=("$_target_manifest|$TARGET|skills/$_target_rel")
    else
      _err "skill.yaml not found in $TARGET"
      exit 5
    fi
  else
    _err "not a skill directory or manifest: $TARGET"
    exit 5
  fi
else
  if [ -d "$SKILLS_DIR" ]; then
    while IFS= read -r -d '' manifest_path; do
      _skill_dir="${manifest_path%/*}"
      _rel="${_skill_dir#$SKILLS_DIR/}"
      manifest_tasks+=("$manifest_path|$_skill_dir|skills/$_rel")
    done < <(find "$SKILLS_DIR" -name "skill.yaml" -type f -print0 2>/dev/null | sort -z || true)
  fi
fi

# --- Main ---
_info "Validating skill manifests..."

for task in "${manifest_tasks[@]}"; do
  mp="${task%%|*}"
  _rest="${task#*|}"
  sd="${_rest%%|*}"
  mf="${_rest#*|}"
  validate_manifest "$mp" "$sd" "$mf"
done

if [ "$violation_count" -eq 0 ]; then
  _info "All manifests valid."
  if [ "$JSON_OUT" -eq 1 ]; then
    jq -n --arg schema_version "1.0.0" --arg tool "validate" --argjson exit_code 0 \
      '{schema_version: $schema_version, tool: $tool, exit_code: $exit_code, violations: [], summary: {total: 0, by_code: {}}}'
  fi
  exit 0
fi

_info "Found ${violation_count} violation(s)."

if [ "$JSON_OUT" -eq 1 ]; then
  jq -n --arg schema_version "1.0.0" --arg tool "validate" --argjson exit_code 4 --slurpfile violations "$violations_tmp" \
    '{
      schema_version: $schema_version,
      tool: $tool,
      exit_code: $exit_code,
      violations: $violations,
      summary: {
        total: ($violations | length),
        by_code: ($violations | group_by(.code) | map({key: .[0].code, value: length}) | from_entries)
      }
    }'
elif [ "$QUIET" -eq 0 ]; then
  jq -r '"  [\(.code)] \(.file) — \(.message)"' "$violations_tmp"
fi

exit 4
