# Implementation Plan: Harness-Neutral Parsing (Model + Parser split)

## Overview
Reshape the `packages/vgv_ai_cli/lib/src/plugin_source/` parsing layer into a
hub-and-spoke shape (Direction B of `docs/ideas/harness-neutral-parsing.md`): a
harness-neutral, portable-by-construction model (the hub), a single
`ClaudePluginParser` that is the only place that knows what "Claude-specific"
means (the first spoke), and a shared `ConfigMap` value-access layer that
replaces the three ad-hoc parsing styles (`_string`/`_stringList`/`_plain`
YAML getters, imperative hooks-JSON walking, inline MCP-JSON coercion).

This is step 1 of an eventual N-decoder + N-encoder codec architecture. Nothing
built here should need rewriting when output harnesses later gain `decode`
counterparts — we only add the neutral hub and one input spoke now.

## Scope boundary (grounded in the code)
The change is confined to `lib/src/plugin_source/` and its tests. Confirmed by
inspection:
- `Frontmatter`, `PluginAssets`, `PluginAssetsReader`, `HookAsset`/`HookCommand`
  all live under `plugin_source/`, exported from `plugin_source.dart`.
- `claudeOnlyKeys` is a top-level const in `plugin_assets.dart`, physically
  separate from `Frontmatter` (frontmatter.dart) — the "different file than the
  class that knows those keys" smell the idea calls out.
- **No command wires the reader yet.** `grep` finds no use of
  `PluginAssetsReader`/`PluginAssets` outside `plugin_source/`. The
  `bricks/agents/hooks` translators consume mustache **vars**, not these models,
  so this refactor has no downstream lib consumers to break — only the module's
  own tests (`test/src/plugin_source/frontmatter_test.dart`,
  `plugin_assets_test.dart`) must keep passing.

This makes the refactor low-blast-radius: correctness is defined entirely by the
existing plugin_source tests plus new tests for the new seams.

## Architecture Decisions
- **Composition, not inheritance.** The neutral model exposes only neutral
  fields; Claude-only keys (`allowed-tools`, `user-invocable`, `effort`,
  `when_to_use`, `disable-model-invocation`) do not exist on it. No
  `ClaudeFrontmatter extends Frontmatter`. Inheritance is reserved for the
  `PluginParser` *behavior* interface only.
- **New `model/` seam.** Neutral models move to
  `lib/src/plugin_source/model/` and parsers to
  `lib/src/plugin_source/parser/`, so parsers and (future) translators both
  depend on the model without depending on each other. (Resolves the first open
  question in the idea doc.)
- **`ConfigMap` is the shared foundation, landed first.** It is the
  highest-leverage cleanup and everything else reads cleaner once it exists, so
  it is Phase 1.
- **Claude-only keys are dropped at parse time, not carried as opaque
  metadata.** No output harness needs them and there is no round-trip
  requirement yet (resolves open question 3). Revisit only when a real
  `decode`/round-trip need appears.
- **MCP server config stays `Map<String, Object?>`.** No translator needs the
  structure; typed modeling is explicitly out of scope.
- **`PluginParser` returns a single aggregate (`PluginAssets`).** Hooks
  concatenate while skills/agents resolve by name, and `PluginAssets.merge`
  already owns exactly that distinction — keeping the aggregate return preserves
  it in one place (resolves open question 2).

## Assumptions validated during planning
- Claude is the only *input* dialect near-term — confirmed, no non-Claude
  reader exists. The parser seam is introduced anyway so a second spoke is
  additive.
- The neutral model can carry everything translators need — the only fields the
  brick vars consume are name/description/skills/body plus mcpServers and hook
  event/matcher/command; none of the Claude-only keys are read downstream.

## Task List

### Phase 1: Foundation
- [x] Task 1: Introduce the `ConfigMap` value-access layer

### Checkpoint: Foundation  ✅
- [x] `ConfigMap` has its own tests at 100% coverage; analyze + format clean
- [x] Full existing plugin_source suite still green (139 tests)

### Phase 2: Route existing parsing through ConfigMap
- [x] Task 2: Route YAML frontmatter accessors through `ConfigMap`
- [x] Task 3: Route hooks-JSON and MCP-JSON reading through `ConfigMap`

### Checkpoint: Unified accessors  ✅
- [x] All existing `plugin_source` tests pass unchanged in intent
- [x] Tolerant-of-missing/wrong-type behavior demonstrably preserved

### Phase 3: Neutral model + Claude parser
- [x] Task 4: Extract the neutral model into a `model/` seam and define the
      `PluginParser` interface
- [x] Task 5: Introduce `ClaudePluginParser` and move all Claude-only knowledge
      into it
- [x] Task 6: Give Skill/Agent/Hook neutral-model treatment and remove
      `PluginAssetsReader` in favor of `ClaudePluginParser` as the single entry
      point

### Checkpoint: Complete  ✅
- [x] Exactly one place (`ClaudePluginParser`) knows a key is Claude-specific
- [x] Neutral model is portable by construction (no Claude-only fields on it)
- [x] Full coverage run is green at 100% (407/407 lib lines); ready for review

## Risks and Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Coverage drops below 100% during the split (dead neutral getters, etc.) | High | Land each seam with its tests in the same task; run the MCP `test` tool at each checkpoint, not just at the end |
| Reshuffling `claudeOnlyKeys`/`portableFrontmatter` silently changes which keys are dropped | Med | Task 5 keeps the exact key set; add a parser test asserting the dropped-key set explicitly |
| `allowed-tools` regex + comma/space split behavior regresses when moved | Med | Move the parsing verbatim into the parser and keep the existing `animations`/`Bash(...)` edge-case assertions |
| New `model/`+`parser/` directories break `plugin_source.dart` exports | Low | Update the barrel export in the same task that moves a file; analyze is fatal-infos so a stale export fails fast |
| Dart 3.13 `new(...)` constructor syntax mis-"fixed" by an SDK mismatch | Low | Do not rewrite `new(...)` constructors; verify SDK is 3.13 per AGENTS.md before touching |

## Open Questions
- None blocking. The three open questions from the idea doc are answered under
  Architecture Decisions (model/ seam; aggregate return; drop-at-parse-time).
  Flag for human review at the Phase 3 checkpoint if any output translator turns
  out to need a Claude-only key as neutral metadata.
