#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS_DIR="${SKILLS_DIR:-$REPO_ROOT/skills}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$REPO_ROOT/scripts}"
TESTS_DIR="${TESTS_DIR:-$REPO_ROOT/tests}"

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
      echo "ERROR: unexpected argument: $1" >&2
      exit 2
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

# --- check_duplicate_skills ---
# Two skills with the same <namespace>/<name> key (derived from directory path)
check_duplicate_skills() {
  _verb "Checking for duplicate skills..."
  if [ ! -d "$SKILLS_DIR" ]; then
    return 0
  fi
  declare -A seen
  while IFS= read -r -d '' manifest_path; do
    local rel="${manifest_path#$SKILLS_DIR/}"
    local ns="${rel%%/*}"
    local rest="${rel#*/}"
    local name="${rest%%/*}"
    local key="${ns}/${name}"
    if [ -n "${seen[$key]:-}" ]; then
      record_violation "DUPLICATE_SKILL" "skills/$key/" \
        "Skill key '${key}' is duplicated; first seen at ${seen[$key]}"
    else
      seen[$key]="skills/$key/"
    fi
  done < <(find "$SKILLS_DIR" -name "skill.yaml" -type f -print0 2>/dev/null | sort -z || true)
}

# --- check_orphan_files ---
# Files under skills/ not referenced by any manifest and not a documented exception.
# Documented exceptions: .gitkeep, skill.yaml (the manifest itself), README.md.
check_orphan_files() {
  _verb "Checking for orphan files..."
  if [ ! -d "$SKILLS_DIR" ]; then
    return 0
  fi

  # First, collect files outside any skill directory (skills/ root or skills/<ns>/ level)
  while IFS= read -r -d '' file_path; do
    local rel="${file_path#$SKILLS_DIR/}"
    local base
    base=$(basename "$file_path")

    case "$base" in
      .gitkeep) continue ;;
    esac

    record_violation "ORPHAN_FILE" "skills/$rel" \
      "File outside any skill directory is not a documented exception"
  done < <(find "$SKILLS_DIR" -maxdepth 2 -type f -print0 2>/dev/null | sort -z || true)

  # For each skill directory, check files against the manifest
  while IFS= read -r -d '' skill_dir; do
    local rel_dir="${skill_dir#$SKILLS_DIR/}"
    local manifest="$skill_dir/skill.yaml"

    [ -f "$manifest" ] || continue

    # Build the set of known paths from the manifest
    local known_tmp
    known_tmp=$(mktemp)
    # exceptions are never orphans
    printf '%s\n' "skill.yaml" "README.md" ".gitkeep" >> "$known_tmp"

    # entrypoint
    yq -r '.entrypoint // ""' "$manifest" 2>/dev/null | while IFS= read -r ep; do
      [ -z "$ep" ] && continue
      [ "$ep" = "null" ] && continue
      printf '%s\n' "$ep" >> "$known_tmp"
    done || true

    # material paths
    yq -r '.materials // [] | .[] | .path // ""' "$manifest" 2>/dev/null | while IFS= read -r mp; do
      [ -z "$mp" ] && continue
      printf '%s\n' "$mp" >> "$known_tmp"
    done || true

    # Check each file in the skill directory
    while IFS= read -r -d '' file_path; do
      local skill_rel="${file_path#$skill_dir/}"

      if grep -qxF "$skill_rel" "$known_tmp" 2>/dev/null; then
        continue
      fi

      local file_rel="skills/$rel_dir/$skill_rel"
      record_violation "ORPHAN_FILE" "$file_rel" \
        "Not referenced in skill.yaml materials, entrypoint, or documented exceptions"
    done < <(find "$skill_dir" -type f -print0 2>/dev/null | sort -z || true)

    rm -f "$known_tmp"
  done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null | sort -z || true)
}

# --- check_skill_integrity ---
# Each skill directory must have skill.yaml, SKILL.md, valid entrypoint, and valid material paths.
check_skill_integrity() {
  _verb "Checking skill integrity..."
  if [ ! -d "$SKILLS_DIR" ]; then
    return 0
  fi
  while IFS= read -r -d '' skill_dir; do
    local rel_dir="${skill_dir#$SKILLS_DIR/}"
    local manifest="$skill_dir/skill.yaml"

    if [ ! -f "$manifest" ]; then
      record_violation "MISSING_SKILL_YAML" "skills/$rel_dir/" \
        "Missing required file: skill.yaml"
      continue
    fi

    # --- SKILL.md checks ---
    if [ ! -f "$skill_dir/SKILL.md" ]; then
      record_violation "MISSING_SKILL_MD" "skills/$rel_dir/SKILL.md" \
        "Missing required file: SKILL.md"
    else
      local skill_md_type
      skill_md_type=$(yq -r '.materials // [] | map(select(.path == "SKILL.md")) | .[0].type // ""' "$manifest" 2>/dev/null || true)
      if [ -z "$skill_md_type" ] || [ "$skill_md_type" = "null" ]; then
        record_violation "SKILL_MD_NOT_PROMPT" "skills/$rel_dir/skill.yaml" \
          "SKILL.md is not listed in materials"
      elif [ "$skill_md_type" != "prompt" ]; then
        record_violation "SKILL_MD_NOT_PROMPT" "skills/$rel_dir/skill.yaml" \
          "SKILL.md has type '${skill_md_type}', expected 'prompt'"
      fi
    fi

    # --- Entrypoint checks ---
    local ep
    ep=$(yq -r '.entrypoint // ""' "$manifest" 2>/dev/null || true)
    if [ -z "$ep" ] || [ "$ep" = "null" ]; then
      record_violation "MISSING_SKILL_YAML" "skills/$rel_dir/skill.yaml" \
        "Required field 'entrypoint' is missing or null"
    else
      if [[ "$ep" == *".."* ]]; then
        record_violation "PARENT_TRAVERSAL" "skills/$rel_dir/skill.yaml" \
          "Entrypoint '${ep}' contains parent traversal"
      elif [ ! -f "$skill_dir/$ep" ]; then
        record_violation "ENTRYPOINT_NOT_FOUND" "skills/$rel_dir/skill.yaml" \
          "Entrypoint '${ep}' does not exist on disk"
      fi
    fi

    # --- Materials path checks ---
    local mat_count=0
    while IFS= read -r mat_path; do
      [ -z "$mat_path" ] && continue
      mat_count=$((mat_count + 1))

      if [[ "$mat_path" == *".."* ]]; then
        record_violation "PARENT_TRAVERSAL" "skills/$rel_dir/skill.yaml" \
          "Material path '${mat_path}' contains parent traversal"
        continue
      fi

      local depth
      depth=$(echo "$mat_path" | tr -cd '/' | wc -c)
      depth=$((depth + 1))
      if [ "$depth" -gt 2 ]; then
        record_violation "EXCESSIVE_DEPTH" "skills/$rel_dir/skill.yaml" \
          "Material path '${mat_path}' exceeds depth 2 (found ${depth})"
      fi

      if [ ! -f "$skill_dir/$mat_path" ]; then
        record_violation "MATERIAL_PATH_NOT_FOUND" "skills/$rel_dir/skill.yaml" \
          "Material path '${mat_path}' does not exist on disk"
      fi
    done < <(yq -r '.materials // [] | .[] | .path // ""' "$manifest" 2>/dev/null || true)
  done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null | sort -z || true)
}

# --- check_repository_structure ---
# No files directly in scripts/ or tests/ -- only subdirectories allowed.
check_repository_structure() {
  _verb "Checking repository structure..."
  for dir_path in "$SCRIPTS_DIR" "$TESTS_DIR"; do
    local dir_label
    dir_label=$(basename "$dir_path")
    if [ ! -d "$dir_path" ]; then
      continue
    fi
    while IFS= read -r -d '' file_path; do
      local base
      base=$(basename "$file_path")
      case "$base" in
        .gitkeep) continue ;;
      esac
      local rel="${file_path#$REPO_ROOT/}"
      record_violation "STRUCTURE_VIOLATION" "$rel" \
        "Source file directly in '${dir_label}/' — must be in a subdirectory"
    done < <(find "$dir_path" -maxdepth 1 -type f -print0 2>/dev/null | sort -z || true)
  done
}

# --- Main ---
_info "Running lint checks..."

check_duplicate_skills
check_orphan_files
check_skill_integrity
check_repository_structure

if [ "$violation_count" -eq 0 ]; then
  _info "No violations found."
  if [ "$JSON_OUT" -eq 1 ]; then
    jq -n --arg schema_version "1.0.0" --arg tool "lint" --argjson exit_code 0 \
      '{schema_version: $schema_version, tool: $tool, exit_code: $exit_code, violations: [], summary: {total: 0, by_code: {}}}'
  fi
  exit 0
fi

_info "Found ${violation_count} violation(s)."

if [ "$JSON_OUT" -eq 1 ]; then
  jq -n --arg schema_version "1.0.0" --arg tool "lint" --argjson exit_code 1 --slurpfile violations "$violations_tmp" \
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

exit 1
