# Commit Conventions Skill

Establish and enforce commit message and branch naming conventions using the Conventional Commits specification.

## Conventions

### Commit message format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

**Rules:**
- The type and description are mandatory.
- The description must be lowercase and use the imperative mood ("add" not "added").
- The description must not end with a period.
- Scopes are optional and enclosed in parentheses after the type: `feat(auth): add login`.
- Breaking changes are indicated with `!` after the type/scope: `feat!: drop support for v1 API` or a `BREAKING CHANGE:` footer.

### Branch naming

```
<category>/<short-description>
```

**Categories:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

**Rules:**
- Use kebab-case for the description segment.
- Keep the description short and descriptive (3–5 words).
- Prefix with the same type categories used in commits.

**Examples:** `feat/user-auth`, `fix/race-condition-cache`, `docs/api-reference`

## Applying the conventions

### As an author

1. Write every commit message in Conventional Commits format.
2. Name branches using the `<category>/<short-description>` pattern.
3. Use the bundled commit message template (`templates/commit-message-format.md`) as a reference when composing messages.

### As a reviewer

1. Check that commit messages follow the format during PR review.
2. Flag messages that are missing a type or use non-imperative descriptions.
3. Suggest squash-and-rebase when a PR's commit history includes "fix typo" or "wip" messages.

### Adopting the hook

Copy the bundled hook into any repository's `.git/hooks/` directory:

```bash
cp templates/commit-msg-hook.sh .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

The hook validates every commit message against the Conventional Commits format before the commit is accepted.
