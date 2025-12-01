#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS_DIR="${SKILLS_DIR:-$REPO_ROOT/skills}"
INDEX_DIR="${INDEX_DIR:-$REPO_ROOT/index}"
INDEX_FILE="$INDEX_DIR/catalog.json"
SCHEMA_VERSION="1.0.0"

mkdir -p "$INDEX_DIR"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if [ -d "$SKILLS_DIR" ]; then
  while IFS= read -r -d '' manifest_path; do
    rel_path="${manifest_path#$SKILLS_DIR/}"
    namespace="${rel_path%%/*}"
    rest="${rel_path#*/}"
    name="${rest%%/*}"
    key="${namespace}/${name}"
    skill_dir="skills/${namespace}/${name}"

    version=$(yq -r '.version' "$manifest_path" 2>/dev/null)
    description=$(yq -r '.description' "$manifest_path" 2>/dev/null)

    if [ -z "$version" ] || [ "$version" = "null" ]; then
      echo "ERROR: $manifest_path: missing or null version" >&2
      exit 1
    fi
    if [ -z "$description" ] || [ "$description" = "null" ]; then
      echo "ERROR: $manifest_path: missing or null description" >&2
      exit 1
    fi

    tags=$(yq -o json '.tags // [] | sort' "$manifest_path" 2>/dev/null || echo "[]")
    categories=$(yq -o json '.categories // [] | sort' "$manifest_path" 2>/dev/null || echo "[]")

    hash_hex=$(sha256sum "$manifest_path" | cut -d' ' -f1)
    manifest_hash="sha256:${hash_hex}"

    jq -n \
      --arg key "$key" \
      --arg version "$version" \
      --arg description "$description" \
      --argjson tags "$tags" \
      --argjson categories "$categories" \
      --arg path "$skill_dir" \
      --arg manifest_hash "$manifest_hash" \
      '{key: $key, version: $version, description: $description, tags: $tags, categories: $categories, path: $path, manifest_hash: $manifest_hash}' \
      >> "$tmp"
  done < <(find "$SKILLS_DIR" -name "skill.yaml" -type f -print0 | sort -z)
fi

jq -n --arg version "$SCHEMA_VERSION" --slurpfile entries "$tmp" '
{
  schema_version: $version,
  entries: ($entries | sort_by(.key) | map({key: .key, value: {version, description, tags, categories, path, manifest_hash}}) | from_entries)
}' > "$INDEX_FILE"

echo "Catalog index written to $INDEX_FILE" >&2
