# Bash Constraints

The canonical constraints that apply to every Bash script in the skills marketplace tooling. The Claude CLI drives tools from non-interactive Bash scripts — this document defines what that means and what rules follow from it.

Every marketplace tool (`scripts/catalog/`, `scripts/installer/`, and future additions) must comply with these constraints. A reviewer evaluating a new tool should be able to use this document as a checklist for non-interactive correctness.

## No TTY assumptions

Marketplace scripts execute in CI pipelines, in `claude` CLI invocations, and in headless environments. No script may assume a terminal is attached.

### Forbidden constructs

| Construct | Rule | Rationale |
|-----------|------|-----------|
| `read` | Must not be used. | Blocks forever if stdin is not a terminal. |
| `read -p` | Must not be used. | Prompts for input; no terminal to read from. |
| `select` | Must not be used. | Interactive menu; requires terminal. |
| Terminal control sequences (`\033[`, `\e[`, `tput`) | Must not be used. | Produces garbage output when no terminal is attached. |
| `less`, `more` | Must not be used. | Pagers require terminal interaction. |
| `/dev/tty` | Must not reference it. | No guarantee a controlling terminal exists. |
| `stty` | Must not be used. | Terminal configuration; meaningless without a terminal. |

### Acceptable stdin usage

Reading from stdin is allowed when stdin is a pipe or redirect, not a terminal:

```bash
# Allowed: consuming piped input
jq '.entries' < /dev/stdin

# Allowed: accepting input from a file argument
local file="${1:?missing file argument}"
jq '.entries' < "$file"
```

## Strict mode

Every script must start with the strict-mode preamble:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| Option | What it enforces |
|--------|-----------------|
| `-e` | Exit immediately on any non-zero exit code. |
| `-u` | Treat unset variables as errors. |
| `-o pipefail` | Return the exit code of the first failing command in a pipeline. |

Scripts must not disable these options except for a specific, documented reason (e.g., a `grep` that legitimately may not match, scoped to a single line with `|| true`).

## Deterministic outputs

Two runs of the same tool against the same inputs must produce byte-for-byte identical output.

### Stable ordering

When a tool outputs a list or map, the ordering must be deterministic:

- **JSON objects:** Sort keys alphabetically. Use `jq --sort-keys` or construct objects with keys inserted in sorted order.
- **Arrays:** Sort elements alphabetically using `LC_ALL=C` collation.
- **File enumeration:** Sort with `sort -z` (null-delimited) or `sort` before processing.

### Machine-readable formats

When a tool's primary output is consumed by another program, prefer structured, machine-readable formats:

| Format | When to use |
|--------|-------------|
| JSON (`jq`) | Structured data, API-like output. The catalog index uses this. |
| Null-delimited lines | File paths (safe with spaces, newlines in names). |
| Newline-delimited lines | Simple lists where values are guaranteed to not contain newlines. |

### Non-determinism sources to avoid

| Source | Mitigation |
|--------|-----------|
| `find` without `sort` | Always pipe `find` output through `sort` before processing. |
| `mktemp` in output | Only use `mktemp` for internal scratch files; never embed them in primary output. |
| Timestamps | If a generated file includes a timestamp, use `SOURCE_DATE_EPOCH` for reproducibility. |
| Hashes of unordered data | Sort before hashing. |

## Exit codes

Every marketplace script uses a reserved set of exit codes with consistent semantics across tools. A caller can interpret the exit code without knowing the specific tool that produced it.

### Reserved exit codes

| Code | Name | Meaning |
|------|------|---------|
| `0` | `SUCCESS` | Completed successfully. No errors. |
| `1` | `GENERAL_ERROR` | An error occurred that does not fit a more specific code. |
| `2` | `INVALID_USAGE` | The invocation was malformed: missing required argument, unknown flag, invalid flag value. |
| `3` | `DEPENDENCY_MISSING` | A required external tool (`jq`, `yq`, `sha256sum`) is not available. |
| `4` | `INPUT_INVALID` | Input data is malformed or fails validation (e.g., invalid `skill.yaml`, malformed JSON). |
| `5` | `RESOURCE_UNAVAILABLE` | A required file, network resource, or service is not reachable. |
| `6` | `CONFLICT` | The requested operation conflicts with existing state (e.g., skill already installed, duplicate key). |
| `7` | `AUTH_FAILURE` | Authentication or authorisation failed. Reserved for future use. |

### Exit code rules

- **No redefinition.** These codes have the same meaning in every marketplace tool. A script must not use exit code `3` to mean something other than a missing dependency.
- **Specific over general.** Use the most specific code that applies. Exit code `1` is a last resort.
- **Documented surface.** Only codes `0`–`7` are reserved. Codes `8`–`127` are free for tool-specific use but must be documented in that tool's own scope.
- **`$?` is ephemeral.** Always capture exit codes explicitly when branching on them: `rc=$?` before testing.

### Usage pattern

```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed" >&2
  exit 3
fi
```

## Idempotence

Every command must be safe to re-run. Running a tool twice with the same inputs must produce the same result as running it once.

### Requirements

| Scenario | Idempotent behaviour |
|----------|---------------------|
| Generate an index when `index/catalog.json` already exists. | Overwrite it with identical content. |
| Install a skill that is already installed. | Exit with code `6` (CONFLICT) and a clear message, or reinstall cleanly if `--force` is given. |
| Run a generator against an empty `skills/` directory. | Produce a valid empty catalog. |
| Run a generator against an unchanged `skills/` directory. | Produce byte-for-byte identical output. |

### Explicit over destructive

A tool must not silently overwrite or delete user data. Destructive operations require an explicit flag (`--force`, `--overwrite`). Without that flag, the tool exits with an error and a descriptive message.

```bash
if [ -f "$INDEX_FILE" ] && [ "${FORCE:-0}" -ne 1 ]; then
  echo "index/catalog.json already exists. Use --force to overwrite." >&2
  exit 6
fi
```

## Output modes

Every tool supports three output modes selected by mutually exclusive flags. The default mode differs by command but is always documented.

| Flag | Mode | Behaviour |
|------|------|-----------|
| `--quiet` / `-q` | Quiet | Produce no stdout output. Only exit code signals success or failure. stderr may still carry diagnostics. |
| (default) | Normal | Produce primary output on stdout. Diagnostics on stderr. |
| `--verbose` / `-v` | Verbose | Same as normal, plus progress messages and diagnostic detail on stderr. |
| `--json` | JSON | Primary output is JSON on stdout. Diagnostics on stderr. Mutually exclusive with `--quiet`. |

### Mode precedenec

When multiple output flags are provided, the last one wins. This follows the convention used by `curl`, `grep`, and other standard Unix tools:

```bash
tool --quiet --verbose   # verbose mode (last wins)
tool --json --quiet      # quiet mode (last wins)
```

### JSON mode

JSON output must be valid, parseable JSON. Use `jq` to construct it — never concatenate strings:

```bash
# Correct: jq constructs valid JSON
jq -n --arg key "$key" --arg version "$version" '{key: $key, version: $version}'

# Wrong: string concatenation, breaks on special characters
echo "{\"key\": \"$key\", \"version\": \"$version\"}"
```

JSON output is written to stdout. A consumer must be able to `tool --json | jq .` without filtering stderr.

## Logging convention

stdout and stderr have distinct, non-overlapping purposes across all marketplace tooling.

| Stream | Purpose | Example |
|--------|---------|---------|
| **stdout** | Primary output of the command. Machine-readable where applicable. | Catalog JSON, query result, success confirmation. |
| **stderr** | Diagnostics, progress, warnings, errors. Human-readable. | "Generating catalog...", "ERROR: missing version field". |

### Rules

- **No diagnostics on stdout.** A consumer piping stdout to `jq` or a file must not receive log messages.
- **No primary output on stderr.** A caller capturing stderr separately must not miss the tool's result.
- **Error messages include context.** An error on stderr must name the file, field, or value that caused it.
- **Progress goes to stderr.** Even in normal mode, "Generating index..." and similar messages write to stderr.

### Example

```bash
# Correct: result on stdout, diagnostics on stderr
echo "Catalog index written to $INDEX_FILE" >&2
cat "$INDEX_FILE"  # stdout is the primary output

# Wrong: diagnostic on stdout pollutes the result
echo "Catalog index written to $INDEX_FILE"
cat "$INDEX_FILE"
```

## Precedence: environment variables vs flags

When a tool accepts a configuration value from both an environment variable and a command-line flag, the flag wins. This follows the principle that explicit invocation options override ambient configuration.

### Precedence order (highest to lowest)

1. **Command-line flag** (e.g., `--skills-dir /path`)
2. **Environment variable** (e.g., `SKILLS_DIR=/path`)
3. **Default** (hard-coded in the script)

### Conventions for each tool

Environment variables follow a naming convention that scopes them to the tool:

| Script | Environment variable prefix |
|--------|-----------------------------|
| `scripts/catalog/generate-index.sh` | `SKILLS_DIR`, `INDEX_DIR` |
| `scripts/installer/` (future) | `INSTALL_` prefix |

### Pattern

```bash
SKILLS_DIR="${SKILLS_DIR:-$REPO_ROOT/skills}"     # env or default
SKILLS_DIR="${1:-$SKILLS_DIR}"                     # flag overrides env
```

Or, when using named flags:

```bash
# Parse flags, then:
SKILLS_DIR="${SKILLS_DIR:-$REPO_ROOT/skills}"     # default
SKILLS_DIR="${flag_skills_dir:-$SKILLS_DIR}"       # env overrides default
# (flag value, if set in parsing, already won)
```

## Reference and discovery

### Apply to existing tooling

The catalog index generator (`scripts/catalog/generate-index.sh`) already follows these constraints:

- Strict mode preamble (`set -euo pipefail`)
- Idempotent (byte-for-byte identical on re-run)
- stdout for primary output, stderr for diagnostics
- Deterministic output (sorted keys, sorted arrays)
- Uses `mktemp` only for scratch files
- Environment variables (`SKILLS_DIR`, `INDEX_DIR`) with defaults
- No TTY assumptions (no `read`, no prompts)

### Evaluation checklist

When reviewing a new marketplace tool, verify:

- [ ] Starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- [ ] No `read`, `select`, terminal escapes, or `/dev/tty`.
- [ ] stdout is primary output; stderr is diagnostics only.
- [ ] Exit codes use the reserved table (0–7) with correct semantics.
- [ ] Safe to re-run: produces identical output or fails explicitly with a clear message.
- [ ] Supports `--quiet`, `--verbose`, `--json` where applicable.
- [ ] Environment variables follow the tool-specific prefix convention.
- [ ] Flags override environment variables; environment variables override defaults.
- [ ] Output is deterministic: sorted keys, sorted arrays, no embedded timestamps or temp paths.

## Cross-references

- **[Marketplace repository layout](marketplace-repository-layout.md):** Defines `scripts/<tool>/` and `tests/<tool>/` directories. Every script in those directories must comply with this document.
- **[Catalog index format](catalog-index-format.md):** The catalog generator follows these constraints. JSON output convention, stable ordering, and hashing strategy are concrete applications of the rules defined here.
- **[Skill directory layout](skill-directory-layout.md):** Installer scripts must follow these constraints when placing or removing skills.
- **[Skill manifest schema](skill-manifest-schema.md):** Validation scripts in the tooling must follow the exit code conventions (`INPUT_INVALID` for malformed manifests).
