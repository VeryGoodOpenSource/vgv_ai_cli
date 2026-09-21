# Tasks: Harness-Neutral Parsing (Model + Parser split)

Plan: `tasks/plan.md`. All paths relative to `packages/vgv_ai_cli/`.

Verification commands (run from `packages/vgv_ai_cli`, per AGENTS.md):
- Analyze: `dart analyze --fatal-infos --fatal-warnings lib test`
- Format: `dart format --set-exit-if-changed .`
- Single test file: `dart run test test/src/plugin_source/<file>_test.dart`
- Full coverage (100% required): use the `very_good_cli` MCP `test` tool
  (the `dart test`/`very_good test` forms are hook-denied)

---

## Task 1: Introduce the `ConfigMap` value-access layer  ✅ DONE

**Description:** Create one shared, tolerant accessor over a
`Map<String, Object?>` that centralizes the behavior currently spread across
`Frontmatter._string`, `_stringList`, `_plain`, and the `is! Map` /
`Map<String, Object?>.from` coercions in `PluginAssetsReader`. It normalizes
parsed YAML/JSON (`YamlMap`/`YamlList` → plain collections) and offers
missing/wrong-type-tolerant reads: `string`, `stringList`, `child` (nested
map), `list`. No existing file consumes it yet — this task only lands the
foundation and its tests.

**Acceptance criteria:**
- [x] `ConfigMap` exposes tolerant `string(key)`, `stringList(key)`,
      nested-map (`child`), and `list` accessors (plus `integer`, `boolean`,
      `entries`, `operator []`, and static `maps`) that return null/empty on
      missing or wrong-typed values rather than throwing.
- [x] YAML `YamlMap`/`YamlList` and JSON `Map`/`List` inputs both normalize to
      plain Dart collections through one code path (absorbs `_plain`).
- [x] It carries no Claude-specific or YAML/JSON-specific knowledge (usable for
      frontmatter, hooks JSON, and MCP JSON alike).

**Verification:**
- [x] Tests pass: `dart run test test/src/plugin_source/config_map_test.dart`
      (29 pass)
- [x] Analyze clean: `dart analyze --fatal-infos --fatal-warnings lib test`
- [x] Format clean: `dart format --set-exit-if-changed .`
- [x] Manual check: 100% line coverage on `config_map.dart` (37/37 lines)

**Dependencies:** None

**Files likely touched:**
- `lib/src/plugin_source/config_map.dart` (new)
- `lib/src/plugin_source/plugin_source.dart` (export)
- `test/src/plugin_source/config_map_test.dart` (new)

**Estimated scope:** Small (2-3 files)

---

## Task 2: Route YAML frontmatter accessors through `ConfigMap`  ✅ DONE

**Description:** Replace `Frontmatter._string`/`_stringList`/`_plain` with
`ConfigMap`. `Frontmatter.parse` builds a `ConfigMap` from the decoded YAML
document; the getters (`name`, `description`, `skills`, and — for now —
`allowedTools`, `userInvocable`) read through it. Behavior, including the
one-line description flattening and the `allowed-tools` regex, is preserved
verbatim. (Claude-only getters move out in Task 5; this task is accessor
plumbing only.)

**Acceptance criteria:**
- [ ] `Frontmatter` no longer defines its own `_string`/`_stringList`/`_plain`;
      it delegates to `ConfigMap`.
- [ ] Every existing `frontmatter_test.dart` case passes with unchanged intent,
      including the `animations` comma-separated and `Bash(...)` scoped-tool
      cases and the folded/literal description flattening.
- [ ] Non-string YAML keys (e.g. unquoted `2:`) still stringify correctly.

**Verification:**
- [ ] Tests pass: `dart run test test/src/plugin_source/frontmatter_test.dart`
- [ ] Analyze clean; format clean
- [ ] Manual check: coverage on `frontmatter.dart` stays 100%

**Dependencies:** Task 1

**Files likely touched:**
- `lib/src/plugin_source/frontmatter.dart`
- `test/src/plugin_source/frontmatter_test.dart` (only if assertions need
  re-pointing; intent unchanged)

**Estimated scope:** Small (1-2 files)

---

## Task 3: Route hooks-JSON and MCP-JSON reading through `ConfigMap`  ✅ DONE

**Description:** Replace the imperative `is! Map` / `is! List` walking in
`PluginAssetsReader._readHooks`, `_readHookCommands`, and `_readMcpServers`
with `ConfigMap` accessors, so the tolerant behavior lives in one place. The
`PluginParseException`-on-corrupt-JSON contract (deliberately not a
`FormatException`) is preserved; only the traversal changes.

**Acceptance criteria:**
- [ ] Hooks and MCP readers traverse decoded JSON via `ConfigMap`, not ad-hoc
      `is! Map`/`is! List` checks.
- [ ] A malformed JSON file still throws `PluginParseException` (not
      `FormatException`); a well-formed-but-empty/absent one still yields empty
      collections.
- [ ] Existing `plugin_assets_test.dart` hook/MCP cases pass with unchanged
      intent, including per-hook `directory` carrying and `matcher` absence.

**Verification:**
- [ ] Tests pass: `dart run test test/src/plugin_source/plugin_assets_test.dart`
- [ ] Analyze clean; format clean
- [ ] Manual check: coverage on `plugin_assets.dart` stays 100%

**Dependencies:** Task 1

**Files likely touched:**
- `lib/src/plugin_source/plugin_assets.dart`
- `test/src/plugin_source/plugin_assets_test.dart` (if assertions need
  re-pointing; intent unchanged)

**Estimated scope:** Small (1-2 files)

---

## Checkpoint: Unified accessors (after Tasks 1-3)  ✅
- [x] All `plugin_source` tests pass (139); analyze + format clean
- [x] Tolerant missing/wrong-type behavior preserved for YAML, hooks JSON, MCP
- [x] Coverage still 100% across every `plugin_source` file

---

## Task 4: Extract the neutral model into a `model/` seam and define the `PluginParser` interface  ✅ DONE

**Description:** Create `lib/src/plugin_source/model/` holding the
portable-by-construction neutral models and `lib/src/plugin_source/parser/`
holding behavior interfaces. Move `SkillAsset`, `AgentAsset`, `PluginAssets`,
`HookAsset`, `HookCommand` into `model/` (mechanical move + export update; no
Claude-only fields removed yet — that is Task 5/6). Add a `PluginParser`
abstract interface (`PluginAssets parse(Directory root)`) in `parser/`. This
task is structural: it establishes the seams without changing behavior.

**Acceptance criteria:**
- [ ] Neutral models live under `model/`; the `PluginParser` interface lives
      under `parser/`; both re-exported from `plugin_source.dart`.
- [ ] The neutral model does not import anything Claude- or parser-specific
      (the hub depends on nothing above it).
- [ ] No behavior change: all existing tests pass after import updates.

**Verification:**
- [ ] Tests pass: `dart run test test/src/plugin_source/plugin_assets_test.dart`
- [ ] Analyze clean (fatal-infos catches any stale/unused export); format clean
- [ ] Manual check: `plugin_source.dart` barrel resolves; no dead exports

**Dependencies:** Task 3

**Files likely touched:**
- `lib/src/plugin_source/model/*.dart` (moved from `plugin_assets.dart`,
  `hooks.dart`)
- `lib/src/plugin_source/parser/plugin_parser.dart` (new interface)
- `lib/src/plugin_source/plugin_source.dart` (exports)
- `test/src/plugin_source/plugin_assets_test.dart` (import paths)

**Estimated scope:** Medium (4-5 files)

---

## Task 5: Introduce `ClaudePluginParser` and move all Claude-only knowledge into it  ✅ DONE

**Description:** Create `ClaudePluginParser` (implements `PluginParser`) as the
single place that knows Claude specifics. Move `claudeOnlyKeys`, the
`portableFrontmatter` filtering, and the `allowedTools` / `userInvocable`
parsing off `Frontmatter`/`SkillAsset` and into the parser. `Frontmatter`
becomes the neutral document model (`values` map + `name`/`description`/`skills`
/`body`) with no Claude-only getters. The parser produces neutral models from
that.

**Acceptance criteria:**
- [ ] `claudeOnlyKeys`, portable-frontmatter filtering, and `allowed-tools` /
      `user-invocable` parsing exist in exactly one place: `ClaudePluginParser`.
- [ ] The neutral `Frontmatter`/models expose no Claude-only field
      (portable by construction).
- [ ] A parser test asserts the exact dropped-key set
      (`user-invocable`, `disable-model-invocation`, `effort`, `when_to_use`)
      and preserves the `allowed-tools` regex edge cases (`animations` commas,
      `Bash(...)` scopes).

**Verification:**
- [ ] Tests pass:
      `dart run test test/src/plugin_source/parser/claude_plugin_parser_test.dart`
- [ ] Analyze clean; format clean
- [ ] Manual check: `grep` for `claudeOnlyKeys`/`allowed-tools`/`user-invocable`
      returns hits only inside the parser

**Dependencies:** Task 4

**Files likely touched:**
- `lib/src/plugin_source/parser/claude_plugin_parser.dart` (new)
- `lib/src/plugin_source/frontmatter.dart` (strip Claude-only getters)
- `lib/src/plugin_source/model/*.dart` (strip Claude-only fields)
- `test/src/plugin_source/parser/claude_plugin_parser_test.dart` (new)
- `test/src/plugin_source/frontmatter_test.dart` (drop moved-out assertions)

**Estimated scope:** Medium (5 files)

---

## Task 6: Remove `PluginAssetsReader`; make `ClaudePluginParser` the single entry point  ✅ DONE

**Description:** Fold the directory-walking read logic (`_readSkills`,
`_readAgents`, `_readMcpServers`, `_readHooks`) into `ClaudePluginParser` so
that reading Claude plugin files and producing neutral models is one unit, then
**remove `PluginAssetsReader`** — the parser is the single entry point (decided
with the user). Preserve `PluginAssets.merge` semantics (skills/agents resolve
by name and stay sorted; hooks concatenate) and all real-shape tolerances
(nested agent dirs, `skills/shared/` without SKILL.md, name-fallback to
basename).

**Acceptance criteria:**
- [ ] `PluginAssetsReader` is gone; reading a plugin directory goes through
      `ClaudePluginParser.parse(root)` and returns neutral `PluginAssets`.
- [ ] `merge` still resolves skills/agents by name (later wins, stays sorted)
      and concatenates hooks; `skills/shared/` without `SKILL.md` still survives
      and is not treated as a skill.
- [ ] All existing reader-behavior tests pass against the new entry point.

**Verification:**
- [ ] Tests pass: `dart run test test/src/plugin_source/plugin_assets_test.dart`
      and the parser test
- [ ] Analyze clean; format clean
- [ ] Manual check: no lib file outside `parser/` reads plugin files directly

**Dependencies:** Task 5

**Files likely touched:**
- `lib/src/plugin_source/parser/claude_plugin_parser.dart`
- `lib/src/plugin_source/plugin_assets.dart` (remove reader; keep neutral
  `PluginAssets`/`merge` if not already moved to `model/` in Task 4)
- `lib/src/plugin_source/plugin_source.dart` (drop reader export)
- `test/src/plugin_source/plugin_assets_test.dart` (re-point to parser)

**Estimated scope:** Medium (3-4 files)

---

## Checkpoint: Complete (after Tasks 4-6)  ✅
- [x] Exactly one place knows a key is Claude-specific (`ClaudePluginParser`):
      `claudeOnlyKeys`, `user-invocable` rule, and `allowed-tools` tokenization
      all live there; `grep` finds none of them elsewhere.
- [x] Neutral model has no Claude-only fields and no `.frontmatter` escape hatch
      (portable by construction; Claude keys survive only opaquely inside
      `SkillAsset.portableFrontmatter`).
- [x] Coverage 100% across the whole package (407/407 lib lines).
- [x] Analyze (`--fatal-infos --fatal-warnings`) + format clean across lib/test.
- [x] Full suite green: 170 passed, 1 skipped (version-verify tag).
- [ ] Human review before merge
