#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CATALOG_FILE="$REPO_ROOT/index/catalog.json"
JSON_OUT=0
QUERY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from)
      [ $# -gt 1 ] || { echo "ERROR: --from requires a value" >&2; exit 2; }
      FROM="$2"
      shift 2
      ;;
    --json)
      JSON_OUT=1
      shift
      ;;
    -*)
      echo "ERROR: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [ -z "$QUERY" ]; then
        QUERY="$1"
        shift
      else
        echo "ERROR: unexpected argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

[ -n "$QUERY" ] || { echo "ERROR: search query required" >&2; exit 2; }

if [ -n "${FROM:-}" ]; then
  if [ -f "$FROM/index/catalog.json" ]; then
    CATALOG_FILE="$FROM/index/catalog.json"
  elif [ -f "$FROM" ]; then
    CATALOG_FILE="$FROM"
  else
    echo "ERROR: catalog not found at $FROM" >&2
    exit 5
  fi
fi

[ -f "$CATALOG_FILE" ] || { echo "ERROR: catalog not found at $CATALOG_FILE" >&2; exit 5; }

QUERY_LOWER=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')

if [ "$JSON_OUT" -eq 1 ]; then
  jq --arg q "$QUERY_LOWER" '
    [.entries | to_entries | sort_by(.key)[] |
     select(
       ((.key | ascii_downcase | contains($q)) or
        (.value.description | ascii_downcase | contains($q)) or
        ([.value.tags[]? | ascii_downcase | contains($q)] | any) or
        ([.value.categories[]? | ascii_downcase | contains($q)] | any))
     ) |
     {key: .key} + (.value | {version, description, tags, categories, path, manifest_hash})
    ]
  ' "$CATALOG_FILE"
else
  data=$(jq -r --arg q "$QUERY_LOWER" '
    .entries | to_entries | sort_by(.key) |
    map(select(
      ((.key | ascii_downcase | contains($q)) or
       (.value.description | ascii_downcase | contains($q)) or
       ([.value.tags[]? | ascii_downcase | contains($q)] | any) or
       ([.value.categories[]? | ascii_downcase | contains($q)] | any))
    ))[] | [.key, .value.version, .value.description] | @tsv
  ' "$CATALOG_FILE")
  if [ -n "$data" ]; then
    printf "%-40s %-12s %s\n" "SKILL" "VERSION" "DESCRIPTION"
    printf "%-40s %-12s %s\n" "-----" "-------" "-----------"
    echo "$data" | while IFS=$'\t' read -r key version desc; do
      printf "%-40s %-12s %s\n" "$key" "$version" "$desc"
    done
  fi
fi
