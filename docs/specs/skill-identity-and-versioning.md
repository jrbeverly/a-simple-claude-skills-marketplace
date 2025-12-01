# Skill Identity and Versioning

How a skill is uniquely identified across the marketplace, how versions evolve, and how both surface in install and update commands.

## Identity

### Skill key

A skill is identified by a **skill key**: `<namespace>/<name>`.

```
example/code-review
example/git-helpers
```

**Components:**

| Component | Definition |
|-----------|------------|
| `namespace` | Organisational grouping that prevents name collisions across independent authors. |
| `name` | Machine-readable identifier for one skill within the namespace. |

The skill key is the universal identifier: it is used in repository paths (`skills/<namespace>/<name>/`), catalog index entries, install targets (`~/.claude/skills/<namespace>/<name>/`), and CLI commands.

### Namespace

- **Format:** kebab-case, matching `^[a-z][a-z0-9-]*$`.
- **Length:** 1–64 characters.
- **Constraints:** Must not start or end with a hyphen. Must not contain consecutive hyphens.

The namespace is not declared in the skill manifest — it is derived from context:

| Context | Derivation |
|---------|------------|
| **Marketplace repository** | The directory name under `skills/` (e.g. `skills/example/code-review` → namespace `example`). |
| **Direct install** | Specified explicitly by the user at install time. |

### Name

The `name` field is declared in `skill.yaml`. Its format and constraints are defined in the [skill manifest schema](skill-manifest-schema.md#name).

### Reserved namespaces

The following namespaces are reserved and must not be used by community skills:

| Namespace | Reserved for |
|-----------|-------------|
| `claude` | Official Claude Code skills shipped by Anthropic. |
| `anthropic` | Skills published by Anthropic that are not bundled with Claude Code. |
| `system` | Skills managed automatically by the runtime or installer. |

### Reserved names

The following names are reserved and must not be used as a skill `name` within any namespace. They conflict with CLI subcommands and reserved keywords:

| Name | Conflict |
|------|----------|
| `install` | CLI install subcommand. |
| `uninstall` | CLI uninstall subcommand. |
| `update` | CLI update subcommand. |
| `search` | CLI search subcommand. |
| `list` | CLI list subcommand. |
| `info` | CLI info subcommand. |
| `help` | CLI help subcommand. |
| `version` | CLI version flag. |

Reserved names are enforced at catalog ingestion time. A skill whose `name` collides with a reserved name is rejected.

### Identity uniqueness

A skill key (`<namespace>/<name>`) must be unique within a catalog. Two skills with the same key but different sources conflict; the first registered wins, and later registrations are rejected until the conflict is resolved.

## Versioning

### SemVer

Skills use [SemVer 2.0](https://semver.org/) (`MAJOR.MINOR.PATCH`). The `version` field in `skill.yaml` is the single source of truth for a skill's version.

Pre-release and build metadata suffixes (e.g. `1.0.0-alpha.1`, `2.0.0+20260101`) are allowed but must conform to the SemVer 2.0 grammar.

### What counts as a breaking change (MAJOR)

A change is **breaking** if a downstream consumer that depends on the skill must update their configuration, scripts, or dependency constraints to continue working after the upgrade. All of the following are breaking changes:

| Category | Examples |
|----------|----------|
| **Entry point** | Changing `entrypoint` to a different file. Removing the entry point. |
| **Materials** | Renaming or removing a material path. Changing a material's `type` (e.g. `script` → `prompt`). |
| **Dependencies** | Narrowing a dependency version constraint. Removing a required dependency. |
| **Manifest schema** | Removing a required field. Changing a field's type or constraints in an incompatible way. |
| **License** | Changing the license. License changes affect downstream compliance obligations. |
| **Behaviour contract** | Changing the expected inputs, outputs, or side effects of the entry point in a way that existing callers would break. |

```text
Before:                    After:                     Bump:
entrypoint: run.sh         entrypoint: main.sh        MAJOR (1.0.0 → 2.0.0)
materials:                 materials:
  - path: prompts/a.md       - path: prompts/b.md     MAJOR (1.0.0 → 2.0.0)
  type: prompt               type: prompt             (a.md renamed to b.md)
dependencies:              dependencies:
  - name: git-helpers        - name: git-helpers      MAJOR (1.0.0 → 2.0.0)
    version: ">=1.0.0"         version: ">=2.0.0"    (constraint narrowed)
```

### What counts as a new feature (MINOR)

A change is a **minor** version bump when it adds new, backward-compatible functionality:

| Category | Examples |
|----------|----------|
| **Materials** | Adding a new material without removing or renaming existing ones. |
| **Manifest fields** | Adding a new optional field to `skill.yaml` that consumers can ignore. |
| **Dependencies** | Adding a new optional dependency. Expanding a version constraint (e.g. `>=1.0.0` → `>=1.0.0 \|\| >=2.0.0`). |
| **Tags / categories** | Adding new tags or categories. |
| **New behaviour** | Adding a new capability that does not change or remove existing behaviour. |

```text
Before:                    After:                     Bump:
materials:                 materials:
  - path: prompts/a.md       - path: prompts/a.md     MINOR (1.0.0 → 1.1.0)
    type: prompt               type: prompt           (new material added)
                              - path: prompts/b.md
                                type: prompt
```

### What counts as a fix (PATCH)

A change is a **patch** version bump when it corrects behaviour without adding features or breaking compatibility:

| Category | Examples |
|----------|----------|
| **Description** | Updating the description string. |
| **Materials** | Fixing a bug in a script or prompt without changing the material's declared interface. |
| **Metadata** | Adjusting tags, categories, homepage, or author fields. |
| **Documentation** | Updating `README.md` or inline comments within materials. |
| **Non-functional changes** | Reformatting prompts, adjusting whitespace, fixing typos. |

```text
Before:                    After:                     Bump:
description: Reviews PRs.  description: Reviews pull  PATCH (1.0.0 → 1.0.1)
                            requests for correctness.

tags:                      tags:                      PATCH (1.0.0 → 1.0.1)
  - code-review              - code-review            (tag added)
                             - security
```

### Version bump decision table

| Change | Bump |
|--------|------|
| Entry point changed or removed | MAJOR |
| Material renamed, removed, or type changed | MAJOR |
| Dependency constraint narrowed | MAJOR |
| Dependency removed | MAJOR |
| License changed | MAJOR |
| Behaviour contract changed incompatibly | MAJOR |
| Material added | MINOR |
| New optional dependency added | MINOR |
| Dependency constraint expanded | MINOR |
| New optional manifest field | MINOR |
| Tags or categories added | MINOR |
| Description updated | PATCH |
| Bug fix (no interface change) | PATCH |
| Tag/category removed or adjusted | PATCH |
| Documentation or typo fix | PATCH |

## Deprecation and renaming

### Deprecation

A skill author may deprecate a skill by adding the optional `deprecated` field to `skill.yaml`:

```yaml
deprecated:
  message: Use example/better-review instead.
  replacement: example/better-review
```

| Field | Required | Type | Purpose |
|-------|----------|------|---------|
| `message` | yes | string, 1–500 chars | Explanation for consumers about why the skill is deprecated and what action to take. |
| `replacement` | no | string, `<namespace>/<name>` format | The skill key of the recommended replacement, if one exists. |

Deprecated skills:
- Continue to work for existing installations.
- Are hidden from default catalog listings.
- Show a warning when installed or updated.
- May be removed from the catalog after a **six-month** deprecation period.

### Renaming

A skill cannot be renamed in place. To rename a skill:

1. Create a new skill with the desired `<namespace>/<name>`.
2. Deprecate the old skill, setting `replacement` to the new skill key.
3. After the deprecation period, the old skill may be removed.

This preserves backward compatibility for consumers pinned to the old identity and gives them a clear migration path.

## Reference syntax

### Full reference

A skill is referenced in install, update, and dependency declarations using the syntax:

```
<namespace>/<name>@<version>
```

**Examples:**

```text
example/code-review@1.2.0
example/git-helpers@2.0.0
my-org/security-linter@0.5.0-alpha.1
```

### Short forms

| Form | Meaning | Example |
|------|---------|---------|
| `<namespace>/<name>` | Latest available version of the skill. | `example/code-review` |
| `<namespace>/<name>@<version>` | Exact version. | `example/code-review@1.2.0` |
| `<namespace>/<name>@latest` | Explicit latest (equivalent to omitting the version). | `example/code-review@latest` |

### Version specifiers in dependencies

Within `skill.yaml` `dependencies`, version constraints use [node-semver range syntax](https://github.com/npm/node-semver#ranges):

```yaml
dependencies:
  - name: git-helpers
    version: ">=1.2.0 <2.0.0"
  - name: code-review
    version: "^1.0.0"
  - name: security-linter
    version: "~1.2.3"
```

The reference syntax (`<namespace>/<name>@<version>`) is used in CLI commands. Version ranges (`>=1.0.0 <2.0.0`) are used in dependency declarations. The two syntaxes serve different purposes and are not interchangeable.

### Installer contract

The installer resolves a reference into a concrete skill version by:

1. Parsing `<namespace>/<name>` from the reference.
2. Resolving the version: if `@<version>` is an exact SemVer, use it directly; if omitted or `@latest`, select the highest available version from the catalog.
3. Fetching the skill from its catalog source.
4. Placing it at `~/.claude/skills/<namespace>/<name>/`.

Version range resolution in dependencies is the installer's responsibility and is defined in the installer specification (separate milestone).

## Validation summary

| Rule | Constraint |
|------|------------|
| `namespace` format | `^[a-z][a-z0-9-]*$`, 1–64 chars |
| `name` format | `^[a-z][a-z0-9-]*$`, 1–64 chars (see manifest schema) |
| Skill key format | `<namespace>/<name>` |
| Reserved namespaces | `claude`, `anthropic`, `system` |
| Reserved names | `install`, `uninstall`, `update`, `search`, `list`, `info`, `help`, `version` |
| Version format | SemVer 2.0 (`MAJOR.MINOR.PATCH`) |
| Reference syntax | `<namespace>/<name>@<version>` |
| Deprecation period | 6 months minimum |

## Guidance

- **Namespace is context, not content.** The namespace never appears in `skill.yaml`. It is determined by where the skill lives in the repository or what the user specifies at install time. This keeps skills relocatable: the same skill package can be published under different namespaces without modifying the manifest.
- **When in doubt, bump the higher component.** If a change might be breaking, bump MAJOR. Conservative versioning prevents accidental breakage. A contributor who cannot decide between MINOR and PATCH should choose MINOR.
- **The reference syntax is the public interface.** Every tool (CLI, installer, web UI, CI) uses `<namespace>/<name>@<version>` as the canonical way to name a skill and version. The installer milestone must consume this specification.
- **Deprecation is not deletion.** Deprecated skills remain installable for existing consumers. The deprecation period gives consumers time to migrate before the skill is removed from the catalog.

## Cross-references

- **[Skill manifest schema](skill-manifest-schema.md):** Defines the `name`, `version`, and `deprecated` fields in `skill.yaml`. The identity rules in this document build on those field definitions.
- **[Skill directory layout](skill-directory-layout.md):** Defines how `<namespace>/<name>` maps to the `skills/` directory tree and the install target `~/.claude/skills/<namespace>/<name>/`.
- **[Catalog index format](catalog-index-format.md):** Defines how the skill key appears in `catalog.json` entries and how version and manifest hash are recorded.
- **[Marketplace repository layout](marketplace-repository-layout.md):** Defines where `skills/<namespace>/<name>/` directories live in the repository.
