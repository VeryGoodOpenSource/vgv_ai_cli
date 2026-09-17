# agents

Staging output for `vgv_ai install`.

This brick does not write to your home directory. It renders into a staging
directory, and the CLI reconciles that staging output against your real config:
settings files are deep merged, and the instruction block is swapped in between
its `<!-- vgv:begin -->` and `<!-- vgv:end -->` markers. Generating straight
into `$HOME` would clobber settings you own.

## What it generates

| file | goes to |
| --- | --- |
| `vgv_block.md` | the instruction block for every harness memory file |
| `claude_settings.fragment.json` | `~/.claude/settings.json` |
| `gemini_settings.fragment.json` | `~/.gemini/settings.json` |
| `codex_config.fragment.toml` | `~/.codex/config.toml` |
| `opencode.fragment.json` | `~/.config/opencode/opencode.json` |
| `pi_settings.fragment.json` | `~/.pi/agent/settings.json` |

Each fragment is generated only when its harness flag is set. `vgv_block.md` is
always generated.

## Variables

`claude`, `gemini`, `codex`, `opencode` and `pi` select harnesses. At least one
must be set or `pre_gen` fails. `marketplace` names the Claude Code marketplace
hosting the VGV plugins, and `skills_root` is where the translated skills live.

`skills`, `agents` and `mcp_servers` are supplied by the CLI from the resolved
plugins rather than prompted for. They default to empty, so `mason make` works
standalone.

## Partials

The shared prose lives in partials, so a change to `{{~ testing.md }}` reaches
every harness at once. Three constraints are worth knowing before editing them:

- Partials must sit at the root of `__brick__`. Mason keys them by their path
  relative to `__brick__`, so `{{> shared/x.md }}` will never resolve a file in
  a subdirectory.
- Partials render leniently. A mistyped name becomes an empty string rather
  than an error, which is why `agents_bundle_test.dart` asserts that no
  output file is empty or still contains mustache syntax. Run it after any edit.
- Use triple mustache for anything containing a path. `{{skills_root}}` HTML
  escapes the slashes; `{{{skills_root}}}` does not.

## Regenerating the bundle

The bundle is committed and CI fails if it drifts:

```sh
./tool/generate_agents_bundle.sh
```
