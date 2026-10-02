import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template codex_translator}
/// Configures Codex.
///
/// Codex reads `~/.agents/skills` natively. Its agents are TOML.
/// {@endtemplate}
class const CodexTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.codex;

  @override
  bool get runsHooks => true;

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

  /// The plugins' hooks, as `~/.codex/hooks.json` spells them.
  ///
  /// Codex's hooks file has the same shape as Claude's, down to `timeout`
  /// being seconds, so the plugins' scripts run as written. Three things are
  /// spelled differently: the plugin root their commands point at, the tool
  /// names their matchers name, and the payload itself, which every command
  /// goes through [payloadScript] to read as Claude Code's.
  ///
  /// Codex runs no hook it has not been told to trust, however, so writing
  /// this file is half of it and [notes] says the other half.
  ///
  /// See https://developers.openai.com/codex/hooks.
  @override
  String? hooks(PluginAssets assets, {required String hooksRoot}) {
    final events = <String, List<Object?>>{};
    for (final hook in assets.hooks.where(_runs)) {
      events.putIfAbsent(hook.event, () => []).add({
        'matcher': ?_matcher(hook),
        'hooks': [
          for (final command in hook.commands)
            {
              'type': command.type,
              'command': _command(command, hook, hooksRoot: hooksRoot),
              'timeout': ?command.timeout,
            },
        ],
      });
    }
    return events.isEmpty ? null : jsonEncode({'hooks': events});
  }

  /// The hooks Codex will not run, and the trust step that starts the rest.
  @override
  List<TranslationNote> notes(PluginAssets assets) => [
    ...super.notes(assets),
    for (final hook in assets.hooks)
      if (hook.matcher case final matcher? when !_runs(hook))
        TranslationNote(
          subject: '${hook.event} $matcher',
          reason: 'Codex has none of those tools, so the hook could never fire',
        ),
    if (assets.hooks.any(_runs))
      const TranslationNote(
        subject: 'the hooks written to ~/.codex/hooks.json',
        reason:
            'Codex runs no hook it has not been told to trust, so run /hooks '
            'in Codex and trust them',
      ),
  ];

  /// [hook]'s matcher as Codex spells it, and null when it declares none,
  /// which is how both harnesses spell a hook that fires for every tool.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? => _codexTools(declared).join('|'),
    _ => null,
  };

  /// Whether Codex can run [hook].
  ///
  /// A hook with no matcher fires for every tool, so it always can. One whose
  /// matcher names only tools Codex does not have translates to an empty
  /// matcher and could never fire, so it is left out of [hooks] and reported
  /// by [notes] instead.
  static bool _runs(HookAsset hook) => _matcher(hook)?.isNotEmpty ?? true;

  /// The script the brick writes into the harness's own hooks folder, which
  /// hands a plugin script the Codex payload as Claude Code's.
  ///
  /// Every command runs through it rather than only the ones that edit a
  /// file, so the payload a script reads is Claude's whatever fired it, and
  /// nothing here has to track which field each script happens to read.
  static const payloadScript = 'claude-payload.sh';

  /// The handler type whose `command` is a shell command.
  ///
  /// Codex also takes an `mcp_tool` handler, and Claude a `prompt` one.
  /// Neither runs a shell command, so neither has a payload to translate.
  static const _commandType = 'command';

  /// What [command] runs as, once it names a real script and a real payload.
  ///
  /// Both arguments are quoted, because a plugin resolved from a cache under
  /// the user's home sits at a path that may hold spaces.
  static String _command(
    HookCommand command,
    HookAsset hook, {
    required String hooksRoot,
  }) {
    final expanded = command.command.replaceAll(
      HookCommand.pluginRoot,
      hook.pluginRoot.path,
    );
    if (command.type != _commandType) return expanded;

    final script = _quoted(p.join(hooksRoot, payloadScript));
    return 'bash $script ${_quoted(expanded)}';
  }

  /// [value] as one single-quoted shell word.
  static String _quoted(String value) => "'${value.replaceAll("'", r"'\''")}'";

  /// The tools [matcher] fires for, as Codex names them.
  ///
  /// A matcher is an alternation of tool names, so each alternative goes
  /// through [CodexTool] on its own. One Codex has no name for drops out,
  /// which is how a matcher naming nothing it has comes back empty.
  static List<String> _codexTools(String matcher) =>
      {for (final name in matcher.split('|')) ...CodexTool.codexNamesOf(name)}
          .toList();
}
