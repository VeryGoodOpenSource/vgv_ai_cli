# vgv_ai_cli

![coverage][coverage_badge]
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

`vgv_ai` configures the Very Good AI tooling for the coding agents on your
machine. It installs the skills, agents, MCP servers, and hooks from the VGV
Claude Code plugins into every agent it supports, checks that they stay
current, and removes them again without touching your own configuration.

## Installation

`vgv_ai` is a Dart package. You need the
[Dart SDK](https://dart.dev/get-dart) 3.13 or later.

```sh
dart pub global activate vgv_ai_cli
```

This puts the `vgv_ai` executable on your path. Run `vgv_ai --help` to confirm
that it's installed.

## Supported harnesses

`vgv_ai` calls each coding agent a harness. The flag name is what you pass to
`--only` and `--[no-]<harness>`, and the config directory is where `vgv_ai`
writes that harness's files, relative to your home directory.

| Flag          | Harness            | Executable | Config directory     |
| ------------- | ------------------ | ---------- | -------------------- |
| `claude`      | Claude Code        | `claude`   | `~/.claude`          |
| `gemini`      | Gemini CLI         | `gemini`   | `~/.gemini`          |
| `codex`       | Codex              | `codex`    | `~/.codex`           |
| `opencode`    | OpenCode           | `opencode` | `~/.config/opencode` |
| `pi`          | Pi                 | `pi`       | `~/.pi/agent`        |
| `copilot`     | GitHub Copilot CLI | `copilot`  | `~/.copilot`         |
| `antigravity` | Antigravity CLI    | `agy`      | `~/.gemini/config`   |

Claude Code installs the VGV plugins natively, so `vgv_ai` only points it at
the VGV marketplace. Gemini CLI, Codex, OpenCode, Pi, and GitHub Copilot CLI
share one copy of the skills in `~/.agents/skills`. Antigravity CLI keeps its
own copy inside its plugin.

## Commands

`vgv_ai` has four commands.

### install

`install` writes the Very Good AI tooling into the config of each harness you
select. By default, it configures every supported harness that it finds
installed on your machine.

```sh
# Configure every detected harness
vgv_ai install

# Preview what would be written, without writing anything
vgv_ai install --check

# Configure only some harnesses, whether or not they're detected, or skip one
vgv_ai install --only codex --only gemini
vgv_ai install --no-claude

# Also overwrite your values that conflict with the ones install writes
vgv_ai install --force

# Install just the VGV plugins you name, instead of every pinned one
vgv_ai install --plugin vgv-wingspan
```

`install` reads the pinned plugins from the Claude Code plugin cache when it
holds the pinned version, and otherwise clones them into `~/.vgv_ai/plugins`.
It records every file and key it writes in `~/.vgv_ai/manifest.json`, which is
how `doctor` and `uninstall` tell what's yours from what's VGV's.

- **Your settings:** settings files such as `~/.gemini/settings.json` are
  merged, not replaced. Without `--force`, a value you set is kept, and
  `install` warns you about it. TOML files keep their comments and layout,
  unless `--force` needs to rewrite one.
- **Instructions:** files such as `~/.codex/AGENTS.md` get a section between
  VGV's markers, and the rest of the file stays yours.
- **VGV's files:** agents, commands, skills, and hook scripts belong to VGV and
  are written whole. A file you edited since `install` wrote it, or one at the
  same path that `install` didn't write, is kept unless you pass `--force`.
- **Selection:** `--only` and `--no-<harness>` can't be combined.
- **Plugins:** without `--plugin`, every pinned plugin is installed. Pass it
  once per plugin to name the ones you want. What a previous `install` wrote
  for the plugins you leave out stays where it is; `uninstall` removes that.

### doctor

`doctor` checks that the Very Good AI tooling `install` wrote is still there,
unchanged, and current with this version of `vgv_ai`. It never changes your
harness config or the manifest.

```sh
# Check every harness
vgv_ai doctor

# Check only some harnesses, or skip one
vgv_ai doctor --only codex --only gemini
vgv_ai doctor --no-claude
```

For each harness, `doctor` reports the files and keys that are missing, were
changed since, or differ from what this version installs. It also compares the
plugin versions you installed from with the ones this version pins, notes a
pinned plugin you haven't installed, suggests configuring a harness that's
installed but not configured, and warns about a configured harness that's no
longer installed.

Every problem comes with the `install` command that fixes it, and the report
ends with one command that fixes everything `install` can, such as
`vgv_ai install --only gemini --only codex`. That command includes `--force`
only when changed files need restoring, and then `--force` applies to every
harness it names.

To check whether files are current, `doctor` resolves the plugins the same way
`install` does, so it may clone them into `~/.vgv_ai/plugins`.

### uninstall

`uninstall` removes only what `~/.vgv_ai/manifest.json` records that `install`
wrote, so your own files, keys, comments, and sections stay.

```sh
# Remove the tooling from every harness
vgv_ai uninstall

# Preview what would be removed, without removing anything
vgv_ai uninstall --check

# Remove the tooling from only some harnesses, or keep one
vgv_ai uninstall --only codex --only gemini
vgv_ai uninstall --no-claude

# Also remove what you changed since install
vgv_ai uninstall --force
```

- **Selection:** the harnesses come from the manifest, not from what's
  installed, so you can clean up an agent you've already removed.
  `--only` and `--no-<harness>` can't be combined.
- **Shared skills:** the skills in `~/.agents/skills` are shared by every
  agent, so they're removed only when every harness the manifest records is.
  A partial run keeps them and tells you how to remove them.
- **Your changes:** without `--force`, a file, key, or section you changed
  since `install` is kept, and a warning names it.
- **Directories:** empty directories left behind are removed, but
  `~/.agents/skills` and each harness's config directory, such as `~/.codex`,
  stay.
- **Manifest:** it keeps whatever is left to remove, and it's deleted once
  nothing is. `--check` changes nothing, not even the manifest.

### update

`update` updates `vgv_ai` to the latest version on pub.dev. It takes no flags.

```sh
vgv_ai update
```

Every other command also checks pub.dev for a newer version when it finishes,
and prints how to update when there is one.

## Global options

These options work without a command:

```sh
# Show the version
vgv_ai --version

# Show usage help, for vgv_ai or for one command
vgv_ai --help
vgv_ai install --help

# Log every step, including the shell commands vgv_ai runs
vgv_ai install --verbose
```

## Contributing

To work on `vgv_ai`, see the
[contributing guide](../../CONTRIBUTING.md).

[coverage_badge]: coverage_badge.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
