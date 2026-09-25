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

| Harness  | Settings        | `AGENTS.md` | Agents          | Commands           |
| -------- | --------------- | ----------- | --------------- | ------------------ |
| claude   | `settings.json` |             |                 |                    |
| gemini   | `settings.json` | yes         | `agents/*.md`   | `commands/*.toml`  |
| codex    | `config.toml`   | yes         | `agents/*.toml` | `prompts/*.md`     |
| opencode | `opencode.json` | yes         | `agent/*.md`    | `command/*.md`     |
| pi       |                 | yes         |                 | `prompts/*.md`     |

Claude Code installs the plugins natively from the marketplace, so its folder
holds only the settings that point at it.

The CLI maps each folder onto the harness's config directory. A file at the
root of a folder is merged into what is already there. A file in a
subdirectory belongs to VGV and is written whole.

## Partials

Markdown-shaped content is a partial. `{{~ agents.md }}` is the shared
instructions index, and `{{~ agent.md }}` and `{{~ command.md }}` frame an
agent or a command under its frontmatter.

Data-shaped content is rendered by the CLI and placed with a triple mustache.
Mustache cannot escape YAML, TOML or JSON, so every settings file, every
frontmatter block and every TOML agent or command arrives finished.

## Variables

| Var                      | Type    | What it is                                        |
| ------------------------ | ------- | ------------------------------------------------- |
| `claude` ... `pi`        | boolean | Which harnesses to render                          |
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
