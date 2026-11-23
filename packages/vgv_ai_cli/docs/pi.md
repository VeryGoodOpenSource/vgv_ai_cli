# Pi

- **Flag:** `pi`
- **Executable:** `pi`
- **Config directory:** `~/.pi/agent`

| What         | Where                                  |
| ------------ | -------------------------------------- |
| Skills       | `~/.agents/skills`, shared             |
| Instructions | `~/.pi/agent/AGENTS.md`, VGV's section |
| Prompts      | `~/.pi/agent/prompts/*.md`             |

Pi is minimal by design. It has no subagents, no MCP, and no declarative hooks,
so it gets none of the agents, MCP servers, or hooks, and `install` notes what
it left out. It reads the shared skills and `AGENTS.md` without any settings.
