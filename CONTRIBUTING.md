# Contributing

Thanks for helping out. This page covers setup, the commands you'll run, and the rules a PR has
to meet. [AGENTS.md](AGENTS.md) holds the architecture and the reasoning behind it.

## Prerequisites

| Requirement | Why |
| --- | --- |
| Dart SDK `^3.13.0` (CI pins `3.13.0`) | The code uses Dart 3.13 syntax |
| `very_good_cli ^1.5.0` | Pub workspace coverage support |
| `mason_cli 0.1.4` | Regenerating the `agents` brick bundle |
| `jq` | The agent hooks parse their payloads with it |
| `gh`, authenticated with org access | This repo is private |

On Dart 3.12 `dart analyze` reports `experiment_not_enabled_off_by_default` against the `new(...)`
constructors. Fix the SDK, not the constructors. See
[AGENTS.md](AGENTS.md#prerequisites) for the rest of the symptoms.

## Setup

```sh
# Install dependencies, from the repo root
dart pub get

# Check your toolchain
cd packages/vgv_ai_cli
dart analyze --fatal-infos --fatal-warnings lib test
```

This repo commits `.claude/settings.json`, which enables two VGV plugins. Open it in Claude Code,
accept the trust prompt, run `/plugin` to confirm both are enabled, then restart the session —
hooks and MCP servers only bind at session start. The
[contributor setup in the README](README.md#contributor-setup) covers what goes wrong if you skip
that.

## Commands

Run these from `packages/vgv_ai_cli`.

```sh
# Format
dart format --set-exit-if-changed .

# Analyze (warnings and infos are fatal)
dart analyze --fatal-infos --fatal-warnings lib test

# Run one test file
dart run test test/src/commands/update_command_test.dart

# Run tests matching a name
dart run test --plain-name 'handles pub update'

# Run the CLI from source
dart run bin/vgv_ai.dart --help
```

From the repo root:

```sh
# Regenerate the agents bundle after changing bricks/agents
tool/generate_agents_bundle.sh
```

> **Warning:** the full coverage run is the one exception. With the VGV AI Flutter Plugin active, a
> hook denies `dart test`, `flutter test`, `very_good test`, `dart create`, `flutter create`,
> `very_good create` and `very_good packages` when they are the first two tokens of a Bash command.
> That's why the single-test commands above use `dart run test`, a form the hook doesn't catch. Run
> the full suite through the `very_good_cli` MCP `test` tool instead. CI runs it as
> `very_good dart test -j 4 --coverage --platform vm --min-coverage 100 --optimization`.

## Conventions

- **Layers.** `model/` holds what two or more features share, and `document/` sits above it.
  `detect/`, `resolve/`, `translate/`, `reconcile/` and `manifest/` are the features, each
  importing `model/` and `document/` but never another feature. `commands/` orchestrates them. See
  [AGENTS.md](AGENTS.md#layers).
- **Dart 3.13 syntax.** Unnamed constructors use the `new` keyword — `new({required this._logger})`.
  Empty class bodies end in a semicolon.
- **Linting** is `very_good_analysis` ^11.0.0 with `public_member_api_docs` off. Public classes
  still carry `/// {@template name}` doc comments.
- **No records or bare maps** across a boundary. A shape that would be one becomes a class or an
  extension type; a map appears only at the edge that needs it, through `toJson` or `toMap`.
- **Cognitive complexity** must stay at or below 15 per function. Split the function rather than
  raising the threshold.

## Tests

100% coverage is required. New code needs tests for its success, failure, and usage-error paths.

- Mock with `mocktail`.
- Exercise a command through `VgvAiCliCommandRunner.run(['install'])`, not by instantiating the
  `Command`, so argument parsing and the runner's error handling are covered too.
- Assert on logger calls alongside the exit code.
- Use `MemoryFileSystem.test()` for anything that touches disk.

Two suites are tagged and skipped by default:

```sh
# The generated version file is in sync
dart run test --run-skipped -t version-verify

# The real pinned plugins still resolve, parse and translate
dart run test --run-skipped -t pinned-plugins
```

## Commits and PRs

- **Never commit to `main`.** Branch as `<type>/<short-kebab-description>`, e.g.
  `feat/antigravity-hooks`.
- Commit messages and PR titles follow [Conventional Commits](https://www.conventionalcommits.org).
  The `semantic-pull-request` job checks the title.
- Fill in [the PR template](.github/PULL_REQUEST_TEMPLATE.md) and nothing more. A few sentences per
  heading.
- Don't edit `CHANGELOG.md` or bump versions. Release automation owns those.
- `lib/src/version.dart` is generated. Regenerate it with `dart run build_runner build` after a
  version bump; never edit it by hand.

## CI

Most jobs live in [`.github/workflows/vgv_ai_cli.yaml`](.github/workflows/vgv_ai_cli.yaml).

| Job | What it checks |
| --- | --- |
| `semantic-pull-request` | The PR title is a conventional commit |
| `build` | Format, analyze, 100% coverage, cognitive complexity |
| `spell-check` | cspell over every markdown file but the brick templates, changed or not |
| `verify-bundle` | `tool/generate_agents_bundle.sh` produces no diff |
| `verify-version` | `lib/src/version.dart` matches `pubspec.yaml` |
| `verify-pins` | The pinned plugins still resolve, parse and translate |

That workflow is path-filtered to `packages/vgv_ai_cli/{lib,test}/**`,
`packages/plugin_source/lib/**`, both `pubspec.yaml` files, `bricks/**`, `tool/**`,
`.github/cspell.json` and itself — so a docs-only PR triggers no CI at all, and a markdown mistake
surfaces on the next code PR instead. Add a new word to `words` in
[`.github/cspell.json`](.github/cspell.json) when spell-check rejects it.

[`license_check.yaml`](.github/workflows/license_check.yaml) is separate. It runs only when a
`pubspec.yaml` changes, and restricts dependency licenses to `MIT`, `BSD-3-Clause`, `BSD-2-Clause`
and `Apache-2.0`.

## Adding a harness

Teaching `vgv_ai` a new coding agent touches the `Harness` enum, the `agents` brick, a translator,
and four test files — five if it has hooks. See [ADDING_A_HARNESS.md](ADDING_A_HARNESS.md).
