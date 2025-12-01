# Planning Skill

Convert a feature idea, bug report, or design proposal into a structured implementation plan using the bundled templates. The plan captures what to build, in what order, and what depends on what — so any contributor can pick up a phase and start work.

## When to use this skill

- A feature request or design document needs to be broken into concrete, sequenced work items.
- A project has a goal but no written plan for achieving it.
- Multiple contributors need to work on related tasks without stepping on each other.
- A reviewer asks "what's the plan?" or "what are the dependencies?"

## Methodology

1. Start with the milestone outline. Define the phases from first principles: what must be true before the next phase can begin? Each phase should produce a working intermediate state, not a half-built feature.
2. Write one issue per phase using the issue template. An issue is the unit of work a single contributor can complete in a sitting. If a phase is large, write multiple issues but keep them independently completable.
3. Map dependencies. Every issue blocks zero or more other issues. Draw the graph so you know what order work can proceed in and where parallelism is possible.
4. Review the plan as a whole. Does every phase end in a verifiable state? Are dependencies acyclic? Can any phase be split or combined to reduce coordination overhead?
5. Publish the plan. Commit the milestone outline and dependency map to the repository. File the issues. Link them together.

## Templates and when to apply them

### Milestone outline (`templates/milestone-outline.md`)

A table that breaks the work into ordered phases with goals, files to touch, and dependencies. Apply first, before writing individual issues. The outline forces you to think about sequencing before diving into details.

### Issue template (`templates/issue-template.md`)

A structured issue for a single unit of work. Apply once per phase (or per sub-task within a large phase). The template covers context (why this matters), approach (what to do), acceptance criteria (how to know it's done), and dependencies.

### Dependency map (`templates/dependency-map.md`)

A visual ordering of phases with blocking relationships annotated. Apply after the milestone outline and issues are drafted. The map surfaces coordination points and reveals whether the plan is parallel enough.

## How to use the templates

1. Copy the milestone outline into a new document (e.g. `docs/plans/{{feature-name}}.md`).
2. Fill in each phase row. Keep the scope of each phase small enough that it can be verified independently.
3. For each phase, copy the issue template and fill it in. File the issues in the project tracker.
4. Copy the dependency map and fill in the phases and their blocking relationships.
5. Remove the placeholder comments once filled in.
6. Cross-link the documents: the milestone outline references the issues; the issues reference the dependency map.

## Reference example

The worked example (`examples/sample-plan.md`) shows all three templates filled in for a fictional "add user authentication" feature. Use it to see how phases decompose into issues, how dependencies are annotated, and what a complete plan looks like when the placeholders are filled in.
