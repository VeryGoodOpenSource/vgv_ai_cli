# Adding a harness

What to change, in order, to teach `vgv_ai` a new coding agent.

A harness is one coding agent the CLI configures: Claude Code, Gemini, Codex, OpenCode, Pi,
Copilot, Antigravity. The VGV plugins are written for Claude Code and stay that way. Every
difference another harness has is answered in one place, its **translator**.

## Research it first

The plugins contribute skills, agents, MCP servers and hooks. Before writing code, find out from
the harness's own docs how it spells each one. Your answers decide what you write.

| Question | Where the answer goes |
| --- | --- |
| What does the binary answer `--version` with? | `executable` on the enum |
| Which directory under `$HOME` holds its user config? | `config` on the enum |
| Does it have a settings file, and what's its schema? | `settings()` on the translator |
| Does it read `~/.agents/skills` with no configuration? | `readsSharedSkills` |
| If not, where does it want its own copy of the skills? | `skillsRoot()` |
| Does it have subagents? What frontmatter do they need? | `agent()`, plus an `agents/` folder in the brick |
| Does it have slash commands or prompts? | `command()`, plus the folder it reads them from — `prompts/`, `command/`, `commands/`, whatever it calls it |
| Can anything in its config run a shell command? | `hooks()` and `scripts` |
| Does it read MCP servers, and under which key? | `settings()` |

Anything the plugins ship that the harness has no home for becomes a `TranslationNote`, so the
user is told rather than left guessing.

Two worked examples: [`pi_translator.dart`][pi] is the smallest a translator gets, and
[`antigravity_translator.dart`][antigravity] is the fullest — its own skills copy, hooks, and a
compat script.

## 1. Add the enum value

`packages/vgv_ai_cli/lib/src/model/harness.dart`

```dart
/// Antigravity CLI, which keeps the config it shares with the Antigravity
/// IDE beside Gemini's.
antigravity(
  displayName: 'Antigravity',
  executable: 'agy',
  config: '.gemini/config',
);
```

- `name` — the enum's own name — is three things at once: the `--only <name>` and
  `--[no-]<name>` flag, the `owner` the manifest records, and **the brick folder the harness
  renders into**.
- `displayName` is what reports and `--help` print.
- `executable` is the binary probed with `<executable> --version`. A non-zero exit reads as not
  installed.
- `config` is relative to `$HOME` with `/` separators, whatever the platform.

Position matters: `Harness.values` is the order every report and the translator registry use.

## 2. Give it a brick folder

`bricks/agents/__brick__/{{#<harness>}}<harness>/…{{\<harness>}}`

**The tree is the capability matrix.** What the folder holds is what the harness supports. A
feature the harness lacks has no file, and that absence is the whole opt-out — Pi has `AGENTS.md`
and `prompts/` and nothing else.

The CLI maps the folder onto the harness's config directory and picks how each file lands from its
path:

| Path in the folder | How it lands |
| --- | --- |
| `<harness>/settings.json` | Deep merged into the JSON file |
| `<harness>/config.toml` | Deep merged into the TOML document |
| `<harness>/<any other root file>` | Merged as the `instructions` section of a markdown file, between VGV's markers. The extension is not checked — anything at the root that isn't `.json` or `.toml` lands here |
| `<harness>/<anything deeper>` | Owned by VGV and written whole |

So a root file is shared with the user and merged; anything deeper VGV owns. See
[`rendered_change.dart`][rendered_change].

### The variables

| Var | What it is |
| --- | --- |
| `<harness>` | Boolean. Renders the whole folder. |
| `<harness>_settings` | The settings fragment `settings()` returned. Absent when it returns null. |
| `<harness>_hooks` | The fragment `hooks()` returned. Absent when there is none, so wrap a hooks file in `{{#<harness>_hooks}}…{{\<harness>_hooks}}` and it is written only when there is something to register. |
| `agents` | One entry per agent: `name`, `instructions`, and a map per harness. |
| `commands` | One entry per invocable skill: `name`, `body`, and a map per harness. |
| `index` | `skills` and `agents` for the instructions file to list, each with a `has_skills` / `has_agents` boolean the shared partials gate on. |

Each agent and command carries a map under the harness's name holding whatever `HarnessFields`
your translator returned — `frontmatter`, `toml`, `instructions`.

### Writing the templates

The settings file. Its whole body is the fragment the translator returned:

```mustache
{{{<harness>_settings}}}
```

One file per agent. The file name is a path loop, and the body pulls the harness's own map off
each agent:

```mustache
{{#agents}}{{#<harness>}}{{> agent.md }}{{/<harness>}}{{/agents}}
```

The instructions file, which is just the two shared partials:

```mustache
{{> instructions.md }}{{> agent_index.md }}
```

Three rules:

1. **Use a triple mustache for anything structured.** Mustache cannot escape JSON, TOML or YAML, so
   those arrive from the translator already finished.
2. **Markdown-shaped content is a partial.** `instructions.md`, `agent_index.md` and `agent.md`
   already exist; reuse them instead of writing a fourth.
3. **A path loop needs its list to be non-empty.** Mason renders an empty list as a file with no
   name, which is why `agents` and `commands` are left out when empty and the `AGENTS.md` lists
   live inside `index`.

Then add a row to the capability matrix in [`bricks/agents/README.md`](bricks/agents/README.md).

## 3. Declare the brick var

`bricks/agents/brick.yaml`

```yaml
antigravity:
  type: boolean
  default: true
  description: Configure Antigravity CLI.
  prompt: Configure Antigravity CLI?
```

Only the harness booleans are declared. Everything else is passed at render time.

## 4. Regenerate the bundle

```sh
# From the repo root
tool/generate_agents_bundle.sh
```

The bundle is committed, and CI's `verify-bundle` job fails if it drifts. Needs
`dart pub global activate mason_cli 0.1.4`.

## 5. Write the translator

`packages/vgv_ai_cli/lib/src/translate/translators/<harness>_translator.dart`

Subclass [`HarnessTranslator`][harness_translator]. Everything but `harness` has a default, so you
override only what the harness actually differs on.

```dart
/// {@template pi_translator}
/// Configures Pi.
///
/// Pi is minimal by design, with no subagents, no MCP and no declarative
/// hooks. It reads the shared skills and `AGENTS.md` without configuration,
/// so it gets its instructions and its prompts, which are the skill bodies as
/// written, and nothing that would imitate the rest.
/// {@endtemplate}
class const PiTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.pi;

  @override
  List<TranslationNote> notes(PluginAssets assets) => [
    if (assets.agents.isNotEmpty)
      TranslationNote(
        subject: '${assets.agents.length} agent(s)',
        reason: 'Pi has no subagents, so it gets none',
      ),
    if (assets.mcpServers.isNotEmpty)
      TranslationNote(
        subject: '${assets.mcpServers.length} MCP server(s)',
        reason: 'Pi has no MCP support, so it gets none',
      ),
  ];
}
```

| Member | Default | Override when |
| --- | --- | --- |
| `harness` | — | Always. |
| `readsSharedSkills` | `true` | It does not read `~/.agents/skills`. |
| `skillsRoot(home)` | `null` | It needs its own copy of the skills somewhere. |
| `settings(assets)` | `null` | It has a settings file. Return finished JSON or TOML. |
| `agent(agent, instructions:)` | empty | Its agent files need frontmatter or a TOML body. |
| `command(skill)` | empty | Its command files need frontmatter or a TOML body. |
| `hooksRoot(home)` | `<config>/hooks` | It reads hook files from somewhere else. |
| `scripts` | `null` | It runs the plugins' hook scripts. |
| `hooks(assets, hooksRoot:)` | `null` | Its config can run a shell command. |
| `notes(assets)` | `[]` | Something the plugins ship has no home here. |

Three things to get right:

- **Return finished text.** The brick only decides where a value goes, never how it is escaped.
- **No translator depends on another.** One file per harness, and shared behavior belongs on the
  base class or in `translate/`.
- **Don't write the "no hooks" note yourself.** When `hooks()` returns null and the plugins ship
  hooks, [`Translator._result`][translator] adds it, so every harness says it the same way.

If the harness needs something no existing override expresses — Antigravity needed its own skills
copy and an `instructions` field on `HarnessFields` — add it to `HarnessTranslator` or
`HarnessFields` with a default that leaves every other harness unchanged.

## 6. Register it

```dart
// translators/translators.dart — alphabetical
export '<harness>_compat.dart';     // only with hooks
export '<harness>_translator.dart';

// translators/harness_translators.dart — in Harness.values order
const harnessTranslators = <HarnessTranslator>[
  // …
  AntigravityTranslator(),
];
```

`translator_test.dart` asserts `harnessTranslators.map((t) => t.harness)` equals `Harness.values`,
so a missed registration or a wrong position fails there.

## 7. Hooks, if it has them

Skip this whole step when nothing in the harness's config runs a shell command. OpenCode is the
example: its hooks are TypeScript callbacks, so `hooks()` stays null and the user gets a note.

The plugins ship hooks as Claude Code shell commands. Three pieces make them run elsewhere, and
`hooks()` wires all three together — nothing in the framework calls `scripts` for you.

**`scripts`** is the copier. It copies each plugin's whole `hooks/` folder under
`hooksRoot/<plugin>/` — the whole folder, because scripts source their neighbors — and splices a
preamble below the shebang of every UTF-8 bash script a hook runs. Anything else is copied as it
is, with a note. The plugin's own `hooks/hooks.json` is never copied; your translator spells the
registry instead.

```dart
@override
HookScripts get scripts =>
    const HookScripts(harness: Harness.copilot, preamble: copilotPreamble);
```

In the preamble, `__ROOT__`, `__AGENT__` and `__COMPAT__` are replaced with quoted shell words: the
plugin root, the agent the hook is scoped to — or an empty string when hooks of more than one agent
scope run the script — and the compat script's path.

**The compat script** goes in `<harness>_compat.dart` beside the translator. It reads what the
harness sends on stdin, hands the script the payload Claude Code would have sent, and respells the
answer the way the harness reads it. [`copilot_compat.dart`][copilot_compat] is the one to copy
from.

**`hooks()`** does the assembling. It calls `scripts.copy(...)`, plans the compat script as a file
of its own, and returns all of it as one `HookTranslation`:

```dart
@override
HookTranslation hooks(PluginAssets assets, {required Directory hooksRoot}) {
  final runnable = _runnable(assets);
  final compat = hooksRoot.childFile(compatScript);
  final copy = scripts.copy(runnable, hooksRoot: hooksRoot, compat: compat);
  return HookTranslation(
    fragment: _fragment(runnable, hooksRoot: hooksRoot),
    files: [
      if (runnable.any(HookScripts.runsCommand))
        PlannedChange.text(
          file: compat,
          contents: copilotCompatScript,
          harness: harness,
        ),
      ...copy.files,
    ],
    notes: [
      ...copy.notes,
      ..._scopedNotes(assets),
      ...scripts.handlerNotes(runnable),
    ],
  );
}
```

`fragment` is what gets merged into the harness's hooks file — and what reaches the brick as
`<harness>_hooks`. Helpers on `HookScripts` for writing it:

| Helper | What it does |
| --- | --- |
| `HookScripts.command(command, hook, hooksRoot:)` | Points the hooks folder at the copy and the rest of the plugin at itself, both quoted |
| `HookScripts.runsCommand(hook)` | Whether the hook runs a shell command at all |
| `HookScripts.safelyNamed(hook)` | Whether the plugin's name is safe as a folder name |
| `HookScripts.quoted(value)` | One double-quoted shell word |
| `scripts.handlerNotes(hooks)` | A note per handler type that runs no shell command. Shared — do not write your own |

Leave out what the harness can't express and say so in a note — a hook an agent declared for
itself, an event the harness lacks, a handler type that isn't a shell command.

## 8. Tests

100% coverage, `mocktail` for mocks, `MemoryFileSystem.test()` for disk.

**New files:**

```text
test/src/translate/translators/<harness>_translator_test.dart
test/src/translate/translators/<harness>_compat_test.dart   # only with a compat script
```

Build fixtures with the shared helpers in [`test/src/translate/_assets.dart`][assets] —
`skillAsset`, `agentAsset`, `hookAsset`, `pluginAssets`, `frontmatterValues` — so each test asserts
on translation rather than on fixture construction.

**Existing files to update:**

| File | What to add |
| --- | --- |
| `test/src/model/harness_test.dart` | The name in the reporting-order list, and the config directory in the path map |
| `test/src/translate/agents_vars_test.dart` | The harness in the flags map |
| `test/src/translate/translator_test.dart` | A `tree()` expectation for every file the harness gets |

`test/pinned_plugins_test.dart` loops `Harness.values`, so it picks up the new harness on its own.
Run it against the real plugins before opening the PR:

```sh
dart run test --run-skipped -t pinned-plugins
```

## What you don't have to touch

These are all driven by `Harness.values` or by the manifest, and need no per-harness code:

- **Detection.** `HarnessDetector` probes `<executable> --version` for every value.
- **Selection flags.** `HarnessSelection` adds `--only` and `--[no-]<harness>` for every value, so
  `install`, `uninstall` and `doctor` pick the harness up at once.
- **`doctor`.** It reports per harness off the manifest, and derives which harnesses read the
  shared skills from `harnessTranslators`.
- **`uninstall`.** It reverses what the manifest records, and takes its harnesses from there rather
  than from detection.
- **The manifest.** `ManifestEntry.owner` is a `Harness?`, written and read back by name.
- **Reconciliation.** The change mode comes from the file's path in the brick, not from the
  harness.

## Checklist

```text
bricks/agents/brick.yaml                                  boolean var
bricks/agents/__brick__/{{#<h>}}<h>/…{{\<h>}}             the templates
bricks/agents/README.md                                   capability matrix row
packages/vgv_ai_cli/lib/src/templates/agents_bundle.dart  regenerated, not hand-edited
packages/vgv_ai_cli/lib/src/model/harness.dart            enum value
…/lib/src/translate/translators/<h>_translator.dart       the translator
…/lib/src/translate/translators/<h>_compat.dart           only with hooks
…/lib/src/translate/translators/translators.dart          export
…/lib/src/translate/translators/harness_translators.dart  registry entry
…/test/src/translate/translators/<h>_translator_test.dart new
…/test/src/translate/translators/<h>_compat_test.dart     only with hooks
…/test/src/model/harness_test.dart                        order list, config path
…/test/src/translate/agents_vars_test.dart                flags map
…/test/src/translate/translator_test.dart                 rendered tree
```

Then: `tool/generate_agents_bundle.sh`, the full coverage run, and
`dart run test --run-skipped -t pinned-plugins`.

[antigravity]: packages/vgv_ai_cli/lib/src/translate/translators/antigravity_translator.dart
[assets]: packages/vgv_ai_cli/test/src/translate/_assets.dart
[copilot_compat]: packages/vgv_ai_cli/lib/src/translate/translators/copilot_compat.dart
[harness_translator]: packages/vgv_ai_cli/lib/src/translate/harness_translator.dart
[pi]: packages/vgv_ai_cli/lib/src/translate/translators/pi_translator.dart
[rendered_change]: packages/vgv_ai_cli/lib/src/translate/rendered_change.dart
[translator]: packages/vgv_ai_cli/lib/src/translate/translator.dart
