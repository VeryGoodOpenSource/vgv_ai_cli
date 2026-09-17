# Very Good Ventures

At its core, VGV prefers code that embodies clear, concise mental models. We prefer to think deeply about the problem we are solving and find the solution that best fits.

If you recognize a key insight that would clean something up but do not have what you need on hand to implement it, please just say so. Adding a package reference is easy.

Our criteria for good code also enables us to achieve 100% test coverage.

Good code has...

- As few branches as possible
- Injectable dependencies
- Well-named identifiers
- No sibling dependencies in the same architectural layer

## Project Overview

`vgv_ai_cli` is a Dart command-line tool by Very Good Ventures that configures Very Good AI coding agents and tooling. The executable is `vgv_ai`.

The repo is a **pub workspace** monorepo: the root `pubspec.yaml` declares `workspace: [packages/vgv_ai_cli]`, the package uses `resolution: workspace`, and there is one shared `pubspec.lock` at the root.

## Prerequisites

| Requirement | Why | Symptom when wrong |
|---|---|---|
| Dart SDK `^3.13.0` (CI pins `3.13.0`) | The code uses 3.13 syntax | `dart pub get` fails version solving. Worse, on 3.12 `dart analyze` reports `experiment_not_enabled_off_by_default` against the `new(...)` constructors — **do not "fix" that by rewriting them**, fix the SDK |
| `very_good_cli ^1.5.0` | Pub workspace coverage support | Coverage dies with `Directory listing failed, path = './coverage/'`. A stale binary also prints `Invalid kernel binary format version` — reactivate with `dart pub global activate very_good_cli "^1.5.0"` |
| `jq` | Agent hooks parse their payloads with it | Guard hooks error out; the analyze and format hooks silently do nothing |
| `gh`, authenticated with org access | This repo is private | Push and PR creation fail |

Upgrading `very_good_cli` does not reach the MCP server until the agent session restarts — the server binds its binary at session start.

## Common Commands

Run these from `packages/vgv_ai_cli` unless noted.

```bash
# Install dependencies (from the repo root or the package)
dart pub get

# Format code
dart format --set-exit-if-changed .

# Analyze code (strict: warnings and infos are fatal)
dart analyze --fatal-infos --fatal-warnings lib test

# Run a single test file
dart run test test/src/commands/sample_command_test.dart

# Run tests by name (--plain-name matches substrings, so this runs both
# 'tells a joke' and 'tells a joke in cyan')
dart run test --plain-name 'tells a joke'

# Verify the generated version file is in sync (tagged, skipped by default)
dart run test --run-skipped -t version-verify

# Regenerate lib/src/version.dart after bumping the package version
dart run build_runner build

# Run the CLI from source
dart run bin/vgv_ai.dart --help
```

**Full test run with coverage** is the one exception. With the VGV AI Flutter Plugin active, a hook denies `dart test`, `flutter test`, `very_good test`, `dart create`, `flutter create`, `very_good create`, and `very_good packages` when they are the first two tokens of a Bash command (note `very_good packages get` is blocked while `dart pub get` is not), so run it through the `very_good_cli` MCP `test` tool instead. That tool takes no file path and no name filter, which is why the single-test commands above use `dart run test` — a form the hook does not catch, and the one CI itself uses for `verify-version`. The equivalent CI step is:

```bash
very_good test -j 4 --coverage --min-coverage 100 --optimization
```

## Architecture

### Command Runner Pattern

Entry point: `bin/vgv_ai.dart` → `VgvAiCliCommandRunner` (`lib/src/command_runner.dart`), which extends `CompletionCommandRunner<int>` from `cli_completion`, so shell completion is built in.

All commands are `Command<int>` subclasses in `lib/src/commands/`, exported from `commands.dart`, and return the `int` from a `mason_logger` `ExitCode` (e.g. `ExitCode.success.code`). `main` in `bin/vgv_ai.dart` passes the runner's result to `_flushThenExit`.

The runner owns three cross-cutting behaviors that individual commands do not repeat:

- **Dependency injection.** `Logger` (mason_logger) and `PubUpdater` are constructor parameters with real defaults. Commands receive the `Logger` from the runner rather than creating one. This is what makes the whole CLI testable.
- **Error handling.** `FormatException` and `UsageException` are caught in `run()` and converted to `ExitCode.usage.code` with usage output. Commands do not handle these themselves.
- **Update check.** After every command except `update`, `_checkForUpdates()` compares `packageVersion` against pub.dev and prints an upgrade prompt. The `completion` command is fast-tracked and skips this entirely.

### Adding a command

1. Create `lib/src/commands/<name>_command.dart` with a `Command<int>` subclass taking `required this._logger`.
2. Export it from `lib/src/commands/commands.dart`.
3. `addCommand(...)` it in the `VgvAiCliCommandRunner` constructor.

### Generated version file

`lib/src/version.dart` is generated by `build_version` from the `version:` field in `pubspec.yaml`. **Never edit it by hand** — regenerate with `build_runner` after bumping the version. `test/ensure_build_test.dart` verifies it is in sync; it is tagged `version-verify` and skipped by default (see `dart_test.yaml`).

## Code Conventions

- Linting: `very_good_analysis` ^11.0.0, with `public_member_api_docs` disabled. Public classes still carry `/// {@template name}` / `/// {@macro name}` doc comments.
- The codebase uses **Dart 3.13 syntax**. Unnamed constructors are declared with the `new` keyword — `new({required this._logger})`, not `SampleCommand({...})`. Empty class bodies use a semicolon — `class _MockLogger extends Mock implements Logger;`.
- Commits and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/).

### Testing

- **100% test coverage required.** New code needs tests covering success, failure, and usage-error paths.
- Mocking with `mocktail`.
- Tests exercise commands **through** `VgvAiCliCommandRunner.run(['sample'])` rather than instantiating the `Command` directly, so argument parsing and the runner's error handling are covered too.
- Assertions verify logger calls (`verify(() => logger.info(...)).called(1)`) alongside the exit code.

## Agent tooling

`.claude/settings.json` is committed and enables two plugins from the VGV marketplace: `vgv-wingspan` (brainstorm → plan → build → review workflows) and `vgv-ai-flutter-plugin` (Dart quality gates, MCP tools, hooks).

It pins the marketplace catalog to commit `842e9458` (marketplace `1.0.5`), which declares **both plugins at `0.0.5`**. That pins the versions the catalog *declares*; each plugin entry sources from its own repo without a ref of its own, so plugin content still tracks those default branches. Expect some drift, and re-pin the SHA when you want a newer catalog.

The flutter plugin runs `dart analyze` and `dart format` automatically after **every** `.dart` Edit or Write. Analyze failures come back as work to do, which is why the SDK requirement above matters so much.

This is a pure Dart CLI with no widgets, so the rule is: any skill gated on Flutter widgets, theming, or navigation does not apply here. The ones that do include `green-gate`, `testing`, `license-compliance`, `very-good-analysis-upgrade`, `dart-flutter-sdk-upgrade`, and `create-project` (its `dart_cli` template is what this repo is).

`main` has no branch protection yet. The `permissions.deny` entries blocking force-push are a guardrail against accident, not enforcement; they do not stop `git -C . push --force` or similar.

`CLAUDE.md` is a symlink to this file, so Claude Code and any agent that reads `AGENTS.md` get the same guidance.

## CI

- PR titles must be [conventional commits](https://www.conventionalcommits.org). The `semantic_pull_request` job checks this, but see the path-filter note below — it does not run on every PR.
- Dependency licenses are restricted to `MIT`, `BSD-3-Clause`, `BSD-2-Clause`, `Apache-2.0`.
- Markdown is spell-checked with cspell against the VGV dictionaries; add project-specific words to `words` in `.github/cspell.json`. The job runs with `modified_files_only: false`, so it lints **every** markdown file whenever it runs.
- Every job lives in `.github/workflows/vgv_ai_cli.yaml`, which is path-filtered to `lib/**`, `test/**`, `pubspec.yaml`, and itself. A docs- or config-only PR triggers no CI at all.
- The `build` job is currently inlined with a manual `very_good_cli ^1.5.0` pin instead of the reusable `dart_package.yml` workflow, pending very_good_workflows 1.21.1 (pub workspace coverage support). See the TODO in that file before changing it.
