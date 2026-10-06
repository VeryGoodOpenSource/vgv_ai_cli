import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
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
  /// being seconds. Two things are spelled differently here: the tool names
  /// the matchers name, and the plugin root the commands point at, which is
  /// Codex's own copy of each plugin's scripts under [hooksRoot], the one
  /// [hookFiles] writes. The copy is where the third difference, the payload,
  /// is answered.
  ///
  /// Codex runs no hook it has not been told to trust, however, so writing
  /// this file is half of it and [notes] says the other half.
  ///
  /// See https://developers.openai.com/codex/hooks.
  @override
  String? hooks(PluginAssets assets, {required Directory hooksRoot}) {
    final events = <String, List<Object?>>{};
    for (final hook in assets.hooks.where(_runs)) {
      events.putIfAbsent(hook.event, () => []).add({
        'matcher': ?_matcher(hook),
        'hooks': [
          for (final command in hook.commands)
            {
              'type': command.type,
              'command': command.command.replaceAll(
                HookCommand.pluginRoot,
                _copyRoot(hook, hooksRoot).path,
              ),
              'timeout': ?command.timeout,
            },
        ],
      });
    }
    return events.isEmpty ? null : jsonEncode({'hooks': events});
  }

  /// Codex's own copy of each plugin's `hooks` folder, under [hooksRoot] and
  /// the plugin's name, with [preamble] at the top of every script a hook
  /// runs.
  ///
  /// The whole folder comes along, because a script sources its neighbours
  /// and reads files beside it by its own location. The one exception is the
  /// plugin's `hooks.json`, which is what [hooks] translated, so a copy of it
  /// would only mislead. A file is copied from its source so it keeps its
  /// mode, which matters for a hook that runs its script directly.
  ///
  /// A plugin whose `hooks` folder has gone away, as a cache cleared between
  /// resolution and translation does, gets no copy; [hooks] still names the
  /// scripts, and Codex reports the missing file when one fires.
  @override
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) {
    final changes = <PlannedChange>[];
    final byPlugin = assets.hooks.where(_runs).groupListsBy((h) => h.plugin);

    for (final hooks in byPlugin.values) {
      final pluginRoot = hooks.first.pluginRoot;
      final source = pluginRoot.childDirectory(_hooksFolder);
      if (!source.existsSync()) continue;

      final target = _copyRoot(hooks.first, hooksRoot);
      final scripts = {for (final hook in hooks) ..._scriptsOf(hook)};
      final entities = source.listSync(recursive: true, followLinks: false);

      for (final entity in entities) {
        if (entity is! File) continue;

        final relative = p.relative(entity.path, from: pluginRoot.path);
        if (relative == _registry) continue;

        final bytes = entity.readAsBytesSync();
        changes.add(
          PlannedChange(
            file: target.fileSystem.file(p.join(target.path, relative)),
            bytes: scripts.contains(relative)
                ? _withPreamble(bytes, pluginRoot)
                : bytes,
            harness: harness,
            source: entity,
          ),
        );
      }
    }
    return changes;
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

  /// What goes at the top of Codex's copy of a hook script, below any
  /// shebang, so a script written for Claude Code runs as written.
  ///
  /// It answers the two things Codex hands a script differently. It sets
  /// `CLAUDE_PLUGIN_ROOT`, which Codex does not and which a script may read
  /// to find the plugin's other files, to the plugin's real location. And it
  /// rewrites a file edit: Claude Code sends one `Edit` or `Write` per file,
  /// naming it in `tool_input.file_path`, where Codex sends one `apply_patch`
  /// holding the patch text and names no file. So the preamble reads the
  /// files out of the patch headers and runs the script once per file that
  /// still exists, each time with the payload Claude Code would have sent,
  /// then exits with the first failure. Any other payload, and every payload
  /// when jq is missing, reaches the script as it came.
  ///
  /// `__ROOT__` is replaced with the plugin root as one shell word.
  static const preamble = r'''
# Added by vgv_ai install so this script, written for Claude Code, runs under
# Codex. Edits here are overwritten on the next run.
#
# Codex sets no CLAUDE_PLUGIN_ROOT, so it is set to the plugin's real files.
# And Codex reports a file edit as one apply_patch holding the patch text,
# where Claude Code sends an Edit or Write per file, naming it in
# tool_input.file_path. So the script below runs once per file the patch
# touches, each time with the payload Claude Code would have sent. Any other
# payload reaches it as it came, and so does every payload when jq is missing.
export CLAUDE_PLUGIN_ROOT=__ROOT__
if [ -z "${VGV_CLAUDE_PAYLOAD:-}" ] && command -v jq > /dev/null 2>&1; then
  vgv_payload=$(cat)
  # One line per file: the tool Claude Code would have named, a tab, and the
  # path resolved against the payload's own cwd, since a patch header names a
  # file relative to the session root when the model wrote it that way.
  vgv_edits=$(printf '%s' "$vgv_payload" | jq -r '
    ((.cwd // ".") | rtrimstr("/")) as $cwd
    | .tool_input.command // ""
    | scan("(?m)^\\*\\*\\* (Add File|Update File|Move to): (.+)$")
    | (if .[0] == "Add File" then "Write" else "Edit" end)
      + "\t" + (.[1] | if startswith("/") then . else $cwd + "/" + . end)
  ' 2> /dev/null)
  vgv_status=0
  vgv_ran=0
  while IFS=$'\t' read -r vgv_tool vgv_file; do
    # A deleted file, or the old name of a renamed one, is no longer there.
    [ -n "$vgv_file" ] && [ -f "$vgv_file" ] || continue
    vgv_ran=1
    printf '%s' "$vgv_payload" \
      | jq --arg tool "$vgv_tool" --arg file "$vgv_file" \
        '.tool_name = $tool | .tool_input.file_path = $file' \
      | VGV_CLAUDE_PAYLOAD=1 bash "$0" || vgv_status=$?
  done <<< "$vgv_edits"
  if [ "$vgv_ran" -eq 1 ]; then exit "$vgv_status"; fi
  exec < <(printf '%s' "$vgv_payload")
fi
''';

  /// The folder a Claude Code plugin keeps its hooks in.
  static const _hooksFolder = 'hooks';

  /// The plugin's own hook registry, relative to its root.
  static final String _registry = p.join(_hooksFolder, 'hooks.json');

  /// The handler type whose `command` is a shell command.
  ///
  /// Codex also takes an `mcp_tool` handler, and Claude a `prompt` one.
  /// Neither runs a script, so neither names one to copy.
  static const _commandType = 'command';

  /// A plugin file a command names, relative to the plugin root.
  static final _pluginFile = RegExp(
    '${RegExp.escape(HookCommand.pluginRoot)}/(\\S+)',
  );

  /// Where Codex's copy of [hook]'s plugin goes under [hooksRoot].
  static Directory _copyRoot(HookAsset hook, Directory hooksRoot) =>
      hooksRoot.childDirectory(hook.plugin);

  /// The plugin files [hook]'s shell commands name, relative to the plugin
  /// root, which are the scripts that get the [preamble].
  static Iterable<String> _scriptsOf(HookAsset hook) => [
    for (final command in hook.commands)
      if (command.type == _commandType)
        for (final match in _pluginFile.allMatches(command.command)) match[1]!,
  ];

  /// [bytes] with the [preamble] inserted below the shebang line, or at the
  /// top when there is none.
  static List<int> _withPreamble(List<int> bytes, Directory pluginRoot) {
    final script = utf8.decode(bytes);
    final body = preamble.replaceAll('__ROOT__', _quoted(pluginRoot.path));
    final shebang = script.startsWith('#!') ? script.indexOf('\n') + 1 : 0;
    return utf8.encode(
      '${script.substring(0, shebang)}$body${script.substring(shebang)}',
    );
  }

  /// [value] as one single-quoted shell word.
  static String _quoted(String value) => "'${value.replaceAll("'", r"'\''")}'";

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

  /// The tools [matcher] fires for, as Codex names them.
  ///
  /// A matcher is an alternation of tool names, so each alternative goes
  /// through [CodexTool] on its own. One Codex has no name for drops out,
  /// which is how a matcher naming nothing it has comes back empty.
  static List<String> _codexTools(String matcher) =>
      {for (final name in matcher.split('|')) ...CodexTool.codexNamesOf(name)}
          .toList();
}
