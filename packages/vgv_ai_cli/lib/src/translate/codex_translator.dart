import 'dart:convert';

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
  /// names their matchers name, and which file an edit touched, which
  /// [_command] reads out of Codex's payload for the scripts that need it.
  ///
  /// Codex runs no hook it has not been told to trust, however, so writing
  /// this file is half of it and [notes] says the other half.
  ///
  /// See https://developers.openai.com/codex/hooks.
  @override
  String? hooks(PluginAssets assets) {
    final events = <String, List<Object?>>{};
    for (final hook in assets.hooks.where(_runs)) {
      events.putIfAbsent(hook.event, () => []).add({
        'matcher': ?_matcher(hook),
        'hooks': [
          for (final command in hook.commands)
            {
              'type': command.type,
              'command': _command(command, hook),
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

  /// The handler type whose `command` is a shell command.
  ///
  /// Codex also takes an `mcp_tool` handler, and Claude a `prompt` one.
  /// Neither runs a shell command, so neither is handed anything.
  static const _commandType = 'command';

  /// The event whose payload says which files a tool touched.
  static const _afterTool = 'PostToolUse';

  /// A jq program printing each file an `apply_patch` call added or changed,
  /// one per line, as an absolute path.
  ///
  /// Codex reports an edit as `apply_patch` with the patch itself as the
  /// input, and no `file_path`. The files it touched are in the response
  /// instead, one `A path`, `M path` or `D path` line each, as the model
  /// spelled them, so a relative one is resolved against the payload's own
  /// `cwd`. A deleted file is left out, there being nothing left to check,
  /// and a rename reports its new name under `M`.
  ///
  /// `strings` makes the program print nothing for any other shape of
  /// response, so a script fired by something other than a patch is handed
  /// no files rather than a jq error.
  static const _patchedFiles =
      r'(.cwd // ".") as $cwd'
      ' | .tool_response | strings'
      r' | scan("(?m)^[AM] (.+)$") | .[0]'
      r' | if startswith("/") then . else $cwd + "/" + . end';

  /// What [command] runs as, once it names a real plugin root and, for a
  /// script that watches file edits, the files that were edited.
  ///
  /// The plugins read the edited file from `tool_input.file_path`, which is
  /// Claude Code's spelling, and take the files as arguments otherwise. A
  /// shell command on [_afterTool] for a file-editing tool gets them that
  /// way: [_patchedFiles] reads them out of the payload and `xargs` passes
  /// them on, NUL-separated so a path may hold a space.
  ///
  /// `xargs` reports a failing command as 123, where Codex, like Claude,
  /// reads 2 as "block, and show the model what went wrong on stderr". The
  /// scripts exit with nothing but 0 or 2, so any failure is mapped back to
  /// 2 and the analyzer's output reaches the model as it does on Claude.
  static String _command(HookCommand command, HookAsset hook) {
    final expanded = command.command.replaceAll(
      HookCommand.pluginRoot,
      hook.pluginRoot.path,
    );
    if (command.type != _commandType || !_editsFiles(hook)) return expanded;

    return "jq -r '$_patchedFiles' | tr '\\n' '\\0' | xargs -0 $expanded"
        ' || exit 2';
  }

  /// Whether [hook] runs after a tool that edits files, which is when the
  /// payload names them.
  static bool _editsFiles(HookAsset hook) =>
      hook.event == _afterTool &&
      (_matcher(hook)?.split('|').contains(CodexTool.applyPatch) ?? false);

  /// The tools [matcher] fires for, as Codex names them.
  ///
  /// A matcher is an alternation of tool names, so each alternative goes
  /// through [CodexTool] on its own. One Codex has no name for drops out,
  /// which is how a matcher naming nothing it has comes back empty.
  static List<String> _codexTools(String matcher) =>
      {for (final name in matcher.split('|')) ...CodexTool.codexNamesOf(name)}
          .toList();
}
