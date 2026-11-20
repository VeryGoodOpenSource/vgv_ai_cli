# Pi

- **Flag:** `pi`
- **Executable:** `pi`
- **Config directory:** `~/.pi/agent`

| What         | Where                                  |
| ------------ | -------------------------------------- |
| Skills       | `~/.agents/skills`, shared             |
| Settings     | `~/.pi/agent/mcp.json`, merged         |
| Instructions | `~/.pi/agent/AGENTS.md`, VGV's section |
| Prompts      | `~/.pi/agent/prompts/*.md`             |

`mcp.json` gets the MCP servers under `mcpServers`. Pi reads it from 0.99.0;
older versions ignore it. Turning a server off or changing its exposure in
Pi's `/mcp` writes keys `vgv_ai` didn't, so `doctor` doesn't report them as
drift.

Pi is minimal by design. It has no subagents and no declarative hooks, so it
gets none of the agents or hooks, and `install` notes what it left out. It
reads the shared skills and `AGENTS.md` without any settings.
