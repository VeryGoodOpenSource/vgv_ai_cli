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
/// Gemini reads `~/.agents/skills` natively. Its agents are markdown with a
/// `name` its loader validates against a pattern the parser's name rule
/// already satisfies, and its commands are TOML with their own argument
/// placeholder. The brick namespaces the commands under `vgv/`, so they load
/// as `/vgv:plan` rather than colliding with Gemini's built-in `/plan`.
///
/// Its hooks are entries in `settings.json`, the same file the MCP servers
/// go in, so they are part of [settings] rather than a file of their own.
/// {@endtemplate}
class const GeminiTranslator() extends HarnessTranslator {
  /// Gemini's argument placeholder. Codex, OpenCode and Pi all keep Claude's
  /// `$ARGUMENTS`, so this substitution belongs to Gemini alone.
  static const _arguments = r'$ARGUMENTS';

  @override
  Harness get harness => Harness.gemini;

  @override
  bool get runsHooks => true;

  /// The MCP servers, the instruction file names Gemini loads, and the
  /// plugins' hooks.
  ///
  /// `AGENTS.md` is listed so Gemini reads the VGV section, and `GEMINI.md`
  /// so naming a second file does not stop it reading its default one.
  ///
  /// The hooks sit under Gemini's own event names, and each registration has
  /// the shape Claude Code's has, down to the matcher being a regex over
  /// tool names. Three things are spelled differently: the event names, the
  /// tool names the matchers name, and the timeout, which Gemini reads in
  /// milliseconds. The commands point at Gemini's own copy of each plugin's
  /// `hooks` folder under [hooksRoot], the one [hookFiles] writes, which is
  /// where the payload is answered.
  ///
  /// A hook an agent declared for itself is left out: Gemini's tool payload
  /// names no agent, so there is nothing to scope it by, and a guard meant
  /// for one agent would run for all of them. So is a hook on an event
  /// Gemini has no name for.
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

  /// The plugins' hooks under Gemini's event names, or null when it can run
  /// none, so a settings file without hooks gains no empty `hooks` key.
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

  /// One registration of [hook], as Gemini's settings spell it: its matcher
  /// and one handler per shell command.
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

  /// One handler of [hook] running [command], timed in milliseconds.
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
  ///
  /// A hook an agent declared for itself has nothing to scope it by, since
  /// Gemini names no agent in a tool call, and a hook on an event Gemini
  /// has no name for cannot fire.
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
  /// It answers what Gemini hands a script differently. It sets
  /// `CLAUDE_PLUGIN_ROOT`, which Gemini does not, to the plugin's real
  /// location. It names the event and the tool as Claude Code does, where
  /// Gemini sends its own names: `BeforeTool` for `PreToolUse`,
  /// `run_shell_command` for `Bash`, `mcp_<server>_<tool>` for
  /// `mcp__<server>__<tool>`. An MCP tool keeps Gemini's spelling after the
  /// prefix, since Gemini's `_` between server and tool cannot be told from
  /// one inside a server's name, and the scripts match on the server's name
  /// alone. A file's path arrives under `tool_input.file_path` from both,
  /// so that is left as it came.
  ///
  /// What a script says is spelled as Gemini reads it. A permission decision
  /// the script writes under `hookSpecificOutput` becomes the top-level
  /// `decision` and `reason` Gemini reads. A plain line at session start,
  /// which Claude Code hands the agent, becomes `additionalContext`, since
  /// Gemini would show it to the user instead. And what a script exiting 2
  /// says on stderr after a tool, which Claude Code hands the agent beside
  /// the tool's result, becomes `additionalContext` with exit 0, since
  /// Gemini would hide the result behind it. Before a tool, an exit 2 with
  /// its stderr is a denial under both, so it passes as it is. Without jq
  /// the payload and the output pass as they are.
  ///
  /// It is bash, as the plugins' scripts are, so it goes only into a script
  /// bash runs. `__ROOT__` is replaced with the plugin root as one shell
  /// word.
  static const preamble = r'''
# Added by vgv_ai install so this script, written for Claude Code, runs under
# Gemini CLI. Edits here are overwritten on the next run.
#
# Gemini sets no CLAUDE_PLUGIN_ROOT, so it is set to the plugin's real files.
# Gemini names its events and tools its own way where the script reads Claude
# Code's, reads a permission decision at the top level where the script
# writes one under hookSpecificOutput, shows a plain line at session start to
# the user where Claude Code hands it to the agent, and hides a tool's result
# behind what a script exiting 2 says where Claude Code hands it to the agent
# beside the result. So the script below gets the payload under Claude
# Code's names, and its answer is spelled as Gemini reads it. Without jq the
# payload and the output pass as they are.
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

  /// Gemini reads a hook's timeout in milliseconds, Claude Code in seconds.
  static const _millisecondsPerSecond = 1000;

  /// Gemini's name for each of Claude Code's events it has one for, as its
  /// own `hooks migrate` maps them. An event not here, Gemini cannot fire.
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

  /// Gemini's name for each of Claude Code's built-in tools, as its own
  /// `hooks migrate` maps them.
  static const _tools = {
    'Bash': 'run_shell_command',
    'Edit': 'replace',
    'Write': 'write_file',
    'Read': 'read_file',
    'Glob': 'glob',
    'Grep': 'grep',
    'LS': 'ls',
  };

  /// The prefix Claude Code gives an MCP tool's name, and the separator it
  /// puts between the server and the tool. Gemini uses `mcp_` and `_`.
  static const _mcpPrefix = 'mcp__';
  static const _mcpSeparator = '__';

  /// The hooks Gemini can run: every one [_leftOut] has no reason to leave
  /// out.
  static List<HookAsset> _runnable(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (_leftOut(hook) == null) hook,
  ];

  /// [hook]'s matcher as Gemini spells it, and null when it declares none,
  /// which is how both harnesses spell a hook that fires for every tool.
  ///
  /// A matcher is read as a top-level alternation, which is how the plugins
  /// write theirs, so a `|` inside a group is split like any other. Each
  /// alternative naming a built-in tool is respelled from [_tools], and one
  /// naming an MCP tool from `mcp__<server>__<tool>` to
  /// `mcp_<server>_<tool>`. Any other alternative is a pattern over such
  /// names and carries over as written.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? => declared.split('|').map(_geminiTool).join('|'),
    _ => null,
  };

  /// [alternative] as Gemini names the tool it matches.
  static String _geminiTool(String alternative) =>
      _tools[alternative] ?? _geminiMcpTool(alternative);

  /// [alternative] respelled from `mcp__<server>__<tool>` to
  /// `mcp_<server>_<tool>`, or as it is when it names no MCP tool.
  static String _geminiMcpTool(String alternative) {
    if (!alternative.startsWith(_mcpPrefix)) return alternative;
    final rest = alternative.substring(_mcpPrefix.length);
    return 'mcp_${rest.replaceAll(_mcpSeparator, '_')}';
  }
}
