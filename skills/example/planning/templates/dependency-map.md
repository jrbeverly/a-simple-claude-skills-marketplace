# Dependency Map: {{feature-name}}

<!--
  Show the ordering of phases and which phases block others. A phase
  that blocks nothing can start immediately. A phase blocked by
  multiple phases must wait for all of them.
-->

```
Phase 1: {{phase-1-name}}
  └─► Phase 2: {{phase-2-name}}
        ├─► Phase 3: {{phase-3-name}}
        └─► Phase 4: {{phase-4-name}}
              └─► Phase 5: {{phase-5-name}}
```

<!--
  Each arrow (►) means "must complete before." Phases on the same
  level (├─► and └─►) can proceed in parallel — neither blocks the
  other. Adjust the diagram to match your plan.
-->

## Blocking relationships

| Phase | Blocks | Blocked by |
|-------|--------|------------|
| Phase 1: {{phase-1-name}} | Phase 2 | — |
| Phase 2: {{phase-2-name}} | Phase 3, Phase 4 | Phase 1 |
| Phase 3: {{phase-3-name}} | — | Phase 2 |
| Phase 4: {{phase-4-name}} | Phase 5 | Phase 2 |
| Phase 5: {{phase-5-name}} | — | Phase 4 |

<!--
  Fill in one row per phase. A phase with no "Blocks" means nothing
  depends on it — it can be the last phase in its chain. A phase with
  no "Blocked by" means it can start immediately.
-->

## Parallelism

<!--
  Which phases or issues can proceed independently? List groups of
  work that do not conflict with each other.
-->

- **Wave 1:** {{list phases with no blockers}}
- **Wave 2:** {{list phases unblocked after Wave 1 completes}}
- **Wave 3:** {{list phases unblocked after Wave 2 completes}}

<!-- Add or remove waves as needed. -->
