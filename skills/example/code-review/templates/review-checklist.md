# Code Review Checklist

Work through each category. Skip sections that do not apply to the change under review. Mark findings as **blocking** (must fix before merge) or **non-blocking** (suggestion).

## Correctness

- [ ] Logic handles empty, null, and boundary inputs (zero, negative, empty string, empty list).
- [ ] Edge cases are covered: unset fields, missing files, timeouts, partial failures.
- [ ] Error paths are explicit. Every error is either recovered or propagated with context.
- [ ] No race conditions or ordering dependencies in concurrent code paths.
- [ ] Loops, slices, and range checks are free of off-by-one errors.
- [ ] Mutations of shared state are intentional and safe.
- [ ] Return values are checked. No discarded errors without explicit justification.
- [ ] Fallback or default behaviour is defined when an operation can fail.

## Security

- [ ] User input is validated at the system boundary. No unsanitised input reaches SQL, shell, or HTML.
- [ ] Secrets, tokens, and credentials are not logged, echoed to stdout, or returned to the client.
- [ ] Authorisation checks happen before data access, not only before presentation.
- [ ] External URLs, file paths, and commands are not constructed from untrusted input.
- [ ] Sensitive data is not exposed in error messages or stack traces.
- [ ] Dependencies are pinned to known versions. No newly introduced dependency has known vulnerabilities.

## Style and patterns

- [ ] Naming matches project conventions and is self-documenting.
- [ ] Functions and methods have a single responsibility.
- [ ] New abstractions are justified by actual reuse, not anticipated future needs.
- [ ] The change is placed in the correct service, module, or package per project structure rules.
- [ ] No dead code, commented-out blocks, or debug logging left behind.
- [ ] Imports and dependencies are in the correct direction (specific depends on shared, never reverse).

## Tests

- [ ] Tests exist for the new or modified behaviour.
- [ ] Edge cases and error paths are tested, not only the happy path.
- [ ] Tests verify behaviour (observable outcomes), not implementation details.
- [ ] Test fixtures are minimal and focused on what is being tested.
- [ ] No shared mutable state between tests that could cause ordering-dependent failures.
- [ ] Mocks or stubs are used for external dependencies, not for the code under test.

## Documentation

- [ ] Public interfaces, API endpoints, and CLI flags have clear descriptions.
- [ ] Breaking changes are called out with migration steps.
- [ ] New configuration (env vars, flags, files) is documented where operators will find it.
- [ ] Comments explain why, not what — the code already shows what.

## Performance (if applicable)

- [ ] No unnecessary allocations or copies in hot paths.
- [ ] Queries and loops scale with input size (no accidental O(n^2) where O(n) is expected).
- [ ] Resources (files, connections, goroutines) are closed or released, including on error paths.
