# Devin CLI

- **Flag:** `devin`
- **Executable:** `devin`
- **Config directory:** `~/.config/devin`

| What         | Where, under `~/.config/devin/` |
| ------------ | ------------------------------- |
| Skills       | `~/.agents/skills`, shared      |
| Instructions | `AGENTS.md`, merged             |
| Settings     | `mcp_config.json`, merged       |
| Agents       | `agents/*.md`                   |
| Hooks        | `config.json`, merged, `hooks/` |

Devin CLI reads `~/.agents/skills` on its own and makes each skill a
`/<name>` command, so it shares the one copy and gets no commands folder. The
agents are its subagent profiles, and `AGENTS.md` is a global rule.

`install` merges into `mcp_config.json` and `config.json` rather than
replacing them, so your own MCP servers, hooks and settings survive.

Devin CLI is macOS and Linux only here. On Windows its config lives in
`%APPDATA%\devin`, which `vgv_ai` cannot spell yet.

## Hooks

The hook scripts are copied to `~/.config/devin/hooks/`, with
`vgv-claude-compat.sh` beside them, and registered under the `hooks` key of
`config.json`. The scripts are `#!/bin/bash` and call `jq`, so `jq` has to be
on your path.

Devin CLI sends Claude Code's payload field for field, so the compat script
only renames the tool — `exec` to `Bash`, `edit` and `apply_patch` to `Edit`,
and so on — and spells the answer the way Devin reads it.

Three things are left out, and `install` says so each time:

- Hooks an agent declares for itself. A Devin hook payload names no subagent,
  so there is nothing to scope them by.
- Hooks on events Devin CLI does not have, such as `SubagentStart`.
- Handlers that run no shell command. Devin CLI drops every hook in a file
  that declares a handler type it does not know, so one of these would
  disable the rest.

Before a tool runs, Devin CLI reads a decision but not injected context, so a
hook that only adds context runs and the agent hears none of it.

A GPT model with the Codex tools setting edits through `apply_patch`, whose
payload carries the patch text rather than a file path, so the analyze and
format hooks skip those edits.

## Trying it out

Devin CLI refuses to run in a workspace it does not trust. A headless run
needs `--respect-workspace-trust false`; an interactive session trusts the
directory once and remembers.

`devin auth login` stores its credentials under `~/.local/share/devin/`, so a
sandbox `HOME` needs a login of its own.
