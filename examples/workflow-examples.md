# Bash workflow examples

Copy-pasteable Bash recipes for using the skills marketplace in scripts, CI
pipelines, and devcontainer setup. Every recipe is non-interactive (safe in
headless environments) and idempotent (safe to re-run).

**Prerequisites:** `bash`, `git`, `jq`, `yq`

---

## Recipe 1: One-liner install

Install the latest version of a skill in a single command.

```bash
bash scripts/installer/install.sh \
  --from https://github.com/example/skills-marketplace.git \
  example/code-review
```

With a specific version:

```bash
bash scripts/installer/install.sh \
  --from https://github.com/example/skills-marketplace.git \
  example/code-review@1.2.0
```

The installer resolves `@latest` automatically when no version is given.
Already-installed skills are skipped (exit code 0). Use `--force` to overwrite.

---

## Recipe 2: Install in CI (Gitea Actions)

Add this step to your Gitea Actions workflow to install a skill during CI:

```yaml
- name: Install marketplace skill
  env:
    CLAUDE_SKILLS_INSTALL_TARGET: /tmp/skills
  run: |
    set -euo pipefail
    bash scripts/installer/install.sh \
      --from . \
      example/hello-world
```

To use a remote marketplace instead of a local checkout, add a clone step:

```yaml
- name: Clone marketplace
  run: git clone --depth 1 https://github.com/example/skills-marketplace.git /tmp/marketplace

- name: Install skill
  env:
    CLAUDE_SKILLS_INSTALL_TARGET: /tmp/skills
  run: |
    set -euo pipefail
    bash /tmp/marketplace/scripts/installer/install.sh \
      --from /tmp/marketplace \
      example/hello-world
```

The `CLAUDE_SKILLS_INSTALL_TARGET` variable keeps installs out of `$HOME`
when the CI runner user does not have a home directory.

### Full CI workflow example

```yaml
name: ci

on: [push]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          wget -q https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -O /usr/local/bin/yq
          chmod +x /usr/local/bin/yq

      - name: Install skill
        env:
          CLAUDE_SKILLS_INSTALL_TARGET: /tmp/skills
        run: |
          bash scripts/installer/install.sh --from . example/hello-world

      - name: Verify install
        run: |
          test -f /tmp/skills/example/hello-world/skill.yaml
          echo "Skill installed successfully"
```

---

## Recipe 3: Devcontainer postCreate

Add skill installation to your devcontainer's `postCreateCommand`.

Create a `postcreate.sh` script (see [`examples/postcreate.sh`](postcreate.sh)):

```bash
#!/usr/bin/env bash
set -euo pipefail

MARKETPLACE="${1:?missing marketplace URL or path}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/installer/install.sh"

skills=(
  "example/hello-world"
  "example/code-review"
)

for skill in "${skills[@]}"; do
  echo "Installing $skill..."
  bash "$INSTALLER" --from "$MARKETPLACE" "$skill"
done

echo "All skills installed."
```

Reference it in `.devcontainer/devcontainer.json`:

```json
{
  "postCreateCommand": "bash .devcontainer/postcreate.sh https://github.com/example/skills-marketplace.git"
}
```

Or install directly in `postCreateCommand` without a wrapper script:

```json
{
  "postCreateCommand": "bash scripts/installer/install.sh --from . example/hello-world && bash scripts/installer/install.sh --from . example/code-review"
}
```

---

## Recipe 4: Upgrade all installed skills

Use [`examples/upgrade-all.sh`](upgrade-all.sh) to upgrade every installed skill
to the latest version in the catalog:

```bash
bash examples/upgrade-all.sh --from https://github.com/example/skills-marketplace.git
```

The script discovers installed skills under `~/.claude/skills/`, looks up each
one in the catalog, and installs the latest version. Already-current skills are
skipped; outdated skills are overwritten.

To upgrade from a local marketplace checkout:

```bash
bash examples/upgrade-all.sh --from .
```

### How it works

The script discovers installed skills under `$INSTALL_TARGET`, looks up each
one in the catalog, and installs the latest version with `--force`. If the
installed version is already current, the installer exits 0 with an "already
installed" message and the skill is skipped. Errors on individual skills are
reported but do not stop the batch.

See [`examples/upgrade-all.sh`](upgrade-all.sh) for the full implementation.

---

## Configuration quick reference

All examples use the [installer configuration](../scripts/installer/config.sh)
precedence chain: CLI flag > environment variable > config file > default.

| Key | Env variable | Default |
|-----|-------------|---------|
| `INSTALL_TARGET` | `CLAUDE_SKILLS_INSTALL_TARGET` | `~/.claude/skills` |
| `MARKETPLACE_URL` | `CLAUDE_SKILLS_MARKETPLACE_URL` | *(empty)* |
| `CACHE_DIR` | `CLAUDE_SKILLS_CACHE_DIR` | `~/.cache/claude-skills` |

Set defaults in `~/.config/claude-skills/config`:

```ini
MARKETPLACE_URL=https://github.com/example/skills-marketplace.git
```

Then the one-liner shortens to:

```bash
bash scripts/installer/install.sh example/code-review
```
