---
title: Contributing
nav_order: 7
---

[Home](../index.md) > Contributing

# Contributing Guide

How to contribute to Sound Forge Alchemy.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Branch Strategy](#branch-strategy)
- [Commit Convention](#commit-convention)
- [Pull Request Process](#pull-request-process)
- [Testing Requirements](#testing-requirements)
- [Code Style](#code-style)
- [Documentation Standards](#documentation-standards)
- [Issue Reporting](#issue-reporting)

---

## Code of Conduct

Be respectful. Constructive feedback only. No personal attacks.

---

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/sound-forge-alchemy.git`
3. Follow the [Installation Guide](../guides/installation.md) to set up your dev environment
4. Create a feature branch: `git checkout -b feature/your-feature-name`
5. Make your changes with tests
6. Run `mix precommit` to verify everything passes
7. Open a pull request

---

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Production-ready code. Protected. |
| `feature/*` | New features |
| `fix/*` | Bug fixes |
| `refactor/*` | Code improvements without behavior change |
| `docs/*` | Documentation only |
| `chore/*` | Dependency updates, CI changes |

Branches are merged via PR only. Direct pushes to `main` are disabled.

---

## Commit Convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code change without behavior change |
| `docs` | Documentation only |
| `test` | Adding/updating tests |
| `chore` | Build, CI, dependencies |
| `perf` | Performance improvement |

**Examples:**

```
feat(agents): add LibraryAgent for playlist curation
fix(demucs): handle htdemucs_6s model in DemucsPort valid list
docs(api): add WebSocket channel event reference
test(music): add AnalysisResult factory
```

---

## Pull Request Process

1. **Ensure all tests pass:** `mix test`
2. **Ensure `mix precommit` passes** (compile, format, unused deps, test)
3. **Write a clear PR description** explaining:
   - What problem this solves
   - How the implementation works
   - Any migration steps required
4. **Link related issues** with `Closes #123`
5. **Request review** from at least one maintainer
6. **Address review comments** before merge

### PR Checklist

- [ ] Tests added/updated for all changed behavior
- [ ] `mix precommit` passes with no warnings
- [ ] Documentation updated if adding/changing public APIs
- [ ] Migration added if changing DB schema
- [ ] `CHANGELOG.md` entry added if user-facing change

---

## Testing Requirements

All pull requests must:

- Maintain or improve test coverage
- Include unit tests for all new context functions
- Include LiveView tests for new UI interactions
- Not break existing tests (run `mix test --failed` to check)

Test organization:

```
test/
├── sound_forge/          # Unit tests (context, domain)
│   ├── music_test.exs
│   ├── agents/
│   └── llm/
└── sound_forge_web/      # Integration + LiveView tests
    ├── live/
    └── controllers/
```

Run tests:

```bash
mix test                            # All tests
mix test test/sound_forge/          # Unit tests only
mix test test/sound_forge_web/live/ # LiveView tests only
mix test --failed                   # Rerun failed tests
mix test test/sound_forge/music_test.exs:42  # Specific test
```

---

## Code Style

### Elixir

Follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide).

Key rules enforced by `mix format` and `mix credo`:
- 2-space indentation
- Trailing commas in multi-line lists
- Pipe operator over nested function calls
- Pattern matching over conditionals where natural
- `@moduledoc` and `@doc` on all public functions
- `@spec` type annotations on all public functions
- No `any()` types without justification

### TypeScript / JavaScript

Asset files follow standard Prettier formatting. JS hooks should be minimal — business logic belongs in Elixir.

---

## Documentation Standards

When adding or changing functionality:

1. Update relevant docs pages in `docs/`
2. Add `@doc` and `@spec` to all new public Elixir functions
3. Update [Changelog](../changelog/index.md) with a new entry
4. Ensure all internal links in docs resolve (no dead links)

Documentation pages must:
- Start with a breadcrumb
- Have a clear `# Title`
- Include a table of contents for pages over 200 words
- Have a "See Also" section
- End with prev/next navigation

---

## Issue Reporting

For bugs, please provide:
- SFA version (`mix phx.server` output or `Application.spec(:sound_forge, :vsn)`)
- OS and Elixir version
- Steps to reproduce
- Expected vs. actual behavior
- Relevant log output (sanitize any API keys)

For feature requests:
- Describe the use case (not just the implementation)
- Explain why existing features don't solve it
- Note if you're willing to implement it

[Open an Issue on GitHub](https://github.com/peguesj/sound-forge-alchemy/issues/new)

---

## See Also

- [Development Guide](../guides/development.md)
- [Architecture Overview](../architecture/index.md)
- [Changelog](../changelog/index.md)

---

[← Changelog](../changelog/index.md) | [Back to Home →](../index.md)
