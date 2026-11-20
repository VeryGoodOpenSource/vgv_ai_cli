# GitHub Copilot CLI

- **Flag:** `copilot`
- **Executable:** `copilot`
- **Config directory:** `~/.copilot`

| What         | Where                                                   |
| ------------ | ------------------------------------------------------- |
| Skills       | `~/.agents/skills`, shared                              |
| Settings     | `~/.copilot/mcp-config.json`, merged                    |
| Instructions | `~/.copilot/copilot-instructions.md`, VGV's section     |
| Agents       | `~/.copilot/agents/*.agent.md`                          |
| Hooks        | `~/.copilot/hooks/vgv.json`, `~/.copilot/vgv_ai/hooks/` |

Copilot invokes skills by name, so it needs no commands.

## Hooks

Copilot reads every `*.json` under `~/.copilot/hooks/` as a hooks file, so the
hook scripts are copied to `~/.copilot/vgv_ai/hooks/` instead, with
`vgv-claude-compat.sh` beside them. A hook an agent declares for itself is left
out, since Copilot doesn't say which agent is running. The scripts are
`#!/bin/bash` and call `jq`, so `jq` has to be on your path.

## Copilot in VS Code

Skills that launch agents, such as `review`, need **Local** sessions in VS
Code. In **Copilot** sessions, Ask mode is read-only and cannot launch agents.

1. Switch the chat session to **Local**.
2. Under **Configure Tools**, enable the terminal and **Run Subagent**
   (`agent/runSubagent`).
