# Codex

- **Flag:** `codex`
- **Executable:** `codex`
- **Config directory:** `~/.codex`

| What         | Where                                    |
| ------------ | ---------------------------------------- |
| Skills       | `~/.agents/skills`, shared               |
| Settings     | `~/.codex/config.toml`, merged           |
| Instructions | `~/.codex/AGENTS.md`, VGV's section      |
| Agents       | `~/.codex/agents/*.toml`                 |
| Hooks        | `~/.codex/hooks.json`, `~/.codex/hooks/` |

`config.toml` gets the MCP servers as `[mcp_servers.<name>]` tables, keeping
your comments and layout unless `--force` has to rewrite it.

A skill that only you may start gets an `agents/openai.yaml` in its shared
copy that turns off implicit invocation, so Codex runs it only when you name
it.

## Hooks

The hook scripts are copied to `~/.codex/hooks/<plugin>/`, with
`vgv-claude-compat.sh` beside them so a script written for Claude Code gets the
payload it expects. The scripts are `#!/bin/bash` and call `jq`, so `jq` has
to be on your path.
