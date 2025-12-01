# CODEMAP — {{project-name}}

Repository-specific structure, technology stack, and implementation patterns.

## Purpose

<!-- One paragraph describing what this repository does, what it produces, and who consumes it. -->

## Top-level layout

```
{{project-name}}/
├── {{dir-1}}/       # {{purpose of dir-1}}
├── {{dir-2}}/       # {{purpose of dir-2}}
├── {{dir-3}}/       # {{purpose of dir-3}}
├── CODEMAP.md       # This file
├── README.md        # Project overview
└── <!-- additional top-level items -->
```

<!-- Each top-level directory should have a one-line purpose comment. If the full layout specification lives in a separate document, link to it here. -->

## Technology stack

| Layer | Technology in use | Notes |
|-------|------------------|-------|
| {{layer-1}} | {{technology}} | {{why this technology, version constraints}} |
| {{layer-2}} | {{technology}} | {{why this technology, version constraints}} |

### Deviations from technology preferences

<!-- If the repository-wide preferences (defined in .claude/preferences/) differ from the actual technology in use, document each deviation with rationale, trade-offs accepted, and mitigations. -->

#### {{deviation-summary}}

**Deviation from Preference:** {{what preference is being deviated from and why.}}

**Rationale:** {{why this deviation is the right choice for this project.}}

**Trade-offs Accepted:** {{what is given up by not following the preference.}}

**Mitigation:** {{how the trade-offs are addressed.}}

## Build and test

**Build:** {{command to build the project. Dependencies: list them.}}

**Test:** {{command to run tests.}}

**CI:** {{what CI runs on push/PR, where the config lives.}}

**Local validation:**
```bash
{{commands a contributor runs before pushing}}
```

## Architecture decisions

<!-- Table listing ADRs with one-line summaries. -->

| ADR | Decision |
|-----|----------|
| [0001-{{title}}.md](docs/decisions/0001-{{title}}.md) | {{one-line summary of the decision}} |

## Architecture patterns

<!-- 3-5 bullet points naming the key architectural patterns used in this repository and why each exists. -->

- **{{pattern-name}}:** {{what the pattern is and why it exists in this project.}}

## Key invariants

<!-- Hard rules that must not be violated. These are constraints that keep the repository consistent and correct. -->

- {{invariant-1}}
- {{invariant-2}}
