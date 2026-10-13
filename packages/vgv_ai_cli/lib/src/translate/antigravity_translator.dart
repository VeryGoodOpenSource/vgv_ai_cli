import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/hook_scripts.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template antigravity_translator}
/// Configures Antigravity CLI.
///
/// Everything goes into one Antigravity plugin, `plugins/vgv/`, which is how
/// Antigravity bundles skills, agents, MCP servers, hooks and rules. It reads
/// neither `~/.agents/skills` nor a commands folder: the skills are copied
/// into the plugin and each becomes a `/<name>` command on its own.
///
/// See https://antigravity.google/docs/plugins/.
/// {@endtemplate}
class const AntigravityTranslator() extends HarnessTranslator {
  /// The plugin everything is installed as.
  static const plugin = 'vgv';

  @override
  Harness get harness => Harness.antigravity;

  @override
  bool get readsSharedSkills => false;

  @override
  bool get runsHooks => true;

  /// The plugin's root under Antigravity's config directory.
  Directory pluginRoot(Directory home) {
    final config = harness.configDirectory(home);
    return config.fileSystem.directory(p.join(config.path, 'plugins', plugin));
  }

  @override
  Directory skillsRoot(Directory home) =>
      pluginRoot(home).childDirectory('skills');

  @override
  Directory hooksRoot(Directory home) =>
      pluginRoot(home).childDirectory(HookScripts.hooksFolder);

  /// The plugin's `mcp_config.json`. A remote server's endpoint is
  /// `serverUrl`.
  @override
  String settings(PluginAssets assets) => jsonEncode({
    'mcpServers': {
      for (final server in assets.mcpServers)
        server.name: switch (server) {
          LocalMCPServer() => server.toJson(),
          RemoteMCPServer(:final url, :final headers) => {
            'serverUrl': url,
            if (headers.isNotEmpty) 'headers': headers,
          },
        },
    },
  });

  /// An agent names its skills in the frontmatter, relative to the plugin,
  /// so its instructions are the body alone rather than the shared pointer.
  @override
  HarnessFields agent(AgentAsset agent, {required String instructions}) =>
      HarnessFields(
        frontmatter: Frontmatter.render({
          'name': agent.name,
          'description': agent.description,
          'subagent': true,
          if (agent.skills.isNotEmpty)
            'skills': [for (final skill in agent.skills) 'skills/$skill'],
        }),
        instructions: '${agent.body.trimRight()}\n',
      );

  /// The plugin's `hooks.json`: one set per source plugin, under the event
  /// names Antigravity shares with Claude Code, with matchers respelled to
  /// its tool names and a timeout in seconds. Each command carries the event
  /// in `VGV_HOOK_EVENT`, since the payload does not name it.
  ///
  /// See https://antigravity.google/docs/hooks/.
  @override
  String? hooks(PluginAssets assets, {required Directory hooksRoot}) {
    final runnable = _runnable(assets);
    if (runnable.isEmpty) return null;
    return jsonEncode({
      for (final MapEntry(key: source, value: hooks)
          in runnable.groupListsBy((hook) => hook.plugin).entries)
        source: {
          for (final MapEntry(key: event, value: registrations)
              in hooks.groupListsBy((hook) => hook.event).entries)
            event: [
              for (final hook in registrations)
                _registration(hook, hooksRoot: hooksRoot),
            ],
        },
    });
  }

  /// [hook]'s matcher and one handler per shell command.
  static Map<String, Object?> _registration(
    HookAsset hook, {
    required Directory hooksRoot,
  }) => {
    'matcher': ?_matcher(hook),
    'hooks': [
      for (final command in hook.commands)
        if (command.type == HookScripts.commandType)
          {
            'type': command.type,
            'command':
                'VGV_HOOK_EVENT=${hook.event} '
                '${HookScripts.command(command, hook, hooksRoot: hooksRoot)}',
            'timeout': ?command.timeout,
          },
    ],
  };

  @override
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) => _scripts.files(_runnable(assets), hooksRoot: hooksRoot);

  @override
  List<TranslationNote> notes(PluginAssets assets) {
    final runnable = _runnable(assets);
    return [
      ...super.notes(assets),
      ..._scripts.notes(runnable),
      for (final hook in assets.hooks) ?_leftOut(hook),
      if (runnable.any((hook) => hook.event == 'PostToolUse'))
        const TranslationNote(
          subject: 'the PostToolUse hooks',
          reason:
              'Antigravity reads nothing a hook says after a tool, so they '
              'run but the agent hears none of it',
        ),
      ..._handlerNotes(runnable),
    ];
  }

  /// Why [hooks] leaves [hook] out, or null when Antigravity can run it.
  static TranslationNote? _leftOut(HookAsset hook) {
    if (hook.agent != null) {
      return TranslationNote(
        subject: "${hook.agent}'s ${hook.event} hook",
        reason:
            'Antigravity names no agent in a tool call, so a hook an agent '
            'declares for itself cannot be scoped to it and is left out',
      );
    }
    if (!_events.contains(hook.event)) {
      return TranslationNote(
        subject: "${hook.plugin}'s ${hook.event} hook",
        reason: 'Antigravity has no ${hook.event} event, so it is left out',
      );
    }
    return null;
  }

  /// A note per handler type that runs no shell command, counting them.
  static List<TranslationNote> _handlerNotes(List<HookAsset> hooks) {
    final counts = hooks
        .expand((hook) => hook.commands)
        .map((command) => command.type)
        .where((type) => type != HookScripts.commandType)
        .groupFoldBy<String, int>(
          (type) => type,
          (count, _) => (count ?? 0) + 1,
        );
    return [
      for (final MapEntry(key: type, value: count) in counts.entries)
        TranslationNote(
          subject: '$count $type handler(s)',
          reason: 'Antigravity runs a shell command only, so they are left out',
        ),
    ];
  }

  /// What goes at the top of Antigravity's copy of a hook script, below its
  /// shebang, so a script written for Claude Code runs as written.
  ///
  /// Antigravity sends `toolCall.name` and `toolCall.args` under its own
  /// names, `workspacePaths` for the directory, and no event name; the
  /// preamble hands the script Claude Code's payload, with the event from
  /// `VGV_HOOK_EVENT`. Its answer is spelled as Antigravity reads it: a
  /// permission decision, or an exit 2 with its stderr, becomes the
  /// top-level `decision` before a tool; after a tool nothing is read, so
  /// `{}` is answered; a session-start line becomes `injectSteps`. Exit
  /// codes are undocumented, so the script's is not passed on. Without jq
  /// the payload and the output pass as they are.
  ///
  /// `__ROOT__` is replaced with the plugin root as one shell word.
  static const preamble = r'''
# Added by vgv_ai install so this script, written for Claude Code, runs under
# Antigravity CLI. Edits here are overwritten on the next run.
export CLAUDE_PLUGIN_ROOT=__ROOT__
if [ -z "${VGV_CLAUDE_PAYLOAD:-}" ]; then
  vgv_payload=$(cat)
  vgv_event=${VGV_HOOK_EVENT:-}
  vgv_jq=0
  if command -v jq > /dev/null 2>&1; then
    vgv_jq=1
    vgv_rewritten=$(printf '%s' "$vgv_payload" | jq -c --arg event "$vgv_event" '
      {run_command: "Bash", write_to_file: "Write", replace_file_content: "Edit",
       multi_replace_file_content: "Edit", view_file: "Read",
       find_by_name: "Glob", grep_search: "Grep", list_dir: "LS"} as $tools
      | (.toolCall.args // {}) as $args
      | {hook_event_name: $event, session_id: (.conversationId // ""),
         transcript_path: (.transcriptPath // ""),
         cwd: (.workspacePaths[0] // "")}
      + (if .toolCall then
          {tool_name: ($tools[.toolCall.name] // .toolCall.name),
           tool_input: ($args
             + (if $args.CommandLine then {command: $args.CommandLine}
                else {} end)
             + (if $args.TargetFile then {file_path: $args.TargetFile}
                else {} end)
             + (if $args.AbsolutePath then {file_path: $args.AbsolutePath}
                else {} end))}
         else {} end)
    ' 2> /dev/null) && vgv_payload=$vgv_rewritten
  fi
  vgv_errors=$(mktemp)
  vgv_output=$(printf '%s' "$vgv_payload" \
    | VGV_CLAUDE_PAYLOAD=1 bash "$0" 2> "$vgv_errors")
  vgv_exit=$?
  vgv_stderr=$(cat "$vgv_errors")
  rm -f "$vgv_errors"
  [ -z "$vgv_stderr" ] || printf '%s\n' "$vgv_stderr" >&2
  if [ "$vgv_jq" -eq 1 ]; then
    case "$vgv_event" in
      PreToolUse)
        vgv_answer=$(printf '%s' "$vgv_output" | jq -c '
          if (.hookSpecificOutput | type) == "object"
            and (.hookSpecificOutput | has("permissionDecision"))
          then .hookSpecificOutput
            | {decision: .permissionDecision}
              + (if has("permissionDecisionReason")
                 then {reason: .permissionDecisionReason} else {} end)
          else . end
        ' 2> /dev/null) && vgv_output=$vgv_answer
        if [ -z "$vgv_answer" ] && [ "$vgv_exit" -eq 2 ] \
          && [ -n "$vgv_stderr" ]; then
          vgv_output=$(jq -cn --arg text "$vgv_stderr" \
            '{decision: "deny", reason: $text}')
        fi
        ;;
      PostToolUse)
        vgv_output='{}'
        ;;
      SessionStart)
        if [ -n "$vgv_output" ]; then
          vgv_output=$(jq -cn --arg text "$vgv_output" \
            '{injectSteps: [{systemMessage: $text}]}')
        fi
        ;;
    esac
  fi
  [ -z "$vgv_output" ] || printf '%s\n' "$vgv_output"
  exit 0
fi
''';

  static const _scripts = HookScripts(
    harness: Harness.antigravity,
    preamble: preamble,
  );

  /// The Claude Code events Antigravity has under the same name.
  static const _events = {'PreToolUse', 'PostToolUse', 'SessionStart', 'Stop'};

  /// Antigravity's name for each Claude Code built-in tool.
  static const _tools = {
    'Bash': 'run_command',
    'Edit': 'replace_file_content|multi_replace_file_content',
    'Write': 'write_to_file',
    'Read': 'view_file',
    'Glob': 'find_by_name',
    'Grep': 'grep_search',
    'LS': 'list_dir',
  };

  /// How Claude Code spells an MCP tool. How Antigravity spells one in a
  /// hook is undocumented, so the server's name is matched anywhere.
  static const _mcpPrefix = 'mcp__';
  static const _mcpSeparator = '__';

  /// The hooks Antigravity can run.
  static List<HookAsset> _runnable(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (_leftOut(hook) == null) hook,
  ];

  /// [hook]'s matcher with each alternative respelled to Antigravity's tool
  /// name, or null when it declares none.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? => declared.split('|').map(_antigravityTool).join('|'),
    _ => null,
  };

  /// [alternative] as Antigravity names the tool it matches.
  static String _antigravityTool(String alternative) =>
      _tools[alternative] ?? _antigravityMcpTool(alternative);

  /// [alternative] respelled from `mcp__<server>__<tool>` to a pattern over
  /// the server's name.
  static String _antigravityMcpTool(String alternative) {
    if (!alternative.startsWith(_mcpPrefix)) return alternative;
    final rest = alternative.substring(_mcpPrefix.length);
    return '.*${rest.replaceAll(_mcpSeparator, '.*')}'.replaceAll(
      _repeatedWildcard,
      '.*',
    );
  }

  /// `.*` written twice over, as a matcher already ending in one gets.
  static final _repeatedWildcard = RegExp(r'(\.\*){2,}');
}
