# Skill Authoring Guide

A step-by-step walkthrough for designing, authoring, and publishing a new skill in the marketplace. This guide produces a working skill when followed end-to-end. When in doubt about a field or rule, consult the referenced specification — the specs are authoritative; this guide is a map.

## Before you start

Pick a **namespace** and a **name** for your skill. The combination `<namespace>/<name>` is the skill's universal identifier — it appears in repository paths, catalog entries, install commands, and on disk.

A namespace is typically your GitHub username, your organisation name, or a project name. For this walkthrough we will use `my-org` and a skill called `hello`. The skill key will be `my-org/hello`.

**What to check:**
- The namespace must match `^[a-z][a-z0-9-]*$` (kebab-case, 1–64 characters). See [skill identity spec](specs/skill-identity-and-versioning.md#namespace).
- The name must match the same pattern, plus it must not be one of the [reserved names](specs/skill-identity-and-versioning.md#reserved-names) (`install`, `uninstall`, `update`, `search`, `list`, `info`, `help`, `version`).
- The namespace must not be one of the [reserved namespaces](specs/skill-identity-and-versioning.md#reserved-namespaces) (`claude`, `anthropic`, `system`).

---

## Step 1: Create the skill directory

Every skill lives under `skills/<namespace>/<name>/`. Create your directory:

```bash
mkdir -p skills/my-org/hello
```

The directory name `hello` is the skill's `name` — it must match the `name` field you will write in `skill.yaml`.

---

## Step 2: Write the manifest (`skill.yaml`)

Create `skills/my-org/hello/skill.yaml` with the required fields.

### Minimal manifest

```yaml
name: hello
version: 1.0.0
description: A minimal skill that greets the user.
entrypoint: SKILL.md

materials:
  - path: SKILL.md
    type: prompt
    description: Primary skill instructions and greeting behaviour
```

**What each field means:**

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | yes | Machine-readable identifier. 1–64 chars, kebab-case (`^[a-z][a-z0-9-]*$`). |
| `version` | yes | [SemVer 2.0](https://semver.org/) (`MAJOR.MINOR.PATCH`). Start at `1.0.0`. |
| `description` | yes | One-line summary (1–200 chars). Shown in catalog listings and search results. |
| `entrypoint` | yes | Relative path to the file invoked at runtime. Must live within the skill directory. |
| `materials` | yes | Array declaring every file the skill provides. At least one entry required. |

The full schema with all optional fields (`tags`, `categories`, `homepage`, `license`, `authors`, `dependencies`) is in the [manifest schema spec](specs/skill-manifest-schema.md).

### Adding optional fields

Here is the same manifest with optional metadata:

```yaml
name: hello
version: 1.0.0
description: A minimal skill that greets the user.
entrypoint: SKILL.md

materials:
  - path: SKILL.md
    type: prompt
    description: Primary skill instructions and greeting behaviour

tags:
  - greeting
  - onboarding

categories:
  - development

license: MIT

authors:
  - name: Your Name
    email: you@example.com
```

**Tag rules (quick reference):**
- Lowercase kebab-case, 1–30 chars each (`^[a-z][a-z0-9-]*$`)
- 0–20 items maximum
- No leading/trailing hyphens, no consecutive hyphens

**Category rules (quick reference):**
- Must be from the [reserved vocabulary](specs/skill-manifest-schema.md#reserved-categories): `review`, `planning`, `docs`, `behaviours`, `development`, `testing`, `deployment`, `maintenance`
- 0–10 items maximum

---

## Step 3: Write the primary instructions (`SKILL.md`)

`SKILL.md` is the file the runtime loads when the skill is invoked. It contains the prompt or instructions that define the skill's behaviour.

Create `skills/my-org/hello/SKILL.md`:

```markdown
# Hello Skill

When invoked, greet the user warmly by name if the user's name is known, or generically if it is not.

## Behaviour

1. Determine whether the user's name is available from context.
2. If yes: respond with "Hello, <name>! How can I help you today?"
3. If no: respond with "Hello! How can I help you today?"

## Constraints

- Keep the greeting brief (one sentence).
- Do not ask for the user's name if it is not already known.
```

`SKILL.md` is a material like any other — it must appear in the manifest's `materials` array with `type: prompt`. If your skill uses a wrapper script as the entrypoint instead, list both the script and `SKILL.md` as materials (see [directory layout spec](specs/skill-directory-layout.md#skillmd-declaration)).

---

## Step 4: Add more materials (if needed)

The minimal `hello` skill only needs a `SKILL.md`. Most real skills need more. Here is how to organise additional files.

### Material conventions

Choose the right sub-directory and material type for each file:

| If your file is… | Put it in… | Declare `type` as… |
|------------------|------------|---------------------|
| A prompt or instruction template | `prompts/` | `prompt` |
| An executable script (bash, Python) | `scripts/` | `script` |
| A file that undergoes variable substitution | `templates/` | `template` |
| A read-only reference document | `examples/` | `reference` |
| A static file (image, icon, data) | `assets/` | `other` |

These are conventions from the [directory layout spec](specs/skill-directory-layout.md#sub-directories). The manifest's `materials` array is authoritative — sub-directories exist for organisation.

### Example: extending hello with a helper script

```
skills/my-org/hello/
├── skill.yaml
├── SKILL.md
├── README.md
└── scripts/
    └── greet.sh
```

`skill.yaml` would declare both materials:

```yaml
entrypoint: scripts/greet.sh

materials:
  - path: SKILL.md
    type: prompt
    description: Primary skill instructions and greeting behaviour
  - path: scripts/greet.sh
    type: script
    description: Entry-point wrapper that loads the greeting prompt
```

### Naming rules

- All filenames: kebab-case (`^[a-z][a-z0-9-]*$`), matching the manifest `name` pattern.
- Extensions must reflect the format: `.sh`, `.md`, `.json`, `.py`, `.yaml`, `.svg`.
- No spaces, no underscores, no uppercase in filenames.
- No nested sub-directories (maximum depth: one level from the skill root).

Full naming rules are in the [directory layout spec](specs/skill-directory-layout.md#naming-rules).

---

## Step 5: Write a README (optional)

`README.md` is for humans — it explains what the skill does, how to use it, and any setup notes. The runtime does not load it.

Create `skills/my-org/hello/README.md`:

```markdown
# hello

A minimal example skill that greets the user.

## Usage

Invoke the skill and it will respond with a greeting.

## Author

Your Name <you@example.com>
```

---

## Step 6: Version correctly

Every change to a skill after its first release needs a version bump. Use this checklist to decide which component to increment:

| Change | Bump |
|--------|------|
| Entry point changed or removed | MAJOR (`2.0.0`) |
| Material renamed, removed, or type changed | MAJOR |
| Dependency constraint narrowed | MAJOR |
| Dependency removed | MAJOR |
| License changed | MAJOR |
| Behaviour contract changed incompatibly | MAJOR |
| New material added (no removals) | MINOR (`1.1.0`) |
| New optional dependency added | MINOR |
| Dependency constraint expanded | MINOR |
| Tags or categories added | MINOR |
| Description updated | PATCH (`1.0.1`) |
| Bug fix (no interface change) | PATCH |
| Tag/category removed or adjusted | PATCH |
| Documentation or typo fix | PATCH |

**When in doubt, bump the higher component.** If a change might be breaking, bump MAJOR. If you cannot decide between MINOR and PATCH, choose MINOR.

The full versioning rules with rationale are in the [identity and versioning spec](specs/skill-identity-and-versioning.md#versioning).

---

## Step 7: Test locally

Before opening a PR, validate that your skill is well-formed.

### Validate the manifest

Check the required fields are present and look correct:

```bash
FILE="skills/my-org/hello/skill.yaml"

# Required fields
for field in name version description entrypoint materials; do
  if ! grep -q "^${field}:" "$FILE"; then
    echo "MISSING: ${field}"
  else
    echo "  OK: ${field}"
  fi
done

# Name must be kebab-case
NAME=$(grep '^name:' "$FILE" | sed 's/^name: *//')
echo "$NAME" | grep -qE '^[a-z][a-z0-9-]*$' && echo "  OK: name format ($NAME)" || echo "INVALID: name format ($NAME)"

# Version must be SemVer
VER=$(grep '^version:' "$FILE" | sed 's/^version: *//')
echo "$VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+' && echo "  OK: version ($VER)" || echo "INVALID: version ($VER)"

# Materials must have entries
MATCOUNT=$(grep -c '^  - path:' "$FILE" || true)
[ "$MATCOUNT" -ge 1 ] && echo "  OK: materials ($MATCOUNT entries)" || echo "MISSING: materials has no entries"

# Description must be non-empty
DESC=$(grep '^description:' "$FILE" | sed 's/^description: *//')
[ -n "$DESC" ] && echo "  OK: description" || echo "MISSING: description"
```

### Run the catalog generator

Regenerate the index and confirm your skill appears:

```bash
make index
```

Then check that your skill is listed:

```bash
jq '.entries["my-org/hello"]' index/catalog.json
```

Expected output:

```json
{
  "version": "1.0.0",
  "description": "A minimal skill that greets the user.",
  "tags": [],
  "categories": [],
  "path": "skills/my-org/hello",
  "manifest_hash": "sha256:<64-hex-chars>"
}
```

If your skill does not appear, the generator wrote an error to stderr — check for missing or null required fields.

### Run the test suite

```bash
bash tests/catalog/test-generate-index.sh
```

All tests should pass before you open a PR.

---

## Step 8: Open a pull request

Once local validation passes:

1. Commit your skill directory (`skills/my-org/hello/`) and the regenerated `index/catalog.json`:
   ```bash
   git add skills/my-org/hello/ index/catalog.json
   git commit -m "Add my-org/hello skill"
   ```

2. Push your branch and open a PR against `main`.

---

## Reference: complete minimal skill

After following this guide, your skill directory should look like:

```
skills/my-org/hello/
├── skill.yaml      # Manifest with required + optional fields
├── SKILL.md        # Primary skill instructions
└── README.md       # Human-facing overview (optional)
```

And `skill.yaml`:

```yaml
name: hello
version: 1.0.0
description: A minimal skill that greets the user.
entrypoint: SKILL.md

materials:
  - path: SKILL.md
    type: prompt
    description: Primary skill instructions and greeting behaviour

tags:
  - greeting
  - onboarding

categories:
  - development

license: MIT

authors:
  - name: Your Name
    email: you@example.com
```

---

## Where to go next

- **[Skill manifest schema](specs/skill-manifest-schema.md)** — every field in `skill.yaml`, constraints, and validation rules.
- **[Skill directory layout](specs/skill-directory-layout.md)** — file placement, naming rules, sub-directory conventions, and install path.
- **[Skill identity and versioning](specs/skill-identity-and-versioning.md)** — skill key format, reserved names/namespaces, versioning rules, deprecation, and reference syntax.
- **[Catalog index format](specs/catalog-index-format.md)** — how `catalog.json` is structured and how your skill appears to consumers.
- **[Marketplace repository layout](specs/marketplace-repository-layout.md)** — where everything lives in the repository.
- **[Workflow examples](../examples/workflow-examples.md)** — copy-pasteable Bash recipes for CI, devcontainer, and upgrades.
