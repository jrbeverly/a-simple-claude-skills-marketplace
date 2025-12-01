# Skill Directory Layout

The canonical directory layout for a single skill: where files live, how they are named, and how the layout maps between the repository and the installed location.

## Repository layout

Every skill lives in its own directory under `skills/<namespace>/<name>/`. The `namespace` and `name` are kebab-case identifiers matching `^[a-z][a-z0-9-]*$` — the same format as the skill manifest `name` field. Together they form the catalog key `<namespace>/<name>` defined in the [catalog index format](catalog-index-format.md).

### Reference skill tree

```
skills/<namespace>/<name>/
├── skill.yaml              # Manifest (required)
├── SKILL.md                # Primary skill instructions (required)
├── README.md               # Human-facing overview (optional)
├── scripts/                # Executable scripts
│   └── run.sh
├── prompts/                # Prompt or instruction templates
│   ├── main.md
│   └── review.md
├── templates/              # Files with variable substitution
│   └── report.md
├── examples/               # Sample inputs, outputs, or usage
│   └── example-output.json
└── assets/                 # Static files (images, icons, data)
    └── icon.svg
```

The directory is flat by convention: one level of sub-directories, no deeper nesting.

### Required top-level files

| File | Required | Purpose |
|------|----------|---------|
| `skill.yaml` | Yes | Machine-readable manifest. Schema defined in [skill manifest schema](skill-manifest-schema.md). |
| `SKILL.md` | Yes | The primary instructions or prompt that defines what the skill does and how the runtime should behave. This is the file loaded by the runtime when the skill is invoked. |
| `README.md` | No | Human-facing overview: what the skill does, how to use it, authorship, and any setup notes. Not loaded by the runtime; for contributors and catalog browsers. |

`SKILL.md` is the conventional name for the file that contains the skill's primary prompt or instruction set. It is distinct from `README.md`:
- `SKILL.md` is for the runtime (machine-consumed instructions).
- `README.md` is for humans (documentation).

If a skill is simple enough that its entire behaviour fits in a single prompt file, `SKILL.md` can be that file. The `entrypoint` field in `skill.yaml` would then point to it or to a thin wrapper script.

### `SKILL.md` declaration

`SKILL.md` is a material like any other. It must be listed in the manifest's `materials` array with `type: prompt`:

```yaml
materials:
  - path: SKILL.md
    type: prompt
    description: Primary skill instructions and behaviour definition
```

If `SKILL.md` is also the entry point (the file invoked when the skill is run), the `entrypoint` field references it:

```yaml
entrypoint: SKILL.md
```

When the entry point is a script that wraps or calls `SKILL.md`, `entrypoint` points to the script instead and `SKILL.md` remains a material:

```yaml
entrypoint: scripts/run.sh
materials:
  - path: SKILL.md
    type: prompt
    description: Primary skill instructions and behaviour definition
  - path: scripts/run.sh
    type: script
    description: Entry-point wrapper that loads SKILL.md
```

## Sub-directories

Sub-directories are optional. A skill only creates the ones it needs. Each sub-directory has a conventional purpose:

| Directory | Conventional contents | Material type |
|-----------|-----------------------|---------------|
| `scripts/` | Executable scripts (bash, Python, etc.) | `script` |
| `prompts/` | Prompt templates and instruction files | `prompt` |
| `templates/` | Files that undergo variable substitution at runtime | `template` |
| `examples/` | Sample inputs, outputs, or usage demonstrations | `reference` |
| `assets/` | Static files: images, icons, data files, fonts | `other` |

These are conventions, not constraints. A skill author may place materials in the root of the skill directory if the skill is simple enough that sub-directories add more structure than value. The manifest's `materials` array is the authoritative list of what the skill provides, regardless of where files are placed.

### Depth convention

**Maximum depth:** 2 levels from the skill root (i.e. `<subdir>/<file>`). No nested sub-directories.

**Rationale:** A flat structure keeps paths short, makes the manifest's `materials` entries easy to read, and prevents deeply nested paths that complicate relocation. If a skill genuinely needs deeper nesting (e.g. a complex template tree), it can be approved during review with a documented reason.

## Naming rules

### Files

- **Kebab-case** (`^[a-z][a-z0-9-]*$`) for all material files, matching the same pattern as the manifest `name` field.
- **Extension** must reflect the file format (`.sh`, `.md`, `.json`, `.py`, `.yaml`, `.svg`, etc.).
- **No spaces or special characters** in filenames. Hyphens only as word separators.
- **Entry point scripts** may have a simpler name if the skill only has one script (e.g. `run.sh`). If a skill has multiple scripts, each needs a descriptive name (e.g. `pr-checks.sh`, `setup-environment.sh`).

Examples: ✅ `run.sh`, `pr-checks.sh`, `main.md`, `review-report.md`, `icon.svg` — ❌ `run_script.sh`, `PRChecks.sh`, `Main Prompt.md`, `icon (2).svg`

### Sub-directories

- **Lowercase single word** matching one of the conventional names listed above.
- The conventional names (`scripts`, `prompts`, `templates`, `examples`, `assets`) are preferred. A different name requires a documented reason.
- No nesting: `scripts/helpers/` is not allowed. Use a flat `scripts/` with descriptive filenames instead.

## Install target

When a skill is installed, its entire directory tree is placed at:

```
~/.claude/skills/<namespace>/<name>/
```

### Justification

- **XDG-adjacent convention:** `~/.claude/` is the Claude Code configuration directory. Placing skills under `~/.claude/skills/` keeps them within the existing configuration namespace and avoids creating a new top-level dot-directory.
- **Mirrors the catalog key:** The path segment `<namespace>/<name>` is the same key used in `catalog.json` entries and in the repository layout. A consumer that knows the catalog key can derive both the repository path and the install path without additional mapping.
- **Predictable:** The path is deterministic from the skill identity alone. No hashing, no database lookup.
- **Co-installable:** Separate namespaces prevent collisions between skills from different sources.
- **No version in path:** The install path does not include a version segment. Only one version of a skill is installed at a time. Version switching and coexistence are installer concerns, not layout concerns.

### Installed tree

```
~/.claude/skills/<namespace>/<name>/
├── skill.yaml
├── SKILL.md
├── README.md
├── scripts/
│   └── run.sh
├── prompts/
│   └── main.md
├── templates/
│   └── report.md
├── examples/
│   └── example-output.json
└── assets/
    └── icon.svg
```

The installed tree is identical to the repository tree. The installer copies the skill directory recursively, preserving the internal structure. This ensures relative paths in the manifest resolve identically in both locations.

## Relative path rules

All paths declared in `skill.yaml` (`entrypoint`, `materials[].path`) are relative to the skill's root directory — the directory that contains `skill.yaml`.

### Constraints

| Rule | Requirement |
|------|-------------|
| **Root-relative** | Paths are resolved relative to the skill root directory. |
| **No parent traversal** | `..` is not allowed in any path. A skill must be self-contained. |
| **No absolute paths** | Paths must not start with `/` or a drive letter. |
| **POSIX separators** | Forward slash (`/`) only. Backslashes are not valid. |
| **No `./` prefix** | Paths are implicitly relative. Leading `./` is not used. |
| **No shell patterns** | Globs (`*`, `?`, `[`) are not allowed in `entrypoint` or `materials[].path`. |

### Rationale

These rules guarantee that a skill is relocatable: the same manifest works unchanged whether the skill sits in a repository, in `~/.claude/skills/`, or in any other directory. A consumer only needs to know the skill root to resolve every path declared in the manifest.

### Resolution contract

Given a skill root directory `R` and a manifest path `P`:
1. Join `R` and `P` with a single `/`.
2. Resolve the resulting path.
3. The path must be within `R` (no `..` escape).

```text
R = ~/.claude/skills/example/code-review
P = prompts/review.md
→ ~/.claude/skills/example/code-review/prompts/review.md
```

## Cross-references

- **[Skill identity and versioning](skill-identity-and-versioning.md):** Defines the skill key (`<namespace>/<name>`), versioning rules, reference syntax, and deprecation policy. The directory layout is the filesystem realisation of the skill key.
- **[Skill manifest schema](skill-manifest-schema.md):** Defines `skill.yaml` fields including `entrypoint`, `materials`, and their path constraints. The directory layout is the filesystem complement to that schema: the manifest declares what files exist; this document defines where they go.
- **[Catalog index format](catalog-index-format.md):** The `<namespace>/<name>` key used in `catalog.json` entries is the same key used in the repository path (`skills/<namespace>/<name>/`) and the install path (`~/.claude/skills/<namespace>/<name>/`). The index's `path` field points to the skill directory within the repository.
- **Categorization and tagging:** Defined in the manifest schema and indexed in the catalog. Not affected by the directory layout.
