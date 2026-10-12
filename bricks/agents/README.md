# agents

The files each coding agent harness reads to use the VGV plugins.

`vgv_ai install` renders this brick into memory, never into your home
directory, and hands each file to its reconciler. Settings files are deep
merged, so keys you own are preserved.

## The tree is the capability matrix

Each top-level folder is one harness and is rendered only when its flag is set.
What a folder contains is what that harness supports. Pi's folder has
`AGENTS.md` and `prompts/` and nothing else, and that absence is how Pi opts
out of agents and settings.

| Harness  | Settings          | Instructions              | Agents              | Commands          | Hooks            |
| -------- | ----------------- | ------------------------- | ------------------- | ----------------- | ---------------- |
| claude   | `settings.json`   |                           |                     |                   |                  |
| gemini   | `settings.json`   | `AGENTS.md`               | `agents/*.md`       | `commands/*.toml` |                  |
| codex    | `config.toml`     | `AGENTS.md`               | `agents/*.toml`     |                   | `hooks.json`     |
| opencode | `opencode.json`   | `AGENTS.md`               | `agent/*.md`        | `command/*.md`    |                  |
| pi       |                   | `AGENTS.md`               |                     | `prompts/*.md`    |                  |
| copilot  | `mcp-config.json` | `copilot-instructions.md` | `agents/*.agent.md` |                   | `hooks/vgv.json` |

Claude Code installs the plugins natively from the marketplace, so its folder
holds only the settings that point at it.

Codex's `hooks.json` is rendered only when there are hooks Codex can run. Its
commands point at the CLI's own copy of each plugin's `hooks/` folder under
`~/.codex/hooks/<plugin>/`, which the CLI writes beside the brick's output
with a preamble at the top of every script a hook runs, so a script written
for Claude Code gets the payload Claude Code would have sent. Copilot's
`hooks/vgv.json` is the same, written as its own file because Copilot reads
every `*.json` under `~/.copilot/hooks/`, subfolders included, which is also
why its scripts are copied to `~/.copilot/vgv_ai/hooks/<plugin>/` instead.

The CLI maps each folder onto the harness's config directory. A file at the
root of a folder is merged into what is already there. A file in a
subdirectory belongs to VGV and is written whole.

## Partials

Markdown-shaped content is a partial. `{{~ instructions.md }}` opens every
instructions file and indexes the skills, and `{{~ agent_index.md }}` indexes the
agents for the harnesses that have them. Pi has no subagents, so its
`AGENTS.md` leaves the agent index out. `{{~ agent.md }}` frames an agent
under its frontmatter.

Data-shaped content is rendered by the CLI and placed with a triple mustache.
Mustache cannot escape YAML, TOML or JSON, so every settings file, every
frontmatter block and every TOML agent or command arrives finished.

## Variables

| Var                      | Type    | What it is                                        |
| ------------------------ | ------- | ------------------------------------------------- |
| `claude` ... `copilot`   | boolean | Which harnesses to render                          |
| `<harness>_settings`     | string  | That harness's settings fragment, absent for Pi   |
| `agents`                 | list    | Each agent's `name`, `instructions`, and a map per harness |
| `commands`               | list    | Each invocable skill's `name`, `body`, and a map per harness |
| `index`                  | map     | `skills` and `agents` to list in `AGENTS.md`        |

`agents` and `commands` are the only top-level lists, and the CLI leaves either
out when it is empty. Mason renders a path loop once for every combination of
every top-level list, and renders an empty list as a file with no name. The
`AGENTS.md` lists live inside `index` for the same reason.

## Regenerating the bundle

The bundle is committed and CI fails if it drifts:

```sh
tool/generate_agents_bundle.sh
```
