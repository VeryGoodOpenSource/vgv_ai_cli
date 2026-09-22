# plugin_source

Resolves the pinned VGV Claude Code plugins to a directory on disk and parses
them into a harness-neutral asset model.

The package splits into three layers, none of which knows about any harness
beyond its own parser:

- `format/` — tolerant decoders for the file formats plugins ship in (YAML
  frontmatter, hooks JSON, MCP JSON), collapsed into a single `ConfigMap` view.
- `model/` — the harness-neutral asset model every parser produces and every
  translator consumes.
- `parser/` — harness-specific parsers behind the `PluginParser` interface. A
  new input harness is one new implementation.

`sources`, `resolution`, and `plugin_ref` locate a plugin on disk (git clone or
local cache) before it is parsed.
