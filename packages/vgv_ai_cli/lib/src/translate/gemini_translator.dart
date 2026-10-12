import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/hook_scripts.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template gemini_translator}
/// Configures Gemini CLI.
///
/// Gemini reads `~/.agents/skills` natively. Its agents are markdown with
/// frontmatter, its commands TOML under `commands/vgv/` so `/vgv:plan` does
/// not collide with its built-in `/plan`, and its hooks live in
/// `settings.json`, so they are part of [settings].
/// {@endtemplate}
class const GeminiTranslator() extends HarnessTranslator {
  /// Gemini's argument placeholder. Codex, OpenCode and Pi all keep Claude's
  /// `$ARGUMENTS`, so this substitution belongs to Gemini alone.
  static const _arguments = r'$ARGUMENTS';

  @override
  Harness get harness => Harness.gemini;

  @override
  bool get runsHooks => true;

  /// The MCP servers, the context file names, and the hooks.
  ///
  /// `GEMINI.md` stays listed so naming `AGENTS.md` does not drop it. The
  /// hooks have Claude Code's shape under Gemini's event and tool names,
  /// timed in milliseconds, and point at the copy [hookFiles] writes.
  ///
  /// See https://geminicli.com/docs/hooks/reference/.
  @override
  String settings(PluginAssets assets, {required Directory home}) =>
      jsonEncode({
        'mcpServers': {
          for (final server in assets.mcpServers) server.name: server.toJson(),
        },
        'context': {
          'fileName': ['AGENTS.md', 'GEMINI.md'],
        },
        'hooks': ?_hooks(assets, hooksRoot: hooksRoot(home)),
      });

  /// The hooks under Gemini's event names, or null when it can run none.
  static Map<String, List<Object?>>? _hooks(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) {
    final runnable = _runnable(assets);
    if (runnable.isEmpty) return null;
    final byEvent = runnable.groupListsBy((hook) => hook.event);
    return {
      for (final MapEntry(key: event, value: hooks) in byEvent.entries)
        _events[event]!: [
          for (final hook in hooks) _registration(hook, hooksRoot: hooksRoot),
        ],
    };
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
          _handler(command, hook, hooksRoot: hooksRoot),
    ],
  };

  static Map<String, Object?> _handler(
    HookCommand command,
    HookAsset hook, {
    required Directory hooksRoot,
  }) => {
    'type': command.type,
    'command': HookScripts.command(command, hook, hooksRoot: hooksRoot),
    if (command.timeout case final seconds?)
      'timeout': seconds * _millisecondsPerSecond,
  };

  @override
  HarnessFields agent(AgentAsset agent, {required String instructions}) =>
      HarnessFields(
        frontmatter: Frontmatter.render({
          'name': agent.name,
          'description': agent.description,
        }),
      );

  /// Gemini's schema is strict: `prompt` is required, `description` optional,
  /// and nothing else is accepted.
  @override
  HarnessFields command(SkillAsset skill) => HarnessFields(
    toml: TomlDocument.fromMap({
      'description': skill.description,
      'prompt': skill.body.replaceAll(_arguments, '{{args}}'),
    }).toString(),
  );

  /// Gemini's own copy of each plugin's `hooks` folder, with [preamble] at
  /// the top of every script a hook runs.
  @override
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) => _scripts.files(_runnable(assets), hooksRoot: hooksRoot);

  /// What [hookFiles] could not copy as intended, and what [settings] left
  /// out.
  @override
  List<TranslationNote> notes(PluginAssets assets) {
    final runnable = _runnable(assets);
    return [
      ...super.notes(assets),
      ..._scripts.notes(runnable),
      for (final hook in assets.hooks) ?_leftOut(hook),
      ..._handlerNotes(runnable),
    ];
  }

  /// Why [settings] leaves [hook] out, or null when Gemini can run it.
  static TranslationNote? _leftOut(HookAsset hook) {
    if (hook.agent != null) {
      return TranslationNote(
        subject: "${hook.agent}'s ${hook.event} hook",
        reason:
            'Gemini names no agent in a tool call, so a hook an agent '
            'declares for itself cannot be scoped to it and is left out',
      );
    }
    if (!_events.containsKey(hook.event)) {
      return TranslationNote(
        subject: "${hook.plugin}'s ${hook.event} hook",
        reason: 'Gemini has no ${hook.event} event, so it is left out',
      );
    }
    return null;
  }

  /// A note per handler type that runs no shell command, which [settings]
  /// left out, counting the handlers of that type.
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
          reason: 'Gemini runs a shell command only, so they are left out',
        ),
    ];
  }

  /// What goes at the top of Gemini's copy of a hook script, below its
  /// shebang, so a script written for Claude Code runs as written.
  ///
  /// It sets `CLAUDE_PLUGIN_ROOT`, hands the script Claude Code's event and
  /// tool names, and spells the answer as Gemini reads it: a permission
  /// decision at the top level, a session-start line and a post-tool exit 2
  /// as `additionalContext`. An MCP tool keeps Gemini's spelling after the
  /// prefix, since its `_` separator cannot be told from one in a server's
  /// name. Without jq the payload and the output pass as they are.
  ///
  /// `__ROOT__` is replaced with the plugin root as one shell word.
  static const preamble = r'''
# Added by vgv_ai install so this script, written for Claude Code, runs under
# Gemini CLI. Edits here are overwritten on the next run.
export CLAUDE_PLUGIN_ROOT=__ROOT__
if [ -z "${VGV_CLAUDE_PAYLOAD:-}" ]; then
  vgv_payload=$(cat)
  vgv_jq=0
  if command -v jq > /dev/null 2>&1; then
    vgv_jq=1
    vgv_rewritten=$(printf '%s' "$vgv_payload" | jq -c '
      {BeforeTool: "PreToolUse", AfterTool: "PostToolUse",
       BeforeAgent: "UserPromptSubmit", AfterAgent: "Stop",
       PreCompress: "PreCompact"} as $events
      | {run_shell_command: "Bash", replace: "Edit", write_file: "Write",
         read_file: "Read", glob: "Glob", grep: "Grep", ls: "LS"} as $tools
      | if (.hook_event_name | type) == "string"
        then .hook_event_name |= ($events[.] // .) else . end
      | if (.tool_name | type) == "string"
        then .tool_name |= ($tools[.]
          // (if startswith("mcp_") then "mcp__" + .[4:] else . end))
        else . end
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
    vgv_event=$(printf '%s' "$vgv_payload" \
      | jq -r '.hook_event_name // ""' 2> /dev/null)
    if [ -n "$vgv_output" ]; then
      vgv_answer=$(printf '%s' "$vgv_output" | jq -c '
        if (.hookSpecificOutput | type) == "object"
          and (.hookSpecificOutput | has("permissionDecision"))
        then .hookSpecificOutput
          | {decision: .permissionDecision}
            + (if has("permissionDecisionReason")
               then {reason: .permissionDecisionReason} else {} end)
        else . end
      ' 2> /dev/null) && vgv_output=$vgv_answer
      if [ -z "$vgv_answer" ] && [ "$vgv_event" = "SessionStart" ]; then
        vgv_output=$(jq -cn --arg text "$vgv_output" \
          '{hookSpecificOutput: {additionalContext: $text}}')
      fi
    elif [ "$vgv_exit" -eq 2 ] && [ "$vgv_event" = "PostToolUse" ] \
      && [ -n "$vgv_stderr" ]; then
      vgv_output=$(jq -cn --arg text "$vgv_stderr" \
        '{hookSpecificOutput: {additionalContext: $text}}')
      vgv_exit=0
    fi
  fi
  [ -z "$vgv_output" ] || printf '%s\n' "$vgv_output"
  exit "$vgv_exit"
fi
''';

  static const _scripts = HookScripts(
    harness: Harness.gemini,
    preamble: preamble,
  );

  static const _millisecondsPerSecond = 1000;

  /// Gemini's name for each Claude Code event it has one for, as its own
  /// `hooks migrate` maps them.
  static const _events = {
    'PreToolUse': 'BeforeTool',
    'PostToolUse': 'AfterTool',
    'UserPromptSubmit': 'BeforeAgent',
    'Stop': 'AfterAgent',
    'SessionStart': 'SessionStart',
    'SessionEnd': 'SessionEnd',
    'PreCompact': 'PreCompress',
    'Notification': 'Notification',
  };

  /// Gemini's name for each Claude Code built-in tool, likewise.
  static const _tools = {
    'Bash': 'run_shell_command',
    'Edit': 'replace',
    'Write': 'write_file',
    'Read': 'read_file',
    'Glob': 'glob',
    'Grep': 'grep',
    'LS': 'ls',
  };

  /// How Claude Code spells an MCP tool. Gemini uses `mcp_` and `_`.
  static const _mcpPrefix = 'mcp__';
  static const _mcpSeparator = '__';

  /// The hooks Gemini can run.
  static List<HookAsset> _runnable(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (_leftOut(hook) == null) hook,
  ];

  /// [hook]'s matcher with each alternative respelled to Gemini's tool
  /// name, or null when it declares none.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? => declared.split('|').map(_geminiTool).join('|'),
    _ => null,
  };

  /// [alternative] as Gemini names the tool it matches.
  static String _geminiTool(String alternative) =>
      _tools[alternative] ?? _geminiMcpTool(alternative);

  /// [alternative] respelled from `mcp__<server>__<tool>` to
  /// `mcp_<server>_<tool>`.
  static String _geminiMcpTool(String alternative) {
    if (!alternative.startsWith(_mcpPrefix)) return alternative;
    final rest = alternative.substring(_mcpPrefix.length);
    return 'mcp_${rest.replaceAll(_mcpSeparator, '_')}';
  }
}
