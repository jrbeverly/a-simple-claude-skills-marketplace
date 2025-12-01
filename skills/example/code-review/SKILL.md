# Code Review Skill

Perform a structured code review of the pull request or diff provided in context, using the bundled checklist and comment template.

## Methodology

1. Read the entire diff before forming opinions. Understand the intent before evaluating the implementation.
2. Work through the review checklist (`templates/review-checklist.md`), assessing each category.
3. For each finding, classify severity: **blocking** (must fix before merge) or **non-blocking** (suggestion for the author to consider).
4. Draft review comments using the PR comment skeleton (`templates/pr-comment.md`) as a structural guide.
5. Support each blocking finding with a concrete example of what could go wrong and a specific remediation.
6. Acknowledge what the author did well. Reviews should reinforce good decisions, not only flag problems.

## What to look for

### Correctness
- Does the logic handle empty, null, and boundary inputs?
- Are edge cases covered (empty lists, zero values, negative numbers, unset fields)?
- Are error paths handled explicitly? Is every error either recovered or propagated?
- Are race conditions or ordering dependencies possible in concurrent contexts?
- Are off-by-one errors present in loops, slices, or range checks?

### Security
- Is user input validated at the boundary? Are injections possible (SQL, command, path traversal)?
- Are secrets, tokens, or credentials exposed in logs, error messages, or client-facing responses?
- Are authorisation checks performed before data access, not only before rendering?
- Are external URLs or file paths constructed from untrusted input?

### Style and patterns
- Does the code follow the project's established conventions (naming, file placement, error handling)?
- Are functions and methods sized appropriately (single responsibility)?
- Are new abstractions justified, or could existing ones be reused?
- Is the change placed in the correct service or module per the project's structure rules?

### Tests
- Does the change include tests for the new or modified behaviour?
- Are edge cases and error paths tested, not only the happy path?
- Do the tests verify behaviour, not implementation details?
- Are test fixtures minimal and focused on what is being tested?

### Documentation
- Do public interfaces, API endpoints, or CLI flags have clear descriptions?
- Are breaking changes or migration steps documented?
- Are configuration changes (new env vars, new flags) reflected in relevant docs?

## Review tone

- Be direct but respectful. State what is wrong and why, without assigning blame.
- Use the PR comment template to organise feedback so the author can scan it quickly.
- Distinguish observations (things you noticed but are unsure about) from findings (things you are confident need action).
- When you are uncertain, say so — and ask a clarifying question rather than asserting a problem.

## Using the bundled materials

- **Review checklist** (`templates/review-checklist.md`): Work through this systematically. Skip sections that do not apply to the change.
- **PR comment skeleton** (`templates/pr-comment.md`): Fill in each section. Delete sections left empty. The structure helps the author navigate the review.
- **Sample review** (`examples/sample-review.md`): Reference for tone, structure, and depth. Not a template to copy verbatim — adapt to the change under review.
