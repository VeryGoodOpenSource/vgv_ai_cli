# OpenCode

- **Flag:** `opencode`
- **Executable:** `opencode`
- **Config directory:** `~/.config/opencode`

| What         | Where                                         |
| ------------ | --------------------------------------------- |
| Skills       | `~/.agents/skills`, shared                    |
| Settings     | `~/.config/opencode/opencode.json`, merged    |
| Instructions | `~/.config/opencode/AGENTS.md`, VGV's section |
| Agents       | `~/.config/opencode/agent/*.md`               |
| Commands     | `~/.config/opencode/command/*.md`             |

`opencode.json` gets the MCP servers under `mcp`, and `AGENTS.md` under
`instructions`. Each agent is a subagent, so OpenCode delegates to it rather
than letting you drive it directly.

OpenCode gets no hooks.
