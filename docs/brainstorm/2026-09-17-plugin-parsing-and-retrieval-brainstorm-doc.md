---
date: 2026-09-17
topic: plugin-parsing-and-retrieval
---

# Plugin parsing and retrieval

## What We're Building

The retrieval and parsing half of harness generation in `vgv_ai_cli`. The CLI fetches
Claude plugin repositories, parses their structured contents into typed Dart models, and
hands a JSON manifest to mason bricks that emit harness-specific output such as Codex
agent TOML.

Claude plugins stay the single maintained source. Adding support for a new harness means
adding a brick and a config entry, never hand-copying skills or agents.

Work splits in two. This document covers fetch, parse, and the manifest contract. Marcos
owns mason bricks and hooks, consuming the manifest.

## Why This Approach

Three structures were considered.

A separate `vgv_ai_plugins` package gives a hard boundary and independent versioning, but
adds workspace and CI plumbing for exactly one consumer. Rejected as premature.

A two-step disk interface, where a sync command writes `.vgv/manifest.json` and an install
command reads it, is inspectable and decoupled, but introduces on-disk state that goes
stale and splits one user action into two commands. Rejected.

Chosen: parsing lives at `packages/vgv_ai_cli/lib/src/plugins/` and the manifest is passed
in memory as mason vars. A committed golden manifest fixture serves as the written contract
between the two halves, so brick work starts before the parser is finished.

## Key Decisions

- **Fetch by shallow, tag-pinned git clone into a CLI-owned cache.** Reading the local
  `~/.claude/plugins/cache` would be faster and needs no network, but it requires Claude
  Code to be installed with the plugin already present. That defeats the entire point,
  which is serving users on other harnesses. Cloning also makes version pinning free.

- **The model mirrors the Claude plugin structure faithfully.** Claude is the only source
  today. A neutral capability abstraction would be designed against imagined second
  sources. Build it when a second source actually exists.

- **First slice is agents only.** The Claude agent frontmatter maps near 1:1 to Codex agent
  TOML, so it proves the pipeline end to end with the fewest unknowns. Ten agents already
  exist in wingspan as test input. Skills follow, since they add directory-shaped output,
  `references/` files, and frontmatter with no Codex equivalent.

- **Parsing is lossless and mapping is declarative.** The parser keeps every frontmatter
  key, including ones the model does not know, in an `extra` map. Per-harness config
  declares which fields map where. Anything unmapped is surfaced as a warning rather than
  dropped in silence. This is what makes "add a harness by adding config" true instead of
  aspirational.

- **Hooks do mechanical shaping only.** Case conversion, filename derivation, path layout.
  No semantic parsing in hooks, because that is untestable in Dart and every new harness
  would reimplement the same frontmatter reader.

- **A golden manifest fixture is committed first.** `test/fixtures/` holds a frozen JSON
  manifest generated from wingspan. It is the contract, the parser's regression test, and
  Marcos's brick input, all at once.

## Source and Target Shapes

Observed in `vgv-wingspan@0.0.4` and `vgv-ai-flutter-plugin@0.0.5`.

| Path | Contents |
|---|---|
| `.claude-plugin/plugin.json` | name, version, description, author, homepage, repository, license, keywords |
| `agents/**/*.md` | YAML frontmatter plus markdown body |
| `skills/<name>/SKILL.md` | frontmatter, body, sibling `references/` files |
| `hooks/hooks.json` | event matchers and shell commands |
| `.mcp.json` | MCP server definitions |

Agent frontmatter keys in use: `name`, `description`, `model`, `effort`, `skills`.

Skill frontmatter keys in use: `name`, `description`, `when_to_use`, `compatibility`,
`user-invocable`, `argument-hint`, `effort`, `allowed-tools`, `disable-model-invocation`.

Codex agent TOML fields: `name`, `description`, `model`, `model_reasoning_effort`,
`sandbox_mode`, `nickname_candidates`, `developer_instructions`. The entire markdown body
collapses into `developer_instructions`, prefixed by Codex-specific boilerplate.

Two real gaps exist in the agent mapping. Claude's `skills` list has no Codex field, and
Codex's `sandbox_mode` has no Claude source.

## Model Sketch

```
PluginManifest
  source     PluginSource      repo, ref, resolvedSha
  metadata   PluginMetadata    from plugin.json
  agents     List<PluginAgent>

PluginAgent
  id          String            path-derived, e.g. codebase-review/code-simplicity-review-agent
  name        String
  description String            may be multi-line and contain embedded XML
  model       String?
  effort      String?
  skills      List<String>
  body        String            markdown after the frontmatter
  extra       Map<String, dynamic>   unrecognized frontmatter, preserved
```

`PluginManifest.toJson()` is the mason vars map.

## Open Questions

- Agent descriptions in wingspan embed `<examples>` XML blocks that are Claude prompt
  scaffolding. Codex descriptions read as one-liners. Does the Codex mapping take the full
  description, the first paragraph, or a new explicit short-description field in the source?

- Where does the list of plugin repos come from? Marketplace repo was explicitly deferred,
  so the options are CLI config, a hardcoded default set, or a command flag.

- Codex `sandbox_mode` has no Claude source. Default per harness in config, or derive it
  from an agent's `allowed-tools`?

- Codex filenames are snake_case and flat. Claude agent paths are kebab-case and nested
  under category folders. Does nesting flatten, and how are collisions handled?

- Cache location and invalidation policy for cloned repos. Does a tag refetch, and is there
  an explicit refresh command?

- Should the manifest carry its own schema version so bricks can fail loudly on drift?
