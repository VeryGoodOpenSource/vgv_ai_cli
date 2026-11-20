# Gemini CLI

- **Flag:** `gemini`
- **Executable:** `gemini`
- **Config directory:** `~/.gemini`

| What         | Where                                |
| ------------ | ------------------------------------ |
| Skills       | `~/.agents/skills`, shared           |
| Settings     | `~/.gemini/settings.json`, merged    |
| Instructions | `~/.gemini/AGENTS.md`, VGV's section |
| Agents       | `~/.gemini/agents/*.md`              |
| Commands     | `~/.gemini/commands/*.toml`          |

`settings.json` gets the MCP servers, and `context.fileName` set to
`AGENTS.md` and `GEMINI.md`, so Gemini reads the VGV section without
skipping its default `GEMINI.md`.

Gemini CLI gets no hooks.
