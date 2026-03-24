# Contributing to CrewDock

Thanks for your interest in contributing to CrewDock! This guide covers how to get started.

## Getting Started

1. Fork the repo and clone your fork
2. Create a feature branch: `git checkout -b feat/your-feature`
3. Make your changes
4. Run tests: `make test`
5. Commit with a prefix: `feat:`, `fix:`, `chore:`, or `docs:`
6. Open a PR against `develop`

## Prerequisites

- Docker and Docker Compose
- [bats-core](https://github.com/bats-core/bats-core) for running tests (`brew install bats-core` on macOS)
- `jq`, `curl`, `sqlite3` for working with shell scripts

## Development Workflow

### Running Tests

```bash
make test    # Run all bats tests
```

All tests must pass before committing. Tests run against real SQLite databases in temp directories, no Docker required.

### Project Structure

- `agents/` contains agent templates (SOUL.md, config, db helpers)
- `installer/` contains the TUI wizard modules
- `init.d/` contains container boot scripts
- `tests/` contains bats test files

### Writing Tests

When modifying shell scripts, add or update corresponding tests in `tests/`. Tests use [bats-core](https://github.com/bats-core/bats-core):

```bash
@test "description of what you're testing" {
  run bash "$SCRIPT" some-command "arg1" "arg2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"expected"* ]]
}
```

## Code Style

- Shell scripts: `set -euo pipefail`, functions over inline logic
- Bash 3.2 compatibility for anything that runs on the host (installer scripts)
- Commit messages: `feat:`, `fix:`, `chore:`, `docs:`, `merge:` prefixes
- Keep shell scripts focused. One script, one responsibility.

## Pull Requests

- Target the `develop` branch
- Keep PRs focused on a single change
- Include tests for new functionality
- Describe what changed and why in the PR description

## Adding a New Agent

1. Create a directory under `agents/your-agent/`
2. Add at minimum: `SOUL.md`, `IDENTITY.md`, `AGENTS.md`, `.protected`
3. Add a config example: `config.example.json`
4. Register the agent in `installer/manifest.json`
5. Add a Discord integration module in `installer/` if needed
6. Update `init.d/02-config.sh` to include the agent in config generation

## Reporting Bugs

Open an issue with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- Docker version and OS

## Questions?

Open a [discussion](https://github.com/dasirra/crewdock/discussions) or file an issue.
