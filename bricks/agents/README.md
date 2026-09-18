# agents

Staging output for `vgv_ai install`.

This brick does not write to your home directory. It renders full config files
into a per-harness staging directory, and the CLI reconciles that staging
output against your real config: settings files are deep merged so keys you own
are preserved. Generating straight into `$HOME` would clobber them.

## What it generates

| file                     | goes to                            |
| ------------------------ | ---------------------------------- |
| `claude/settings.json`   | `~/.claude/settings.json`          |
| `gemini/settings.json`   | `~/.gemini/settings.json`          |
| `gemini/AGENTS.md`       | `~/.gemini/AGENTS.md`              |
| `codex/config.toml`      | `~/.codex/config.toml`             |
| `codex/AGENTS.md`        | `~/.codex/AGENTS.md`               |
| `opencode/opencode.json` | `~/.config/opencode/opencode.json` |
| `opencode/AGENTS.md`     | `~/.config/opencode/AGENTS.md`     |
| `pi/settings.json`       | `~/.pi/agent/settings.json`        |

Each harness folder is generated only when its flag is set. Every generated
file is a complete config file rather than a fragment of one.

## Partials

The harnesses that read shared agent instructions (`gemini`, `codex` and
`opencode`) each ship an identical `AGENTS.md`. Rather than duplicating it per
folder, the body lives in the `{{~ agents.md }}` mason partial and each folder's
`AGENTS.md` includes it with `{{> agents.md }}`. The partial renders the
resolved `skills` and `agents` so every harness shares the same guidance.

## Variables

`claude`, `gemini`, `codex`, `opencode` and `pi` select harnesses. At least one
must be set or `pre_gen` fails. `skills_root` is where the translated skills
live. The Claude Code marketplace hosting the VGV plugins is fixed to
`VeryGoodOpenSource/very_good_claude_marketplace`.

`skills`, `agents` and `mcp_servers` are supplied by the CLI from the resolved
plugins rather than prompted for. They default to empty, so `mason make` works
standalone.

## Settings

Each settings file is rendered from a var the `pre_gen` hook builds. The hook
models every settings file as a class under `hooks/lib/models` and serializes
it with `json_serializable`, so the shape of each settings file lives in code
rather than in mustache. Use triple mustache for anything containing a path.
`{{skills_root}}` HTML escapes the slashes; `{{{skills_root}}}` does not.

The models rely on generated `*.g.dart` code. Regenerate it after changing a
model:

```sh
cd hooks && dart run build_runner build
```

## Regenerating the bundle

The bundle is committed and CI fails if it drifts:

```sh
tool/generate_agents_bundle.sh
```
