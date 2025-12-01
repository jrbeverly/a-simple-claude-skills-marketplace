# Skill Manifest Schema

The canonical schema for the `skill.yaml` manifest file that every skill ships with.

## Format and filename

**Format:** YAML (`skill.yaml`)

**Rationale:** YAML is [widely available in CI and shell environments](https://mikefarah.gitbook.io/yq) via `yq`, which provides the same query-and-transform power that `jq` provides for JSON. YAML supports comments (`#`), multi-line strings, and has less syntactic noise than JSON — all of which matter for manifests that contributors must hand-write. Using YAML also aligns with conventions familiar to the target audience (Docker Compose, GitHub Actions, Kubernetes, Helm).

The filename `skill.yaml` is descriptive, glob-friendly (`**/skill.yaml`), and unambiguous about what kind of manifest the file contains.

## Required fields

### `name`

- **Type:** string
- **Constraints:** 1–64 characters. Must match `^[a-z][a-z0-9-]*$` (kebab-case). Must not start or end with a hyphen, must not contain consecutive hyphens.
- **Purpose:** Machine-readable identifier for the skill. Used in CLI commands, directory names, and as a unique key in catalogs.

```yaml
name: code-review
```

### `version`

- **Type:** string
- **Constraints:** Must be valid [SemVer 2.0](https://semver.org/) (`MAJOR.MINOR.PATCH`). Pre-release and build metadata suffixes are allowed.
- **Purpose:** The skill's version. Follows SemVer so catalogs and package managers can express version constraints.

```yaml
version: 1.0.0
```

### `description`

- **Type:** string
- **Constraints:** 1–200 characters. Free text.
- **Purpose:** One-line summary of what the skill does. Displayed in catalog listings and search results.

```yaml
description: Reviews pull requests for correctness, security, and style issues.
```

### `entrypoint`

- **Type:** string
- **Constraints:** 1–255 characters. Must be a relative POSIX path pointing to an executable or script within the skill package. Shell-style patterns (globs) are not allowed.
- **Purpose:** The file that is invoked when the skill is run. The runtime resolves this path relative to the skill's root directory.

```yaml
entrypoint: run.sh
```

### `materials`

- **Type:** array of objects
- **Constraints:** At least one entry. Every material object requires a `path` (string, 1–255 chars, relative POSIX path within the skill package) and a `type` (enum, see below). An optional `description` (string, 1–200 chars) may be provided.
- **Purpose:** Declares the files the skill provides. Used by the runtime to know which files to load, and by catalogs to display what a skill contains.

Material `type` values:

| Value        | Meaning                                              |
|-------------|------------------------------------------------------|
| `prompt`    | A Claude Code prompt or instruction template         |
| `script`    | An executable script (bash, Python, etc.)            |
| `template`  | A file that undergoes variable substitution at runtime |
| `reference` | A read-only reference document                       |
| `other`     | Catch-all for material types not listed above        |

```yaml
materials:
  - path: prompts/review.md
    type: prompt
    description: Main code review prompt
  - path: scripts/pr-checks.sh
    type: script
    description: Automated PR validation checks
```

## Optional fields

### `tags`

- **Type:** array of strings
- **Constraints:** 0–20 items. Each tag must match `^[a-z][a-z0-9-]*$`, 1–30 characters.
- **Purpose:** Free-form keywords for discoverability. Catalogs may use tags for filtering and search.

#### Tag formatting rules

Tags are free-form, but the following rules are enforced to keep the catalog searchable and consistent:

| Rule | Requirement |
|------|-------------|
| **Case** | Lowercase only (`^[a-z]`). No uppercase letters allowed. |
| **Allowed characters** | Lowercase letters (`a-z`), digits (`0-9`), and single hyphens (`-`) between segments. Must start with a letter. |
| **Length** | 1–30 characters. Tags shorter than 1 or longer than 30 characters are invalid. |
| **Separator** | Use a single hyphen (`-`) to separate words within a tag (e.g. `pull-requests`, not `pull_requests` or `pullRequests`). |
| **Consecutive hyphens** | Not allowed. `foo--bar` is invalid. |
| **Leading/trailing hyphens** | Not allowed. `-foo` and `foo-` are invalid. |
| **Cardinality** | 0–20 items per skill. An omitted `tags` field is equivalent to `tags: []`. |

Tags that do not conform to these rules make the manifest invalid.

```yaml
tags:
  - code-review
  - pull-requests
  - security
```

### `categories`

- **Type:** array of strings
- **Constraints:** 0–10 items. Each value must be one of the reserved category identifiers listed below. Values are compared case-sensitively.
- **Purpose:** Grouping label for catalog organization. Unlike tags, categories come from a fixed, reserved vocabulary so catalogs can build consistent navigation. Arbitrary values outside the reserved list are invalid.

#### Reserved categories

| Category | Scope |
|----------|-------|
| `review` | Reviewing code, pull requests, designs, architecture, security posture, or other artifacts |
| `planning` | Design, specification, discovery, roadmapping, and architectural decision-making |
| `docs` | Writing, generating, maintaining, or reviewing documentation |
| `behaviours` | Automations, workflows, hooks, conventions, and process enforcement |
| `development` | Code generation, implementation, scaffolding, and boilerplate creation |
| `testing` | Test automation, test generation, verification, linting, and quality gates |
| `deployment` | CI/CD, release management, infrastructure, and delivery pipelines |
| `maintenance` | Refactoring, dependency management, debugging, monitoring, and observability |

The list is intentionally small. A skill that spans multiple categories may list up to 10 of them. Broad categories reduce the need for catalog consumers to reconcile overlapping labels.

```yaml
categories:
  - review
  - maintenance
```

#### Proposing new reserved categories

The reserved category list is defined in this specification. Adding, removing, or renaming a category is a **breaking change** to the catalog schema and must follow this process:

1. **Open a proposal issue** describing the proposed category, its scope, and the skills that would use it.
2. **Show that no existing category covers the use case.** The bar is "the existing categories cannot reasonably describe this skill." If a skill fits under an existing category, a new one is not needed.
3. **Demonstrate at least three concrete skills** that would use the new category. This prevents adding categories for hypothetical use cases.
4. **Update this specification** (the reserved categories table) and the catalog index schema if the category changes affect the index format.
5. **Regenerate the catalog index** after the specification change is merged.

Categories are reserved to keep the catalog navigable. The taxonomy should evolve slowly and deliberately.

### `homepage`

- **Type:** string
- **Constraints:** 0–255 characters. If present, must be a valid `https://` URL.
- **Purpose:** Link to the skill's homepage, repository, or documentation.

```yaml
homepage: https://github.com/example/code-review-skill
```

### `license`

- **Type:** string
- **Constraints:** 0–64 characters. If present, must be a valid [SPDX license identifier](https://spdx.org/licenses/).
- **Purpose:** The license under which the skill is distributed.

```yaml
license: MIT
```

### `authors`

- **Type:** array of objects
- **Constraints:** 0–50 items. Each author object requires `name` (string, 1–100 chars). Optional fields: `email` (valid email, max 254 chars) and `url` (valid `https://` URL, max 255 chars).
- **Purpose:** Credits and contact information for the skill's authors.

```yaml
authors:
  - name: Jane Doe
    email: jane@example.com
    url: https://example.com
```

### `dependencies`

- **Type:** array of objects
- **Constraints:** 0–50 items. Each dependency object requires `name` (string, 1–64 chars) and `version` (string, a valid SemVer range expression as defined by [node-semver](https://github.com/npm/node-semver#ranges)). An optional `repository` (string, valid `https://` URL, max 255 chars) may specify where to fetch the dependency.
- **Purpose:** Declares other skills or packages this skill depends on. The runtime uses these to resolve and fetch dependencies before loading the skill.

```yaml
dependencies:
  - name: git-helpers
    version: ">=1.2.0 <2.0.0"
    repository: https://skills.example.com/catalog
```

## Validation summary

| Field         | Required | Type            | Key constraints                                      |
|---------------|----------|-----------------|------------------------------------------------------|
| `name`        | yes      | string          | 1–64 chars, `^[a-z][a-z0-9-]*$`                      |
| `version`     | yes      | string          | SemVer 2.0                                            |
| `description` | yes      | string          | 1–200 chars                                           |
| `entrypoint`  | yes      | string          | 1–255 chars, relative POSIX path                      |
| `materials`   | yes      | array of object | ≥1 item; `path` + `type` required per item            |
| `tags`        | no       | array of string | ≤20 items, each 1–30 chars, `^[a-z][a-z0-9-]*$`      |
| `categories`  | no       | array of string | ≤10 items, from fixed vocabulary                      |
| `homepage`    | no       | string          | Valid `https://` URL, max 255 chars                   |
| `license`     | no       | string          | SPDX identifier, max 64 chars                         |
| `authors`     | no       | array of object | ≤50 items; `name` required, `email`/`url` optional    |
| `dependencies`| no       | array of object | ≤50 items; `name` + `version` required, `repository` optional |

## Guidance

- **Unknown fields must be ignored** by consumers. This allows additive schema evolution without breaking existing skills.
- **All required fields must be present and valid.** If a required field is missing or invalid, the manifest is invalid and the skill must not be loaded.
- **Optional fields default to empty/absent** when omitted. An omitted `tags` field is equivalent to `tags: []`.
- **Field ordering** within the manifest file is not significant. Present them in the order shown in the example for readability.

 


