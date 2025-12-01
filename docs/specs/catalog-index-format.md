# Catalog Index Format

The canonical schema for the machine-readable index that consumers use to list, search, and resolve skills without scanning the entire repository.

## Format and filename

**Format:** JSON (`catalog.json`)

**Rationale:** JSON is universally parseable and works with `jq` for querying in CI and shell environments. The index is machine-generated (not hand-written), so JSON's lack of comments and stricter syntax are not ergonomic concerns here. Using JSON ensures that every consumer — from shell scripts to web UIs — can parse the index without additional tooling.

The filename `catalog.json` is descriptive and unambiguous about what the file contains.

## Top-level fields

### `schema_version`

- **Type:** string
- **Constraints:** Must be valid [SemVer 2.0](https://semver.org/) (`MAJOR.MINOR.PATCH`). No pre-release or build metadata.
- **Purpose:** The version of the index schema itself. Consumers use this to determine compatibility before reading entries. Incremented when the index format changes in a breaking way.

```json
"schema_version": "1.0.0"
```

### `entries`

- **Type:** object (map)
- **Constraints:** Keys are `<namespace>/<name>` strings where both `namespace` and `name` match `^[a-z][a-z0-9-]*$` (the same kebab-case pattern as the skill manifest `name` field). The namespace provides organizational grouping and prevents name collisions.
- **Purpose:** The catalog of skills. Each value is an entry object describing one skill.

```json
"entries": {
  "example/code-review": { ... },
  "example/git-helpers": { ... }
}
```

## Entry fields

Each entry describes one skill and is keyed by `<namespace>/<name>`.

### `version`

- **Type:** string
- **Constraints:** Must be valid SemVer 2.0.
- **Purpose:** The skill's version, copied from the skill manifest. Consumers use this to select versions or detect updates.

### `description`

- **Type:** string
- **Constraints:** 1–200 characters. Copied from the skill manifest.
- **Purpose:** One-line summary for catalog listings and search results.

### `tags`

- **Type:** array of strings
- **Constraints:** 0–20 items. Each tag matches `^[a-z][a-z0-9-]*$`, 1–30 characters. Sorted alphabetically.
- **Purpose:** Free-form keywords for discoverability. Copied from the skill manifest.

### `categories`

- **Type:** array of strings
- **Constraints:** 0–10 items. Each value is a recognized category identifier (see the skill manifest schema). Sorted alphabetically.
- **Purpose:** Grouping labels for catalog organization. Copied from the skill manifest.

### `path`

- **Type:** string
- **Constraints:** 1–255 characters. Relative POSIX path from the repository root to the skill's directory (the directory containing `skill.yaml`). Must not start with `./` or `../`.
- **Purpose:** Where to find the skill in the repository. Consumers resolve this path to locate the skill manifest and its materials.

### `manifest_hash`

- **Type:** string
- **Constraints:** Format `sha256:<hex>` where `<hex>` is 64 lowercase hexadecimal characters.
- **Purpose:** A content hash of the skill's `skill.yaml` file. Consumers use this to detect changes without re-reading the full manifest. The generator computes this hash at index-build time.

## Complete schema

```json
{
  "schema_version": "1.0.0",
  "entries": {
    "<namespace>/<name>": {
      "version": "<semver>",
      "description": "<one-line summary>",
      "tags": ["<tag>", ...],
      "categories": ["<category>", ...],
      "path": "<relative-path-to-skill-directory>",
      "manifest_hash": "sha256:<64-hex-chars>"
    }
  }
}
```

## Ordering rules

The index must be reproducible: a second implementer running the generator against the same set of skill manifests must produce an identical `catalog.json`. These ordering rules guarantee that.

### Entry ordering

Entries in the `entries` object are sorted alphabetically by key (`<namespace>/<name>`) using standard Unicode codepoint comparison (equivalent to `LC_ALL=C` sort order). This is the natural ordering for `jq` and most JSON serializers when keys are inserted in sorted order.

### Array ordering

Within each entry, the `tags` and `categories` arrays are sorted alphabetically using the same codepoint comparison.

### Rationale

Sorted keys produce minimal, readable diffs when skills are added, removed, or updated. Alphabetical ordering is unambiguous and requires no external metadata.

## Hashing strategy

### Algorithm

SHA-256 of the **raw bytes** of the `skill.yaml` file.

### Encoding

The hash is encoded as `sha256:` followed by 64 lowercase hexadecimal characters:

```
sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

This format mirrors the [content-addressable identifier convention](https://github.com/opencontainers/image-spec/blob/main/descriptor.md#digests) used by OCI, Docker, and other content-addressed systems.

### What is hashed

The full file content of `skill.yaml` as raw bytes — no canonicalization, no field reordering, no whitespace normalization. The hash covers everything including comments, blank lines, and trailing whitespace.

### Rationale

Hashing raw file bytes is the simplest strategy that meets the reproducibility requirement:
- **Deterministic:** Same file bytes → same hash, always.
- **Tool-independent:** Every language and shell can compute `sha256sum skill.yaml`.
- **No parser dependency:** The generator does not need to parse YAML to compute the hash.
- **Change-detection:** Any modification to the manifest (including comment or whitespace changes) is reflected in a new hash, which is conservative and safe for change detection.

### Trade-offs accepted

- Reformatting the manifest (e.g., reordering fields, adjusting whitespace) produces a different hash even if the semantic content is identical. This is acceptable because manifests are edited by humans infrequently and reformatting is a deliberate action that warrants a new hash.
- The hash does not cover skill materials (prompts, scripts, templates). Only the manifest is hashed. Full skill integrity verification is a separate concern.

## Generation contract

The index is generated from a set of skill manifests by a generator tool (separate concern). The contract between the index and the generator is:

1. **Input:** A set of directories, each containing a valid `skill.yaml`.
2. **Output:** A `catalog.json` file conforming to this specification.
3. **Reproducibility:** Given the same inputs (same files at same paths), the output is byte-for-byte identical.
4. **Single writer:** The generator is the only process that writes `catalog.json`. Consumers treat it as read-only.
5. **Namespace derivation:** The `<namespace>/<name>` key is derived from the skill's location in the repository. The mapping from path to namespace is defined by the repository layout convention, not by the manifest.

### Empty catalog

When no skills exist, the index is still valid:

```json
{
  "schema_version": "1.0.0",
  "entries": {}
}
```

## Validation summary

| Field | Required | Type | Key constraints |
|-------|----------|------|-----------------|
| `schema_version` | yes | string | SemVer 2.0, no pre-release |
| `entries` | yes | object | Keys are `<namespace>/<name>` |
| `entries.<key>.version` | yes | string | SemVer 2.0 |
| `entries.<key>.description` | yes | string | 1–200 chars |
| `entries.<key>.tags` | yes | array of string | ≤20 items, sorted, `^[a-z][a-z0-9-]*$` |
| `entries.<key>.categories` | yes | array of string | ≤10 items, sorted, fixed vocabulary |
| `entries.<key>.path` | yes | string | 1–255 chars, relative POSIX path |
| `entries.<key>.manifest_hash` | yes | string | `sha256:<64-hex>` |

## Guidance

- **Unknown fields must be ignored** by consumers. This allows additive schema evolution (e.g., adding a `deprecated` field to entries) without breaking existing consumers.
- **Missing entries** must be treated as absent. A consumer looking for `<namespace>/<name>` that is not present in `entries` must treat the skill as not found.
- **`schema_version` changes** indicate the index format has changed. Consumers should check this field before processing entries. A change in the major version indicates a breaking change.
- **The index is a cache.** The skill manifest (`skill.yaml`) is the source of truth. If the index and a manifest disagree, the manifest wins.
- **Field ordering** within entry objects follows the order shown in the schema: `version`, `description`, `tags`, `categories`, `path`, `manifest_hash`. Producers write them in this order; consumers must not depend on it.
