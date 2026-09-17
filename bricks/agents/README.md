# agents

Staging output for `vgv_ai install`.

This brick does not write to your home directory. It renders into a staging
directory, and the CLI reconciles that staging output against your real config:
settings files are deep merged. Generating straight into `$HOME` would clobber
settings you own.

## What it generates

| file                            | goes to                            |
| ------------------------------- | ---------------------------------- |
| `claude_settings.fragment.json` | `~/.claude/settings.json`          |
| `gemini_settings.fragment.json` | `~/.gemini/settings.json`          |
| `codex_config.fragment.toml`    | `~/.codex/config.toml`             |
| `opencode.fragment.json`        | `~/.config/opencode/opencode.json` |
| `pi_settings.fragment.json`     | `~/.pi/agent/settings.json`        |

Each fragment is generated only when its harness flag is set.

## Variables

`claude`, `gemini`, `codex`, `opencode` and `pi` select harnesses. At least one
must be set or `pre_gen` fails. `skills_root` is where the translated skills
live. The Claude Code marketplace hosting the VGV plugins is fixed to
`VeryGoodOpenSource/very_good_claude_marketplace`.

`skills`, `agents` and `mcp_servers` are supplied by the CLI from the resolved
plugins rather than prompted for. They default to empty, so `mason make` works
standalone.

## Fragments

Each settings fragment is rendered from a var the `pre_gen` hook builds. The
hook models every fragment as a class under `hooks/lib/models` and serializes
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
