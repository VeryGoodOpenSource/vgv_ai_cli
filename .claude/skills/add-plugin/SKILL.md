---
name: add-plugin
description: Adds a new VGV Claude Code plugin to vgv_ai_cli so `vgv_ai install` ports it to every harness — pinning it in vgvPlugins, auditing its contents against what the parser and translators support, extending the parser when the plugin needs it, updating every test that lists the pinned plugins, and verifying against the real plugin. Use when asked to "add <plugin> to vgv_ai", "pin <plugin>", "install <plugin> for every agent", "support the <name> plugin", or when a new plugin lands in the VGV marketplace. Not for bumping a plugin that is already pinned (the weekly bot does that) or for adding a coding agent (use add-harness).
---

# Adding a plugin

A plugin is pinned in one place, `vgvPlugins` in
`packages/vgv_ai_plugins/lib/src/plugin_ref.dart`, and everything else iterates that list. So the
pin itself is a few lines of code. The real work is the audit: a plugin can contain things the
parser has never seen, and the CLI fails on them quietly. A skill whose `${CLAUDE_PLUGIN_ROOT}`
never resolves, a skill name another plugin already took, or a `commands/` folder nobody reads all
install cleanly and then do nothing. Steps 1 and 2 are there to catch that before code is written.

Run commands from the repo root unless a step says otherwise. Paths are written in full from the
root.

## Step 1: research, then report before writing code

Find the release to pin and confirm Claude Code can get it:

```sh
gh release view -R VeryGoodOpenSource/<plugin> --json tagName,publishedAt
gh api repos/VeryGoodOpenSource/<plugin>/contents/.claude-plugin/plugin.json?ref=<tag> \
  --jq .content | base64 -d
gh api repos/VeryGoodOpenSource/very-good-claude-code-marketplace/contents/.claude-plugin/marketplace.json \
  --jq .content | base64 -d
```

Record:

- **`name`**: what `plugin.json` declares. It becomes the `--plugin` value, the manifest key and
  the Claude Code cache folder, so it must match the marketplace entry exactly.
- **`version`**: what `plugin.json` declares at the tag. This is **not** the tag. `PluginRef`
  explains why both are kept: the cache folder is named after the version, while git clones the
  tag.
- **`gitRef`**: the release tag, usually `v`-prefixed.
- **Whether the marketplace lists the plugin at that version.** The Claude harness enables
  `<name>@very-good-claude-code-marketplace` for every pin. If the marketplace doesn't list the
  plugin, Claude Code reports a plugin it can't find. Stop and get it listed first.

Then clone the tag and audit it against the plugins already pinned:

```sh
work=$(mktemp -d)
git clone -q --depth 1 --branch <tag> https://github.com/VeryGoodOpenSource/<plugin>.git "$work/new"
# Each existing pin, at its pinned gitRef from plugin_ref.dart:
git clone -q --depth 1 --branch <gitRef> https://github.com/<repo>.git "$work/<name>"
.claude/skills/add-plugin/scripts/audit_plugin.sh "$work/new" "$work"/<each pinned name>
```

The script only reports; it changes nothing. Here is what each section means:

| Section                                                        | Fine when                                                                                                                                 | Otherwise                                                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Top-level entries the parser does not read                     | Only folders that bodies read in place through `${CLAUDE_PLUGIN_ROOT}`, such as `references/`, `scripts/` or `config/`, plus repo tooling | A Claude feature the parser does not port, such as `commands/` or `output-styles/`. Report it: it is either new parser work or a known gap the PR states                                                                                                                                          |
| Contributes                                                    | —                                                                                                                                         | Hook events and handler types tell you which harnesses will print notes. Translators already report those, so this is for your report, not a blocker                                                                                                                                              |
| `${CLAUDE_PLUGIN_ROOT}` in files that are copied               | `none`                                                                                                                                    | A skill's other files are copied byte for byte, so the placeholder there never resolves outside Claude Code. That needs parser or translator work                                                                                                                                                 |
| Bare paths to plugin files                                     | `none`                                                                                                                                    | Upstream bug: the path resolves against the user's project, not the plugin. File an issue on the plugin repo (step 6). Do not work around it in the CLI                                                                                                                                           |
| Paths through `${CLAUDE_PLUGIN_ROOT}` the plugin does not hold | `none`                                                                                                                                    | Upstream bug, same as above                                                                                                                                                                                                                                                                       |
| Names already taken by a pinned plugin                         | `none`                                                                                                                                    | `PluginAssets.merge` keeps the **first** skill, agent or MCP server of a name and drops the rest without a word. Compare the two definitions: identical, as with the `very-good-cli` MCP server that two VGV plugins both declare, is harmless. If they differ, stop and ask which one should win |

**Stop and report**, with the audit output, before writing code. Say what will be ported, what will
be noted as unsupported, and what needs CLI changes. A guess here produces config that silently does
nothing.

## Step 2: CLI changes the plugin needs, if any

Most plugins need none. When the audit shows one, such as a placeholder the parser does not yet
resolve, make that change on its own, in its own commit (`feat(plugins): …`), before the pin. That
way the pin commit reads as data. The ffca plugin is the precedent: it needed `${CLAUDE_PLUGIN_ROOT}`
resolved in skill and agent bodies, which went into `ClaudePluginParser` in `vgv_ai_plugins`.

- Put Claude-specific interpretation in `ClaudePluginParser`. It is the one place that knows what
  "Claude-specific" means. A harness-specific rendering goes in that harness's translator.
- Test it against fixtures in `packages/vgv_ai_plugins/test/src/parser/`, not against the real
  plugin.
- **If the change alters what an existing install renders**, every user's files read as
  `outdated` in `doctor` until they run `install` again. Say so in the PR. Also add a `doctor` test
  in `packages/vgv_ai_cli/test/src/commands/doctor/doctor_command_test.dart` for the case that
  flips. `a skill pointing into the plugin root` in that file is the model.
- Update the docs of the model types you touched (`HookCommand`, `SkillAsset`, `AgentAsset`, …) so
  they still describe the contract.
- Both packages' CI runs a cognitive complexity check (max 15 per function) on `lib`. Split a
  function before it crosses that.
- **Prove the change leaves the existing pins alone.** Fixture tests can't show what real plugins
  render. Install the existing pins into one home before the change and into another after it,
  then diff the two with the home path normalized. Only files the change is meant to affect may
  differ. Run this with the change committed, before the pin:

  ```sh
  cd packages/vgv_ai_cli
  only=$(dart run bin/vgv_ai.dart install --help | sed -n 's/.*\[\([a-z]*\)\] .*/--only \1/p' | xargs)
  pins=$(dart run bin/vgv_ai.dart install --help | sed -n 's/.*\[\(.*-.*\)\]$/\1/p' | tr -d ',' | sed 's/[^ ][^ ]*/--plugin &/g')
  install_into() {
    local home; home=$(mktemp -d)
    HOME=$home dart run bin/vgv_ai.dart install $only $pins > /dev/null
    rg -l --hidden --no-ignore -F "$home" "$home" | xargs perl -pi -e "s|\Q$home\E|HOME|g"
    echo "$home"
  }
  git switch -q --detach <commit before the change>; before=$(install_into); git switch -q -
  after=$(install_into)
  diff -r -x .vgv_ai -x .dart-tool "$before" "$after"   # clones and Dart telemetry differ anyway
  ```

## Step 3: the pin

Append a block to `vgvPlugins`:

```dart
PluginRef(
  name: '<name>',
  repo: 'VeryGoodOpenSource/<plugin>',
  version: '<plugin.json version>',
  gitRef: '<tag>',
),
```

- **Keep exactly this shape.** `packages/vgv_ai_plugins/tool/bump_plugin_pins.dart` finds the block
  with `PluginRef\([^)]*\)` and the `repo: '…',` line, then rewrites `version` and `gitRef` in place.
  A reformatted block makes the weekly bump fail.
- **Append; do not insert.** List order decides which plugin wins a name collision (step 1). It is
  also the order of `--plugin` in `install --help`.

## Step 4: the tests that list the plugins

Most tests iterate `vgvPlugins` and adapt on their own. Find the ones that do not:

```sh
rg -n "vgv-wingspan|vgv-ai-flutter-plugin|vgvPlugins\.(first|last)" packages/*/test
```

These are the known ones. Update each, then check the `rg` output for any the list has missed:

- `packages/vgv_ai_plugins/test/tool/bump_plugin_pins_test.dart`: the `pinsSource` copy of the pin
  list, and **every** `releases({...})` map, which needs an entry for the new plugin. Add a test that
  bumps only the new plugin, modeled on `bumps the FFCA plugin like any other`.
- `packages/vgv_ai_cli/test/src/translate/translators/claude_translator_test.dart`: the
  `enabledPlugins` map.
- `packages/vgv_ai_cli/test/src/commands/install_command_test.dart`: any expectation that names
  only the first plugin where every pinned plugin is meant. The `--plugin` test that skips
  `vgvPlugins.last` is one. With a third pin, "every plugin but the skipped one" is no longer just
  `first`.

Leave alone the tests that use a plugin name only as sample data, such as `install_manifest_test.dart`
or the `vgv-wingspan` fixture in `test/src/translate/_assets.dart`.

## Step 5: verify

From each package:

```sh
cd packages/vgv_ai_plugins
dart format --set-exit-if-changed . && dart analyze --fatal-infos --fatal-warnings lib test
dart run test
cd ../vgv_ai_cli
dart format --set-exit-if-changed . && dart analyze --fatal-infos --fatal-warnings lib test
dart run test --run-skipped -t pinned-plugins
```

`pinned-plugins` is the check that matters for a new pin. It clones every real pinned plugin at its
`gitRef`, so this is the first time the parser's strict schemas meet the new plugin's actual files.
It then translates them for every harness and checks that every plugin path a rendered body names
exists. It is skipped by default, which is why the command passes `--run-skipped`.

If the clone fails with exit 128 and no message, a global git hook, such as a `post-checkout` from
`init.templateDir`, is failing inside the fresh clone. Run with hooks off for that command only:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
  dart run test --run-skipped -t pinned-plugins
```

Then run the full suite with coverage, which must stay at 100%. If the `very_good_cli` MCP server
is available, use its `test` tool: a hook denies `dart test` and `very_good test` in Bash there.
Otherwise run `very_good test -j 4 --coverage --min-coverage 100 --optimization` in each package.

Finally, run the plugin through the CLI for real, for every harness, in a throwaway home. **Put a
space in the home path**, because that is where shell quoting breaks: the FFCA hooks already quote
`${CLAUDE_PLUGIN_ROOT}`, and the CLI quoted the path a second time inside them. Neither the tests
nor `--check` caught it.

```sh
cd packages/vgv_ai_cli
only=$(dart run bin/vgv_ai.dart install --help | sed -n 's/.*\[\([a-z]*\)\] .*/--only \1/p' | xargs)
home="$(mktemp -d)/Jane Doe"; mkdir -p "$home"
HOME="$home" dart run bin/vgv_ai.dart install $only --plugin <name>
HOME="$home" dart run bin/vgv_ai.dart doctor
```

Then check each of these:

- **Every asset is accounted for.** Each skill, agent, MCP server and hook script the audit counted
  was written, or got a note from `install` saying why a harness can't take it. Anything in neither
  place is silently missing. That is a bug, not something to report as unsupported.
- **`doctor` exits 0.**
- **The rendered paths work.** No rendered file outside a copied hook folder still contains
  `CLAUDE_PLUGIN_ROOT`, and every plugin path a body names exists.
- **The hooks run.** Read the commands out of a harness's hook config, such as
  `jq -r '.. | .command? // empty' "$home/.codex/hooks.json"`. Check that each one is a single
  correctly quoted word despite the space. Then run one with a payload that should trigger it, in a
  scratch project, and confirm it behaves as it does in Claude Code.

## Step 6: upstream issues

Problems in the plugin's own content go to the plugin repository as issues, not into CLI
workarounds. Examples are bare paths, references to files the plugin doesn't ship, and a
placeholder in a file the CLI copies. Search first, then file one issue covering them all:

```sh
gh issue list -R VeryGoodOpenSource/<plugin> --state all --search "CLAUDE_PLUGIN_ROOT"
gh issue create -R VeryGoodOpenSource/<plugin> --title "fix: …" --body-file <file>
```

Give each finding its file and line, why it breaks outside Claude Code, and the fix. Link the issue
from the PR. When the plugin releases the fix, the weekly bump bot picks it up.

## Step 7: the PR

- Branch `feat/add-<plugin>`. Never commit to `main`.
- One logical change per commit. The precedent is #125: `feat(plugins): …` for parser work and its
  tests, `test(doctor): …` when the rendered output changes, `feat: pin <name> v<version>` with the
  test updates, then `docs: …`.
- Do not touch any `CHANGELOG.md` or version. Release automation owns them.
- Document user-visible behavior the plugin introduces in the **Notes** list of
  `packages/vgv_ai_cli/README.md`. Do not edit the plugin lists in `AGENTS.md` and `CONTRIBUTING.md`:
  they describe this repo's own `.claude/settings.json`, not what `install` ships.
- **Spelling is checked in every markdown file and in the PR title**, against the VGV dictionaries
  plus the `words` in `.github/cspell.json`. A plugin's acronym fails both, as "ffca" did. Add the
  acronym to `words` in its own commit (`chore: …`). That also runs `vgv_ai_cli.yaml`, whose
  filters include `.github/cspell.json`. Editing the title does not re-run CI, so after fixing a
  title, close and reopen the PR.
- Fill in `.github/PULL_REQUEST_TEMPLATE.md`. Under a "Known limitations" heading, list what the
  audit found that the PR does not fix, with links to the upstream issues.

Then report: the pinned `version` and `gitRef`, the audit output and what you did about each
finding, the commands from step 5 and their results, and any upstream issues filed. If you could not
run a check, say so plainly rather than implying it passed.

## Common failures

| Symptom                                                                      | Cause                                                                                                                                       |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `pinned-plugins` fails in `setUpAll` with `Could not parse <plugin>`         | The plugin ships a shape `claude_schemas.dart` does not admit. Step 2 work, or an upstream fix                                              |
| `pinned-plugins` fails in `setUpAll` with `Could not clone …` and no message | A global git hook. See the workaround in step 5                                                                                             |
| `bump_plugin_pins_test.dart` fails after the pin                             | `pinsSource` or a `releases({...})` map is missing the new plugin                                                                           |
| The weekly bump PR fails on the new plugin                                   | The `PluginRef(...)` block was reformatted, so `rewritePin` cannot find it                                                                  |
| A skill or agent from the new plugin never installs                          | Its name collides with one an earlier pin declares. `merge` dropped it                                                                      |
| `spell-check / build` fails on **Spell Check PR Title**                      | An acronym missing from `words` in `.github/cspell.json`. Add it, then close and reopen the PR                                              |
| `doctor` reports every file of the plugin as outdated after `install`        | Expected once Claude Code caches the plugin: bodies point at whichever copy the resolver found. See the plugin-files note in the CLI README |
