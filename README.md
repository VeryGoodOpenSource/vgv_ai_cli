# vgv_ai_cli

`vgv_ai` is a command-line tool by Very Good Ventures that configures the Very
Good AI tooling for your coding agents. It installs the skills, agents, MCP
servers, and hooks from the VGV Claude Code plugins into Claude Code, Gemini
CLI, Codex, OpenCode, Pi, GitHub Copilot CLI, and Antigravity CLI.

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

## Contributor setup

Install the prerequisites listed in [AGENTS.md](AGENTS.md#prerequisites)
first. The Dart version matters more than it looks: on 3.12 the analyze hook
reports errors against this codebase's Dart 3.13 syntax, and those errors read
as real ones.

This repo ships a committed agent configuration in `.claude/settings.json`,
which declares the `very-good-claude-code-marketplace` and enables the two VGV
plugins described in [AGENTS.md](AGENTS.md#agent-tooling).

### 1. Trust the folder

Open the repo in Claude Code and accept the trust prompt. The marketplace
resolves from the committed settings, so you don't need to run
`/plugin marketplace add`.

One exception: if you already have a marketplace registered under the name
`very-good-claude-code-marketplace`, that registration wins and the committed
pin is ignored. Check that `/plugin` shows the GitHub source. If it shows a
local directory instead, remove yours first.

### 2. Confirm the plugins installed, then restart

Run `/plugin` and check that both plugins show as enabled. Then restart the
session: settings apply immediately, but hooks and MCP servers only bind at
session start.

This step isn't optional bookkeeping. Wingspan normally nudges you when a
companion plugin is missing, but it decides "already installed" by looking for
the plugin name in `.claude/settings.json`, which this repo commits. If your
install silently failed, nothing tells you, and the agent carries on without
the hooks or quality gates.

### 3. Verify

Run this from `packages/vgv_ai_cli`:

```sh
dart pub get && dart analyze --fatal-infos --fatal-warnings lib test
```

For the full test and coverage gate, see
[AGENTS.md](AGENTS.md#common-commands), since some commands must go through
MCP tools rather than the shell. To browse a coverage report after a coverage
run, generate it with [lcov](https://github.com/linux-test-project/lcov):

```sh
genhtml coverage/lcov.info -o coverage/
open coverage/index.html
```

## Contributing

[AGENTS.md](AGENTS.md) holds the architecture, conventions, commands, and CI
reference for both humans and coding agents. Read it before you change code.
Commits and pull request titles follow
[Conventional Commits](https://www.conventionalcommits.org/).

[pub_workspace_link]: https://dart.dev/tools/pub/workspaces
