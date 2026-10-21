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
| [Mason CLI](https://docs.brickhub.dev) `0.1.4`  | Regenerating the `agents` brick bundle.           |

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

Two suites are tagged and skipped by default:

```sh
# The generated lib/src/version.dart is in sync with pubspec.yaml
dart run test --run-skipped -t version-verify

# The real pinned plugins still resolve, parse and translate
dart run test --run-skipped -t pinned-plugins
```

From the repo root, after changing anything under `bricks/agents`:

```sh
tool/generate_agents_bundle.sh
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

## Conventions

- **Layers.** `model/` holds what two or more features share, and `document/`
  sits above it. `detect/`, `resolve/`, `translate/`, `reconcile/` and
  `manifest/` are the features, each importing `model/` and `document/` but
  never another feature. `commands/` orchestrates them. See
  [AGENTS.md](AGENTS.md#layers).
- **Dart 3.13 syntax.** Unnamed constructors use the `new` keyword —
  `new({required this._logger})`. Empty class bodies end in a semicolon.
- **Linting** is `very_good_analysis` with `public_member_api_docs` off. Public
  classes still carry `/// {@template name}` doc comments.
- **No records or bare maps** across a boundary. A shape that would be one
  becomes a class or an extension type; a map appears only at the edge that
  needs it, through `toJson` or `toMap`.
- **Cognitive complexity** stays at or below 15 per function. Split the
  function rather than raising the threshold.
- **Generated files** are never edited by hand: `lib/src/version.dart` comes
  from `build_runner`, and `lib/src/templates/agents_bundle.dart` from
  `tool/generate_agents_bundle.sh`.

## Testing

- New code needs tests: both packages keep 100% test coverage, covering the
  success, failure, and usage-error paths.
- Mock with `mocktail`, and use `MemoryFileSystem.test()` for anything that
  touches disk.
- Exercise a command through `VgvAiCliCommandRunner.run([...])` rather than
  instantiating the `Command`, so argument parsing and the runner's error
  handling are covered too.

## Pull requests

- Branch off `main`; never commit to it directly. Name the branch
  `<type>/<short-kebab-description>`, such as `feat/antigravity-hooks`.
- Commits and pull request titles follow
  [Conventional Commits](https://www.conventionalcommits.org/). The
  `semantic-pull-request` job checks the title.
- Fill in [the pull request template](.github/PULL_REQUEST_TEMPLATE.md) and
  nothing more.
- Leave every `CHANGELOG.md` and version bump alone, the `agents` brick's included. Release
  automation owns them.

## Breaking changes

`vgv_ai` writes into config files people already own, and the install manifest
is the only record of what it wrote. A change to behavior can therefore strand
files on someone's disk rather than just fail a test.

**Open an issue or a discussion first, agree the approach there, and link it
from the pull request.** A breaking change that arrives as a PR with no prior
discussion gets sent back.

What counts:

- Renaming or removing a `Harness` value. The manifest records the owner by
  name and silently drops an entry it cannot resolve, so every file that
  harness wrote is orphaned: `uninstall` stops removing them and `doctor`
  stops seeing them.
- Moving where a harness writes — its config directory, `hooksRoot()` or
  `skillsRoot()`. The files already written stay behind under the old path.
- Changing a file's `ChangeMode`, which decides whether VGV owns a file
  outright or merges into one the user shares with us.
- Changing which settings keys are written into a config the user also edits.
- Changing the manifest format or its version.

Adding a harness is none of these: it only adds an enum value, a brick folder
and a translator, and touches no existing harness.

## CI

Most jobs live in
[`.github/workflows/vgv_ai_cli.yaml`](.github/workflows/vgv_ai_cli.yaml):

| Job                     | What it checks                                                           |
| ----------------------- | ------------------------------------------------------------------------ |
| `semantic-pull-request` | The pull request title is a conventional commit.                         |
| `build`                 | Format, analyze, 100% coverage, cognitive complexity.                    |
| `spell-check`           | cspell over every markdown file but the brick templates, changed or not. |
| `verify-bundle`         | `tool/generate_agents_bundle.sh` produces no diff.                       |
| `verify-version`        | `lib/src/version.dart` matches `pubspec.yaml`.                           |
| `verify-pins`           | The pinned plugins still resolve, parse and translate.                   |

That workflow is path-filtered to the two packages' `lib/`, `test/` and
`pubspec.yaml`, plus `bricks/`, `tool/` and `.github/cspell.json`. A docs-only
pull request triggers none of it, so a markdown mistake surfaces on the next
code change instead. Add a word to `words` in
[`.github/cspell.json`](.github/cspell.json) when spell-check rejects one.

[`license_check.yaml`](.github/workflows/license_check.yaml) is separate. It
runs when a `pubspec.yaml` changes, and restricts dependency licenses to `MIT`,
`BSD-3-Clause`, `BSD-2-Clause` and `Apache-2.0`.

## Adding a harness

Teaching the CLI a coding agent it does not configure yet touches the `Harness`
enum, the `agents` brick, a translator, and four test files — five if it has
hooks. See [adding a harness](ADDING_A_HARNESS.md).
