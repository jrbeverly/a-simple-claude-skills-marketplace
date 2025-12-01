# Commit message template

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Fields

| Field | Required | Format |
|-------|----------|--------|
| `type` | Yes | One of: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` |
| `scope` | No | Short noun in parentheses: `(auth)`, `(api)`, `(ui)` |
| `description` | Yes | Lowercase, imperative mood, no trailing period |
| `body` | No | Free-form text explaining what and why (not how) |
| `footer(s)` | No | `BREAKING CHANGE: <description>` or issue references like `Refs #123` |

## Breaking changes

Two ways to signal a breaking change:

```
feat!: drop support for legacy auth tokens
```

Or with a footer:

```
feat: add OAuth2 authentication

BREAKING CHANGE: the legacy bearer token format is no longer accepted
```
