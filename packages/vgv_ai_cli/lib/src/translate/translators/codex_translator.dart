import 'dart:convert';

import 'package:file/file.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template codex_translator}
/// Configures Codex.
///
/// Codex reads `~/.agents/skills` natively. Its agents are TOML.
/// {@endtemplate}
class const CodexTranslator() extends HarnessTranslator {
  /// {@macro codex_translator}
  this;

  @override
  Harness get harness => Harness.codex;

  /// The shared copy of such a skill carries [policy], from
  /// [sharedSkillFiles].
  @override
  bool get honorsModelInvocation => true;

  /// Where Codex reads a skill's metadata, relative to the skill.
  static const metadata = 'agents/openai.yaml';

  /// Codex's way of keeping a skill the user's alone: the model may not start
  /// it, and the user still can by naming it.
  ///
  /// See https://developers.openai.com/codex/skills.
  static const policy = '''
policy:
  allow_implicit_invocation: false
''';

  /// [policy] at [metadata] in the shared copy of each skill that sets
  /// `disable-model-invocation`, unless the skill ships its own file there,
  /// which the shared copy carries as written and which is noted.
  @override
  TranslationResult sharedSkillFiles(
    PluginAssets assets, {
    required Directory root,
  }) {
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];
    for (final skill in assets.skills) {
      if (!skill.disableModelInvocation) continue;
      if (skill.directory.childFile(metadata).existsSync()) {
        notes.add(
          TranslationNote(
            subject: 'the ${skill.name} skill',
            reason:
                'it ships its own $metadata, so Codex gets that one as '
                'written and may start the skill on its own',
          ),
        );
        continue;
      }
      changes.add(
        PlannedChange.text(
          file: root.childDirectory(skill.name).childFile(metadata),
          contents: policy,
          harness: harness,
        ),
      );
    }
    return TranslationResult(changes: changes, notes: notes);
  }

  /// The keys Codex spells differently from `.mcp.json`.
  static const _renamedKeys = {'headers': 'http_headers'};

  /// Codex declares servers as `[mcp_servers.<name>]` tables, and a remote
  /// server's static headers as `http_headers`.
  @override
  String settings(PluginAssets assets) => TomlDocument.fromMap({
    'mcp_servers': {
      for (final server in assets.mcpServers)
        server.name: {
          for (final MapEntry(:key, :value) in server.toJson().entries)
            _renamedKeys[key] ?? key: value,
        },
    },
  }).toString();

  /// Codex requires `name` and `developer_instructions`, and drops with a
  /// warning any agent declaring no `description`, so all three are written.
  /// An agent body is a whole markdown document full of quotes, backticks and
  /// backslashes, which is why TOML serializes it rather than mustache.
  @override
  HarnessFields agent(AgentAsset agent, {required String instructions}) =>
      HarnessFields(
        toml: TomlDocument.fromMap({
          'name': agent.name,
          'description': agent.description,
          'developer_instructions': instructions,
        }).toString(),
      );

  /// The plugins' hooks as `~/.codex/hooks.json` spells them: Claude's shape,
  /// Codex's tool names, and commands pointing at Codex's copy of each
  /// plugin's `hooks` folder under `<hooksRoot>/<plugin>`. The whole folder
  /// comes, since scripts source their neighbours, with [codexPreamble] in
  /// every script a hook runs and [compatScript] beside it; the plugin's
  /// `hooks.json` does not. See https://developers.openai.com/codex/hooks.
  @override
  HookTranslation hooks(PluginAssets assets, {required Directory hooksRoot}) {
    final compat = hooksRoot.childFile(compatScript);
    final copy = scripts.copy(
      assets.hooks,
      hooksRoot: hooksRoot,
      compat: compat,
    );
    return HookTranslation(
      fragment: _fragment(assets, hooksRoot: hooksRoot),
      files: [
        if (assets.hooks.any(HookScripts.runsCommand))
          PlannedChange.text(
            file: compat,
            contents: codexCompatScript,
            harness: harness,
          ),
        ...copy.files,
      ],
      notes: [
        ...copy.notes,
        if (assets.hooks.isNotEmpty)
          const TranslationNote(
            subject: 'the hooks written to ~/.codex/hooks.json',
            reason:
                'Codex runs no hook it has not been told to trust, so run '
                '/hooks in Codex and trust them',
          ),
      ],
    );
  }

  /// The `hooks.json` fragment, or null when no plugin declares a hook.
  static String? _fragment(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) {
    final events = <String, List<Object?>>{};
    for (final hook in assets.hooks.where(HookScripts.safelyNamed)) {
      events.putIfAbsent(hook.event, () => []).add({
        'matcher': ?_matcher(hook),
        'hooks': [
          for (final command in hook.commands)
            {
              'type': command.type,
              'command': HookScripts.command(
                command,
                hook,
                hooksRoot: hooksRoot,
              ),
              'timeout': ?command.timeout,
            },
        ],
      });
    }
    return events.isEmpty ? null : jsonEncode({'hooks': events});
  }

  /// The file under the hooks root that holds [codexCompatScript].
  static const compatScript = 'vgv-claude-compat.sh';

  @override
  HookScripts get scripts =>
      const HookScripts(harness: Harness.codex, preamble: codexPreamble);

  /// The tools Claude Code names in a matcher that Codex names differently:
  /// it writes every edit through `apply_patch`, keeping Claude's two names
  /// as aliases, and reads files through the shell.
  static const _codexToolNames = {
    'Edit': ['Edit', 'apply_patch'],
    'Write': ['Write', 'apply_patch'],
    'Read': ['Bash'],
    'Glob': ['Bash'],
    'Grep': ['Bash'],
  };

  /// A matcher that is a flat `A|B` list of tool names, the one shape whose
  /// names are mapped; any other regex is handed to Codex as written.
  static final _flatList = RegExp(r'^\w+(\|\w+)*$');

  /// [hook]'s matcher as Codex spells it, null when it declares none.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? when _flatList.hasMatch(declared) => {
      for (final name in declared.split('|'))
        ...(_codexToolNames[name] ?? [name]),
    }.join('|'),
    final declared => declared,
  };
}
