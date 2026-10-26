# Contributing to vgv_ai_cli

This guide covers setting up the repository and the commands you need to work
on it. For what the repository holds, see the [README](README.md).

## Prerequisites

| Requirement                                     | Why                                               |
| ----------------------------------------------- | ------------------------------------------------- |
| [Dart SDK](https://dart.dev/get-dart) `^3.13.0` | The code uses Dart 3.13 syntax.                   |
| [Very Good CLI](https://cli.vgv.dev) `^1.5.0`   | The coverage run needs its pub workspace support. |
| [jq](https://jqlang.org)                        | The agent hooks parse their payloads with it.     |
| [GitHub CLI](https://cli.github.com), signed in | Pushing branches and opening pull requests.       |

The Dart version matters more than it looks: on 3.12 the analyze hook reports
errors against this codebase's Dart 3.13 syntax, and those errors read as real
ones. Fix the SDK, not the code.

## Contributor setup

This repo ships a committed agent configuration in `.claude/settings.json`,
which declares the `very-good-claude-code-marketplace` and enables two VGV
plugins: `vgv-wingspan` and `vgv-ai-flutter-plugin`.

### 1. Trust the folder

Open the repo in Claude Code and accept the trust prompt. The marketplace
resolves from the committed settings, so you don't need to run
`/plugin marketplace add`.

One exception: if you already have a marketplace registered under the name
`very-good-claude-code-marketplace`, that registration wins and the committed
pin is ignored. Check that `/plugin` shows the GitHub source. If it shows a
local directory instead, remove yours first.

### 2. Confirm the plugins installed, then restart

Run `/plugin` and check that both plugins show as enabled. Then restart the
session: settings apply immediately, but hooks and MCP servers only bind at
session start.

This step isn't optional bookkeeping. Wingspan normally nudges you when a
companion plugin is missing, but it decides "already installed" by looking for
the plugin name in `.claude/settings.json`, which this repo commits. If your
install silently failed, nothing tells you, and the agent carries on without
the hooks or quality gates.

### 3. Verify

Run this from `packages/vgv_ai_cli`:

```sh
dart pub get && dart analyze --fatal-infos --fatal-warnings lib test
```

## Common commands

Run these from `packages/vgv_ai_cli`:

```sh
# Format code
dart format --set-exit-if-changed .

# Analyze code (warnings and infos are fatal)
dart analyze --fatal-infos --fatal-warnings lib test

# Run a single test file
dart run test test/src/commands/update_command_test.dart

# Run the CLI from source
dart run bin/vgv_ai.dart --help
```

CI runs the full suite with a 100% coverage gate:

```sh
very_good dart test -j 4 --coverage --min-coverage 100 --optimization
```

With the VGV AI Flutter plugin active, a hook blocks that command in the shell,
so a coding agent runs it through the `very_good_cli` MCP `test` tool instead.

To browse a coverage report after a coverage run, generate it with
[lcov](https://github.com/linux-test-project/lcov):

```sh
genhtml coverage/lcov.info -o coverage/
open coverage/index.html
```

## Pull requests

- New code needs tests: both packages keep 100% test coverage.
- Commits and pull request titles follow
  [Conventional Commits](https://www.conventionalcommits.org/).

## Releases

[release-please](https://github.com/googleapis/release-please) owns versions and changelogs.
Every push to `main` opens or updates a release pull request that bumps both packages to the
same version and writes their `CHANGELOG.md`. Merge it only when a release is intended; merging it tags the release and
publishes the notes.

Do not bump a version or edit a `CHANGELOG.md` by hand.
