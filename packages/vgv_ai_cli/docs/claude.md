# Claude Code

- **Flag:** `claude`
- **Executable:** `claude`
- **Config directory:** `~/.claude`

Claude Code installs the VGV plugins natively, so `vgv_ai` only points it at
the VGV marketplace. `install` merges two keys into `~/.claude/settings.json`:
`extraKnownMarketplaces`, which adds the marketplace, and `enabledPlugins`,
which enables each plugin you install.

The plugin system then installs the skills, agents, MCP servers, and hooks as
their authors wrote them, so nothing is translated or copied into
`~/.agents/skills`.
