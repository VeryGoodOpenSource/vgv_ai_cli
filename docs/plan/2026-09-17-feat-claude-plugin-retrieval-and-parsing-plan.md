---
title: "feat: add Claude plugin retrieval and parsing"
type: feat
date: 2026-09-17
---

## feat: add Claude plugin retrieval and parsing - Standard

## Overview

Add the retrieval and parsing half of harness generation to `vgv_ai_cli`. The CLI fetches
Claude Code plugin repositories, parses their agents into typed Dart models, and produces a
versioned JSON manifest that mason bricks consume to emit harness-specific output such as
Codex agent TOML.

This plan covers fetch, parse, and the manifest contract. Mason bricks and the per-harness
mapping config are separate workstreams. The committed golden manifest fixture is the written
interface between them.

Derived from [the brainstorm](../brainstorm/2026-09-17-plugin-parsing-and-retrieval-brainstorm-doc.md).

## Problem Statement / Motivation

Claude plugins are natively installable in Claude Code. Users on other harnesses such as
Codex cannot install them, because the same concepts ship in different formats. A Claude
subagent is markdown with YAML frontmatter. A Codex subagent is TOML.

The failure mode to avoid is hand-maintained copies of every agent per harness, which is what
comparable tools do and what rots first. Claude plugins must stay the single maintained
source. Supporting a new harness should mean adding a brick and a config entry, nothing else.

Nothing in the repository does this yet. `packages/vgv_ai_cli` is a fresh Very Good CLI
scaffold with only `sample` and `update` commands.

## Proposed Solution

A new `lib/src/plugins/` library inside `packages/vgv_ai_cli`, split into two layers.

**Parse layer.** A `PluginParser` class that reads a plugin directory tree and produces a
`PluginManifest`. Reads the filesystem, never the network, fully hermetic under test.

**Fetch layer.** A `GitClient` interface with a `ProcessGitClient` implementation that shells
out to `git` for a shallow, tag-pinned clone into a CLI-owned cache directory, resolving the
ref to a SHA. The interface exists so tests substitute a fake and reach 100 percent coverage
without a network.

Mason generation will later run in-process inside this same package, so the manifest is passed
as Dart objects and `lib/src/` is the correct home. Nothing needs re-exporting from
`lib/vgv_ai_cli.dart`, which today is a bare `library;`. The golden JSON file is the
development-time contract for the brick workstream, not a runtime artifact.

### Manifest shape

The manifest holds many plugins, not one. The real use case is generating wingspan and the
Flutter plugin into a single Codex install. Merging separate single-plugin manifests would
push cross-plugin id collision handling into the brick layer, which cannot fix it.

```
PluginManifest
  schemaVersion  int
  plugins        List<ParsedPlugin>        sorted by metadata.name

ParsedPlugin
  source    PluginSource      repo, ref, resolvedSha
  metadata  PluginMetadata
  agents    List<PluginAgent>               sorted by id

PluginMetadata
  name, version?, description?, author?, homepage?, repository?, license?,
  keywords: List<String>, extra: Map<String, dynamic>

PluginAgent
  id          path under agents/ without .md, e.g. codebase-review/vgv-review-agent
  name        from frontmatter
  description verbatim
  model?      verbatim, never translated here
  effort?
  skills      List<String>
  tools       List<String>
  body        markdown after the frontmatter
  extra       Map<String, dynamic>, arbitrarily nested
```

`PluginSource` lands in Phase 1, not Phase 2. `PluginParser.parse` takes it as a required
parameter, so Phase 2 only supplies real values instead of reshaping the manifest. Otherwise
the fixture the brick workstream builds against is not actually frozen.

`schemaVersion` starts at 1. This plan only emits it. The brick workstream reads it and fails
hard on a mismatch. Do not build validation logic here.

**JSON keys are camelCase**, mirroring the Dart model so `toJson` needs no translation layer.
Mustache resolves any key name, so this only affects `schemaVersion` and `resolvedSha`.

**Models are immutable.** All fields `final`, constructors `const` where field types permit,
collections handed out as `List.unmodifiable` and `UnmodifiableMapView`. No `equatable` and no
value equality: the golden test compares encoded JSON strings, so equality would be an unearned
dependency.

**No code generation.** Hand-written `toJson`, no `fromJson`. `build_runner` is already wired
for `version.dart` and `ensure_build_test.dart`, and adding `json_serializable` would widen
what `ensure_build` verifies for no benefit, since nothing reads the manifest back in Dart.

### Frontmatter splitting

Do not use `package:front_matter`. Its last release was 2019 and it declares
`sdk: >=2.0.0 <3.0.0`, so it cannot resolve here.

Hand-roll the split with `package:yaml`:

1. Normalize CRLF to LF on read. Defensive, not observed: neither real plugin has CRLF today,
   but it is one `replaceAll` and a Windows contributor is a plausible near-term source.
2. If line 1 is not exactly `---`, the file has no frontmatter. Body is the whole file.
3. Otherwise scan forward for the next line that is exactly `---`. Everything between is
   YAML, everything after is body.

Matching `^---$` exactly is load-bearing. Ten `SKILL.md` files in
`vgv-ai-flutter-plugin@0.0.5` contain three to fourteen `---` lines in the body,
`skills/green-gate/SKILL.md` worst at fourteen. A naive split on every `---` truncates those
bodies silently. Agents are clean today, but the same splitter serves skills in a later slice.

Both folded `>` and literal `|` block scalars are in use. `flutter-reviewer.md` uses `>`,
wingspan agents use `|` and carry embedded `<examples>` XML that must survive verbatim. Test
both.

CRLF is tested with a Dart string literal in `frontmatter_test.dart`, never a committed
fixture file. Without a `.gitattributes`, any `core.autocrlf` setting silently rewrites a
committed CRLF file and the test passes while asserting nothing.

### Normalization

Each of these is present in the two real plugins, with the file that produced it.

- **`skills` and `tools` shapes vary.** `skills` appears as a flow sequence
  `[elements-of-style]` in `code-simplicity-review-agent.md` and as a block sequence in
  `flutter-reviewer.md`. `tools` appears as one comma-separated string,
  `Read, Glob, Grep, Bash, mcp__dart__analyze_files`. Normalize both to `List<String>`,
  accepting a flow sequence, a block sequence, or a bare string.
- **`effort` is optional and real.** Present in 3 of 11 agents, all wingspan:
  `plan-splitting-agent.md`, `codebase-review-agent.md`, `code-simplicity-review-agent.md`.
- **`extra` must hold nested structures.** `flutter-reviewer.md` frontmatter carries a nested
  `hooks:` map containing lists of matchers. `toJson` must convert `YamlMap` and `YamlList`
  into plain `Map` and `List` with String keys before `jsonEncode`, or encoding throws. Test
  `extra` with a nested map, a list, an int, a bool, and a null.
- **Every `plugin.json` field except `name` is optional.** `vgv-wingspan@0.0.4` has no
  `license`. Unknown `plugin.json` keys go into `PluginMetadata.extra`, or metadata is lossy
  while agents are lossless.
- **Output must be deterministic.** Directory traversal order is not stable across platforms,
  so sort `plugins` by name, `agents` by id, and `extra` keys, and end the file with a
  newline. Build `id` with `p.split(...).join('/')` so Windows does not emit
  `codebase-review\vgv-review-agent` and flake the golden fixture.

### Model values are carried, never translated

Four of eleven real agents use `model: inherit`. The rest use `sonnet` and `haiku`, which are
Claude aliases with no Codex equivalent. Writing any of these into a Codex `model` field
produces an agent pointed at a model that does not exist.

The parser carries the value verbatim. Translating it belongs to the per-harness mapping
config, which the CLI will own in a follow-up plan. This plan must not bake a Codex default
into the parser.

### Agent identity

Agent nesting is inconsistent. `vgv-wingspan` nests one level
(`agents/codebase-review/vgv-review-agent.md`), `vgv-ai-flutter-plugin` is flat
(`agents/flutter-reviewer.md`). Both must parse.

`id` is the path relative to `agents/` with `.md` stripped. A duplicate `id` within one plugin
is a hard error naming both source paths, never last-write-wins. Codex writes to a flat
directory, so the brick derives a filename from `id`, and it cannot resolve a collision that
already happened upstream.

`name` and the filename can legally disagree. `id` drives output naming.

### Failure is loud

One sealed family, so the follow-up command layer can switch exhaustively:

```dart
sealed class PluginException implements Exception {
  const PluginException(this.path, this.message);
  final String path;
  final String message;
  @override
  String toString() => '$runtimeType: $path: $message';
}
```

`implements Exception`, not `extends Error`, because very_good_analysis 11 enables
`only_throw_errors`. Subclasses cover: missing or malformed `.claude-plugin/plugin.json`,
missing `agents/` or zero agents parsed, malformed YAML including duplicate keys, a duplicate
agent `id`, and an unreadable file. That last one is a single branch wrapping every read
failure with its path, which covers bad encoding and permissions without a special case for
either.

Zero agents is a hard error. An empty manifest generates nothing and would otherwise exit 0
with the user seeing no output and no reason.

Warnings are deferred. There is nothing to warn about until a harness mapping config exists to
declare what is unmappable.

## Technical Considerations

**Architecture.** `lib/src/plugins/` holds `models/`, `frontmatter.dart`,
`plugin_parser.dart`, `plugin_exception.dart`, `git_client.dart`, and `plugin_cache.dart`.
`plugins.dart` is the single barrel, matching the `lib/src/commands/commands.dart` precedent.
No nested `models/models.dart`, which would be a second barrel with one consumer. No new
package: a separate `vgv_ai_plugins` package adds workspace and CI plumbing for exactly one
consumer.

**Scaffold syntax conventions a new author will not reproduce by default.** Every class in
`lib/src/` declares its unnamed constructor as `new({...})`, not `ClassName({...})`. Every
test double uses a semicolon body with a leading underscore,
`class _MockGitClient extends Mock implements GitClient;`, declared in the test file that uses
it. Every public class carries `{@template snake_case_class_name}` on the class and
`{@macro snake_case_class_name}` on the constructor, even though `public_member_api_docs` is
disabled.

**Dependency injection.** The scaffold has two patterns: `required this._logger` for a
collaborator the caller must supply, and a nullable parameter with a real default in the
initializer. `GitClient` and the cache root both have production defaults, so they take the
second form:

```dart
new({GitClient? gitClient, Directory? cacheRoot})
  : _gitClient = gitClient ?? ProcessGitClient(),
    _cacheRoot = cacheRoot ?? defaultCacheRoot();
```

**Coverage.** CI enforces 100 percent. Every branch needs a test, which is why `GitClient` is
an interface, the cache root is injectable, and `PluginParser` takes a `Directory`. The sealed
exception's `toString()` needs its own test or the gate rejects it.

**Test conventions.** Test paths mirror `lib/`. Groups are named for the type under test,
`group('PluginParser', ...)`, with nested groups per method, rather than the scaffold's
command-name style. `plugin_manifest_test.dart` deliberately covers the nested `toJson`
implementations of `ParsedPlugin`, `PluginMetadata`, and `PluginSource` through the root, so
those three get no separate test file. `plugin_agent_test.dart` is separate because the
`skills` and `tools` normalization logic lives there.

**Hermetic tests.** No test clones from a remote. `test/fixtures/sample_plugin/` is a small
plugin tree committed as plain files, covering nested and flat agents, a folded `>` and a
literal `|` description, a nested `hooks:` map in frontmatter, an unknown scalar key, a body
containing `---` lines, and a file with no frontmatter. `sample_plugin_manifest.json` is the
golden output. The fixture must not contain a nested `.git`. Phase 2 git tests build a real
repository at test time with `git init`, commit, tag, and clone from a `file://` URL.

**Spell-check.** `.github/workflows/vgv_ai_cli.yaml` runs cspell over `**/*.md` excluding only
`brick/**`. Add `!packages/vgv_ai_cli/test/fixtures/**/*.md` to the `includes` block, and add
real vocabulary such as `frontmatter`, `mocktail`, `Codex`, `cspell`, `mustache`, and
`subagent` to the empty `words: []` array in `.github/cspell.json`, which exists for exactly
this. Do not exclude `docs`, which would disable spell-checking for every future plan in the
repository.

**Dependencies.** `yaml: ^3.1.4` and `path: ^1.9.1` go under `dependencies`, not
`dev_dependencies`. Both are transitive today, but very_good_analysis enables
`depend_on_referenced_packages` and CI runs `--fatal-infos`, so importing either from `lib/`
without declaring it fails analyze. The tracked root `pubspec.lock` gets rewritten by
`dart pub get` in a workspace, so it is a touched file.

**Git subprocess hygiene, trimmed.** Set `GIT_TERMINAL_PROMPT=0` and apply a timeout. Without
the env var an HTTPS clone of a private repo with no TTY hangs forever rather than failing.
`dart:io` offers no process-group control and `process.kill()` reaches only the direct child,
so do not claim to kill git's transport helpers. Clone with `--depth 1 --single-branch
--no-tags`. Clearing `GIT_ASKPASS` and `SSH_ASKPASS` is deferred: both target plugins are
public, and every extra branch costs a test under the 100 percent gate.

**Cache integrity, defensive rather than observed.** Clone into a temp sibling and rename
atomically so an interrupted clone never leaves a directory that validates. Check a cache hit
with `git rev-parse HEAD` rather than directory existence. Cache root is constructor-injectable
so tests do not pollute the developer machine, defaulting to `XDG_CACHE_HOME` when set and
otherwise `$HOME/Library/Caches/vgv_ai_cli` on macOS and `$HOME/.cache/vgv_ai_cli` elsewhere.
`XDG_CACHE_HOME` is usually unset on macOS, so the fallback is the common path, not the edge.

**Security.** Cloning arbitrary git URLs pulls remote-controlled content. The clone runs with
no submodule recursion and no hook execution, and the CLI never executes anything from a
cloned repository. Plugin `hooks/` scripts are read as data only.

## Implementation Phases

### Phase 1: Models, parser, golden fixture

- **Status:** Done
- **Scope:** Parse layer over a local directory. Models, sealed exceptions, frontmatter
  splitter, normalization, deterministic serialization, committed fixture tree and golden
  manifest. No network. This phase unblocks the brick workstream.
- **Files touched:** `packages/vgv_ai_cli/lib/src/plugins/models/plugin_manifest.dart`,
  `.../models/parsed_plugin.dart`, `.../models/plugin_metadata.dart`,
  `.../models/plugin_agent.dart`, `.../models/plugin_source.dart`,
  `packages/vgv_ai_cli/lib/src/plugins/frontmatter.dart`,
  `packages/vgv_ai_cli/lib/src/plugins/plugin_parser.dart`,
  `packages/vgv_ai_cli/lib/src/plugins/plugin_exception.dart`,
  `packages/vgv_ai_cli/lib/src/plugins/plugins.dart`,
  `packages/vgv_ai_cli/pubspec.yaml`, `pubspec.lock`,
  `.github/workflows/vgv_ai_cli.yaml`, `.github/cspell.json`,
  `packages/vgv_ai_cli/test/src/plugins/frontmatter_test.dart`,
  `packages/vgv_ai_cli/test/src/plugins/plugin_parser_test.dart`,
  `packages/vgv_ai_cli/test/src/plugins/plugin_exception_test.dart`,
  `packages/vgv_ai_cli/test/src/plugins/models/plugin_manifest_test.dart`,
  `packages/vgv_ai_cli/test/src/plugins/models/plugin_agent_test.dart`,
  `packages/vgv_ai_cli/test/fixtures/sample_plugin/**`,
  `packages/vgv_ai_cli/test/fixtures/sample_plugin_manifest.json`,
  `packages/vgv_ai_cli/tool/generate_golden.dart`

  `tool/generate_golden.dart` was added beyond the original list. The golden fixture needs a
  reproducible way to regenerate, and the alternative is hand-editing JSON. It sits outside
  `lib/` so it is neither coverage-gated nor analyzed by CI, which analyzes `lib test` only.
- **Acceptance criteria:** Parsing the fixture produces JSON equal to the golden manifest. A
  body containing `---` lines survives intact for both folded and literal descriptions. A
  nested `hooks:` map round-trips through `extra` into JSON. `tools` as a comma-separated
  string becomes a list. Duplicate `id`, missing `plugin.json`, and zero agents each throw a
  distinct `PluginException` subclass. Output ordering is stable and `id` uses forward slashes.
- **Validation:** `cd packages/vgv_ai_cli && dart test test/src/plugins/`

### Phase 2: Git fetch and cache

- **Status:** Not started
- **Scope:** `GitClient` interface with `ProcessGitClient`, shallow tag-pinned clone into an
  injectable cache root, atomic temp-then-rename, cache validation via `git rev-parse`, ref
  resolved to a SHA on `PluginSource`, `GIT_TERMINAL_PROMPT=0`, and a subprocess timeout.
- **Files touched:** `packages/vgv_ai_cli/lib/src/plugins/git_client.dart`,
  `packages/vgv_ai_cli/lib/src/plugins/plugin_cache.dart`,
  `packages/vgv_ai_cli/lib/src/plugins/plugins.dart`,
  `packages/vgv_ai_cli/test/src/plugins/git_client_test.dart`,
  `packages/vgv_ai_cli/test/src/plugins/plugin_cache_test.dart`
- **Acceptance criteria:** A fake `GitClient` drives clone, cache hit, and every failure path.
  Missing `git`, a bad ref, a clone failure, and a timeout each produce a distinct actionable
  error. An interrupted clone never yields a cache entry that validates. No test reaches the
  network.
- **Validation:** `cd packages/vgv_ai_cli && dart test test/src/plugins/`

## Success Criteria

```success-criteria
GOAL: vgv_ai_cli turns one or more Claude plugin directories into a single versioned, deterministic JSON manifest of their agents, losslessly and with no network access in tests, so mason bricks have a stable contract to generate harness-specific output against.

SUCCESS CRITERIA:
- Parsing the committed fixture tree produces JSON byte-equal to the committed golden manifest | verify: cd packages/vgv_ai_cli && dart test test/src/plugins/plugin_parser_test.dart
- A markdown body containing lines that are exactly `---` is preserved in full rather than truncated, for both folded and literal descriptions | verify: cd packages/vgv_ai_cli && dart test test/src/plugins/frontmatter_test.dart
- CRLF input parses to the same manifest as the LF equivalent, asserted from a Dart string literal rather than a committed file | verify: cd packages/vgv_ai_cli && dart test test/src/plugins/frontmatter_test.dart
- A nested frontmatter map such as `hooks:` round-trips through `extra` into valid JSON, alongside a list, an int, a bool, and a null | verify: cd packages/vgv_ai_cli && dart test test/src/plugins/models/plugin_manifest_test.dart
- `skills` as a flow sequence, a block sequence, or a bare string, and `tools` as a comma-separated string, all normalize to List<String> | verify: cd packages/vgv_ai_cli && dart test test/src/plugins/models/plugin_agent_test.dart
- `model` values including `inherit`, `sonnet`, and `haiku` are carried verbatim with no translation in the parser | verify: cd packages/vgv_ai_cli && dart test test/src/plugins/plugin_parser_test.dart
- Duplicate agent id, missing plugin.json, malformed YAML, an unreadable file, and zero agents each throw a distinct PluginException subclass naming the offending path | verify: cd packages/vgv_ai_cli && dart test test/src/plugins/plugin_exception_test.dart test/src/plugins/plugin_parser_test.dart
- Serialization is deterministic: plugins sorted by name, agents sorted by id, extra keys sorted, agent ids forward-slashed, trailing newline | verify: cd packages/vgv_ai_cli && dart test test/src/plugins/models/plugin_manifest_test.dart
- Every clone, cache-hit, cache-corruption, missing-git, bad-ref, and timeout path is exercised through a fake GitClient plus a local file:// repository, with no network access | verify: cd packages/vgv_ai_cli && dart test test/src/plugins/
- Static analysis is clean at the CI strictness level | verify: cd packages/vgv_ai_cli && dart analyze --fatal-infos --fatal-warnings lib test
- Formatting matches CI | verify: cd packages/vgv_ai_cli && dart format --set-exit-if-changed .
- Spell-check passes with fixtures excluded and real vocabulary added, without disabling docs | verify: manual 1. Confirm .github/workflows/vgv_ai_cli.yaml excludes only packages/vgv_ai_cli/test/fixtures from the cspell includes block and still covers docs. 2. Confirm .github/cspell.json words is no longer empty. 3. Confirm the spell-check job is green on the PR.
- Test coverage is 100 percent, matching the CI gate | verify: manual 1. Confirm very_good is 1.5.0 or newer, since 1.3.0 exits 69 on this workspace without running anything. 2. Invoke the very_good_cli MCP test tool against packages/vgv_ai_cli with dart true, coverage enabled, and minimum coverage 100. 3. Confirm it exits green. A repository hook blocks both dart test and very_good test in the shell, so every dart test command listed above must also be run through that MCP tool rather than the shell.
- The real vgv-wingspan and vgv-ai-flutter-plugin repositories parse together into one manifest | verify: manual 1. Clone both at tags v0.0.4 and v0.0.5 into temp dirs. 2. Run the parser over both from a scratch Dart script. 3. Confirm the manifest lists 2 plugins and 11 agents total, that flutter-reviewer carries its nested hooks map in extra, and that code-simplicity-review-agent carries its skills list and full body.

NON-GOALS:
- Parsing skills, commands, hooks, or .mcp.json. Agents only in this slice.
- Mason bricks or any harness-specific emission. Separate workstream.
- The per-harness mapping config. The CLI will own it, in a follow-up plan. Nothing here may bake a Codex default into the parser.
- A user-facing CLI command, and therefore exit-code and stdout-versus-stderr policy. The library plus the golden fixture is the deliverable.
- Where the list of plugin repositories comes from. Explicit repo and ref arguments only.
- Code generation. Hand-written toJson, no fromJson, no json_serializable.
- Value equality on models and any equatable dependency. The golden test compares encoded JSON.
- Re-exporting from lib/vgv_ai_cli.dart. Mason generation runs in-process in this same package, so lib/src/ is correct.
- Symlink handling. 29 exist in these plugins, all under skills/, none under agents/. It becomes real in the skills slice.
- BOM stripping. Neither real plugin has one, so it is unevidenced hardening.
- Clearing GIT_ASKPASS and SSH_ASKPASS, killing git's transport helpers, cache eviction, orphan pruning of previously generated files, and re-verifying a moved tag on a cache hit.

VERIFICATION COMMAND: cd packages/vgv_ai_cli && dart format --set-exit-if-changed . && dart analyze --fatal-infos --fatal-warnings lib test && dart test
```

## Success Metrics

- Adding a second harness requires a brick and a config entry, with no change to
  `lib/src/plugins/`.
- The brick workstream builds against the golden manifest without waiting on this workstream.
- No agent content is lost between the source markdown and the manifest.

## Dependencies & Risks

**Running the gate locally takes a specific invocation.** A repository hook blocks both
`dart test` and `very_good test` in the shell. The `very_good_cli` MCP tool it redirects to
resolves its binary once per session, so it can hold a `very_good` older than the 1.5.0 CI
pins and exit 69 without running anything, which no reconnect fixes.

What does work, and what Phase 1 was verified with:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings lib test
dart run test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
```

`dart run test` is permitted by the hook and is the same form the workflow's `verify-version`
job already uses. The `dart test` commands in the success criteria document what CI runs.

**100 percent coverage on an I/O layer.** Every error branch in `ProcessGitClient` needs a
test. Mitigated by a thin implementation behind an interface, an injectable cache root, and
the trimmed subprocess hardening, but this is the most likely place the gate bites.

**The manifest contract will move.** `schemaVersion` turns drift into a loud failure instead
of a wrong TOML file. Agree bump rules and consumer failure behavior with the brick
workstream before the fixture is treated as frozen.

**Claude-only references survive into agent bodies.** `${CLAUDE_PLUGIN_ROOT}`, `skill://`
URIs, and `/skill-name` invocations mean nothing on another harness. Carrying them verbatim
is correct for a lossless parser, and deciding what to do about them is a mapping-config
question. Flagged so it is not discovered late.

**`git` must be on PATH.** Phase 2 shells out, and the CI runner needs it for the `file://`
clone tests.

## References & Research

- Brainstorm: [2026-09-17-plugin-parsing-and-retrieval](../brainstorm/2026-09-17-plugin-parsing-and-retrieval-brainstorm-doc.md)
- `new({...})` constructor and `{@template}` conventions:
  `packages/vgv_ai_cli/lib/src/commands/sample_command.dart`,
  `packages/vgv_ai_cli/lib/src/command_runner.dart`
- Nullable-with-default DI: `packages/vgv_ai_cli/lib/src/commands/update_command.dart`
- Semicolon-body mocks: `packages/vgv_ai_cli/test/src/commands/sample_command_test.dart`
- CI gates, cspell glob: `.github/workflows/vgv_ai_cli.yaml`
- Empty `words: []` ready for vocabulary: `.github/cspell.json`
- `only_throw_errors` and `depend_on_referenced_packages` active in very_good_analysis 11.0.0
- Nested `hooks:`, comma-separated `tools:`, folded `>` description, `model: inherit`:
  `vgv-ai-flutter-plugin@0.0.5/agents/flutter-reviewer.md`
- `effort:` present in 3 of 11 agents: `vgv-wingspan@0.0.4/agents/analysis/plan-splitting-agent.md`,
  `.../codebase-review/codebase-review-agent.md`, `.../codebase-review/code-simplicity-review-agent.md`
- Body `---` collision evidence, 14 occurrences:
  `vgv-ai-flutter-plugin@0.0.5/skills/green-gate/SKILL.md`
- Missing `license` key: `vgv-wingspan@0.0.4/.claude-plugin/plugin.json`
- Target format reference: https://github.com/proflead/codex-agents-library/blob/main/.codex/agents/research_agent.toml
- `package:yaml` 3.1.4, `package:path` 1.9.1
- `package:front_matter` rejected, last published 2019-06-16, `sdk: >=2.0.0 <3.0.0`
