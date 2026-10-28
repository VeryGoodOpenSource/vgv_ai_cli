# vgv_ai_cli

`vgv_ai` is a command-line tool by Very Good Ventures that configures the Very
Good AI tooling for your coding agents. It installs the skills, agents, MCP
servers, and hooks from the VGV Claude Code plugins into Claude Code, Gemini
CLI, Codex, OpenCode, Pi, GitHub Copilot CLI, Antigravity CLI, and Devin CLI.

To install and use it, see the [`vgv_ai_cli` README](packages/vgv_ai_cli).

## Repository layout

This is a [pub workspace][pub_workspace_link] monorepo with one shared
`pubspec.lock` at the root.

| Path                                               | What it is                                                                    |
| -------------------------------------------------- | ----------------------------------------------------------------------------- |
| [`packages/vgv_ai_cli`](packages/vgv_ai_cli)       | The `vgv_ai` CLI.                                                             |
| [`packages/plugin_source`](packages/plugin_source) | Resolves the pinned VGV plugins and parses them into a harness-neutral model. |
| [`bricks/agents`](bricks/agents)                   | The Mason brick that lays out the files each harness reads.                   |
| [`tool`](tool)                                     | Scripts, such as the one that regenerates the brick bundle.                   |

## Contributing

To set up the repository and work on it, see the
[contributing guide](CONTRIBUTING.md). To teach the CLI a coding agent it does
not configure yet, see [adding a harness](ADDING_A_HARNESS.md).

[pub_workspace_link]: https://dart.dev/tools/pub/workspaces
