# ADR 0001: Installer Implementation Language

## Status

Accepted (2026-06-14)

## Context

The skills marketplace needs an installer CLI that resolves skill keys to
directories, fetches skill packages, and places them at
`~/.claude/skills/<namespace>/<name>/`. The installer is the second
marketplace tool after the catalog generator.

The repository preferences default to C# .NET 8 for CLI tools
(`.claude/preferences/technology-choices.md`). This ADR records the
decision to deviate from that default for the installer.

## Decision

**Implement the installer in Bash, with `git`, `jq`, and `yq` as the
only runtime dependencies beyond a POSIX shell.**

The installer source lives at `scripts/installer/`. Tests live at
`tests/installer/`, mirroring the existing `scripts/catalog/` and
`tests/catalog/` pattern. Both locations are already defined in the
marketplace repository layout specification.

## Rationale

**Portability.** Every Claude Code user already has bash, git, and jq.
Adding .NET or Node.js as an installer prerequisite would gate users who
have not installed those runtimes. A Bash installer runs on macOS, Linux,
and WSL without any additional install step.

**Zero new dependency surface.** The devcontainer, CI runner, and local
development environment already carry bash, git, jq, and yq. The
installer adds nothing to install.

**Pre-existing infrastructure.** The catalog generator
(`scripts/catalog/generate-index.sh`) is Bash. The Bash constraints
document (`docs/specs/bash-constraints.md`) defines strict mode,
deterministic output, reserved exit codes, output modes, idempotence,
and logging conventions for every marketplace tool. The test harness
(`tests/catalog/test-generate-index.sh`) demonstrates the Bash test
pattern. Choosing Bash for the installer reuses all of this.

**Scope fit.** The installer's core work is file operations, git clones,
YAML/JSON parsing, and directory placement — all well-served by bash +
git + jq + yq. Each subcommand (install, remove, list, update) can be a
separate script, keeping individual files under 50–100 lines.

## Trade-offs

| Trade-off | Mitigation |
|-----------|-----------|
| No type safety. Bash does not catch type errors at authoring time. | Strict mode (`set -euo pipefail`), the reserved exit code table, and deterministic-output tests catch whole categories of runtime errors. The Bash constraints document is a checklist reviewers apply to every new script. |
| Verbose error handling. Bash error paths are manual and repetitive. | Reserve a shared helper script (`_lib.sh`) for common patterns (arg parsing, dependency checks, output mode dispatch). Only introduce this when the second subcommand is written — not prematurely. |
| Harder to build complex data structures. | The catalog is JSON (`jq`). Manifests are YAML (`yq`). The installer processes structured data through these tools rather than building it in Bash. |
| Not the preference default. C# is the documented preference for CLI tools. | The deviation criteria in `technology-choices.md` explicitly cover "very simple scripts" and cases where the preference runtime is not available in the target environment. This is both. |

## Deviation from technology preferences

Per `.claude/preferences/technology-choices.md`:

- **Preference:** C# .NET for CLI tools.
- **Deviation:** Bash for the installer.
- **Reason:** The installer must run in user environments that may not
  have .NET installed. Bash + git + jq is the common subset available on
  every platform Claude Code supports. This matches the documented
  deviation case for "very simple scripts" where a compiled runtime is
  an unreasonable prerequisite.

## Required runtime dependencies

| Dependency | Minimum version | Purpose |
|-----------|----------------|---------|
| `bash` | 4.0+ | Script interpreter |
| `git` | 2.0+ | Repository cloning, fetching |
| `jq` | 1.6+ | JSON parsing (catalog queries) |
| `yq` | 4.0+ | YAML parsing (manifest reading) |

These are the same dependencies as the catalog generator. No new
tooling is required.

## Consequences

- Downstream installer issues reference this ADR and can begin coding
  without re-litigating the language choice.
- All installer scripts must comply with `docs/specs/bash-constraints.md`
  (strict mode, no TTY, deterministic output, reserved exit codes,
  idempotence, output modes).
- If a future subcommand genuinely exceeds Bash's limits (e.g. HTTP with
  retry logic, complex dependency resolution), that subcommand can be
  extracted into a separate tool with its own ADR. The installer remains
  Bash-first.
