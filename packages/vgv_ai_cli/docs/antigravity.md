# Antigravity CLI

- **Flag:** `antigravity`
- **Executable:** `agy`
- **Config directory:** `~/.gemini/config`

Everything goes into one Antigravity plugin, `~/.gemini/config/plugins/vgv/`,
in the config Antigravity CLI shares with the Antigravity IDE.

| What     | Where, under `plugins/vgv/` |
| -------- | --------------------------- |
| Manifest | `plugin.json`               |
| Skills   | `skills/`, its own copy     |
| Settings | `mcp_config.json`, merged   |
| Agents   | `agents/*.md`               |
| Hooks    | `hooks.json`, `hooks/`      |

Antigravity doesn't read `~/.agents/skills`, so the plugin keeps its own copy
of the skills, and each skill is a `/<name>` command on its own. The skills
and agents register natively, so there is no instructions file.

## Hooks

The hook scripts are copied to `plugins/vgv/hooks/`, with
`vgv-claude-compat.sh` beside them. Hooks on events Antigravity lacks, and
hooks an agent declares for itself, are left out. After a tool runs,
Antigravity reads nothing a hook says, so those hooks run but the agent hears
none of it. The scripts are `#!/bin/bash` and call `jq`, so `jq` has to be on
your path.
