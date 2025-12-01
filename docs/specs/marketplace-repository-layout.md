# Marketplace Repository Layout

The canonical top-level structure of this repository as a skills marketplace.

## Repository tree

```
skills-marketplace/
├── skills/                   # Skill packages organized by namespace and name
│   └── <namespace>/<name>/   # One directory per skill (per skill-directory-layout spec)
├── index/                    # Generated catalog index files (machine-readable, read-only)
│   └── catalog.json          # Skill catalog index (per catalog-index-format spec)
├── docs/                     # Human-facing documentation: specs, vision, decisions
│   └── specs/                # Specification documents
├── scripts/                  # Tooling source code (service-scoped subdirectories)
│   ├── catalog/              # Catalog index generator
│   └── installer/            # Skill installer
├── tests/                    # Automated tests (mirrors scripts/ structure)
│   ├── catalog/              # Catalog generator tests
│   └── installer/            # Installer tests
├── examples/                 # Example skills and catalog for validation and reference
├── CODEMAP.md                # Repository structure and technology map
├── README.md                 # Project overview
└── VISION.md                 # Project vision and goals
```

## Top-level directory purpose statements

| Directory | Purpose |
|-----------|---------|
| `skills/` | Skill packages, one per `<namespace>/<name>/` directory, each containing a `skill.yaml` manifest and its materials. |
| `index/` | Generated, machine-readable catalog index files. The generator writes here; consumers read from here. |
| `docs/` | Human-facing documentation: specifications, vision, architectural decisions. Not consumed by tooling. |
| `scripts/` | Tooling source code in service-scoped subdirectories (catalog generator, installer). No top-level source files. |
| `tests/` | Automated tests mirroring the `scripts/` structure. No top-level test files. |
| `examples/` | Example skills and a sample catalog index for validation and reference. |

## Directory constraints

### Source-code directories (`scripts/`, `tests/`)

The `scripts/` and `tests/` directories contain no source files directly at the top level. All source code lives in a service subdirectory.

- `scripts/<service>/` — one subdirectory per tool or service (e.g. `catalog/`, `installer/`)
- `tests/<service>/` — mirrors the `scripts/` structure (e.g. `catalog/`, `installer/`)

A new tool (e.g. a validator or a linter) gets its own subdirectory in both `scripts/` and `tests/`:

```
scripts/
├── catalog/
├── installer/
└── validator/          # Future tool
tests/
├── catalog/
├── installer/
└── validator/          # Matching test directory
```

### Content directory (`skills/`)

The `skills/` directory is content, not source code. It is organized by `<namespace>/<name>/` with the layout defined in [skill-directory-layout.md](skill-directory-layout.md). The namespace/name pattern provides the same collision-avoidance and scaling properties as service-scoped directories.

### Generated directory (`index/`)

The `index/` directory holds generated files produced by the catalog index generator. Consumers treat it as read-only. The only writer is the generator tool in `scripts/catalog/`. The index format is defined in [catalog-index-format.md](catalog-index-format.md).

## Tracked content

A fresh checkout of this experiment, before any generator runs, includes:

- The directories shown above
- Example skills and catalogs for validation
- `docs/specs/` with the current specification documents
- `CODEMAP.md`, `README.md`, and `VISION.md`

After the catalog generator runs, `index/catalog.json` exists and reflects the current state of `skills/`.

## Cross-references

- **[Skill identity and versioning](skill-identity-and-versioning.md):** Defines the skill key (`<namespace>/<name>`), SemVer versioning rules, reference syntax, and deprecation policy.
- **[Skill directory layout](skill-directory-layout.md):** Defines the per-skill directory structure under `skills/<namespace>/<name>/`.
- **[Skill manifest schema](skill-manifest-schema.md):** Defines the `skill.yaml` format every skill ships with.
- **[Catalog index format](catalog-index-format.md):** Defines the `catalog.json` schema and generation contract.
- **[Bash constraints](bash-constraints.md):** Defines the non-interactive Bash constraints that every script under `scripts/` and `tests/` must follow. The installer and all future tooling are evaluated against this document.
