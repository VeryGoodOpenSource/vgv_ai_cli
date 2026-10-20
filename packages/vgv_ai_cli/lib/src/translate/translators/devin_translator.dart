import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// {@template devin_translator}
/// Configures Devin CLI.
///
/// Devin reads `~/.agents/skills` natively and makes each skill a `/<name>`
/// command of its own, so it needs no commands folder. Its agents are the
/// markdown subagent profiles under `agents/`, and its rules are
/// `AGENTS.md`.
///
/// See https://docs.devin.ai/cli/extensibility.
/// {@endtemplate}
class const DevinTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.devin;

  /// The file under the hooks root that holds [devinCompatScript].
  static const compatScript = 'vgv-claude-compat.sh';

  /// The MCP servers, in the shape `mcp_config.json` already declares them.
  @override
  String settings(PluginAssets assets) => jsonEncode({
    'mcpServers': {
      for (final server in assets.mcpServers) server.name: server.toJson(),
    },
  });

  /// A subagent profile takes the same frontmatter as a skill, of which
  /// Devin reads `name` and `description`.
  @override
  HarnessFields agent(AgentAsset agent, {required String instructions}) =>
      HarnessFields(
        frontmatter: Frontmatter.render({
          'name': agent.name,
          'description': agent.description,
        }),
      );

  /// The plugins' hooks as the `hooks` key of `~/.config/devin/config.json`
  /// spells them: Claude Code's shape, Devin's tool names, and commands
  /// pointing at Devin's copy of each plugin's `hooks` folder under
  /// `<hooksRoot>/<plugin>`, with [devinCompatScript] beside it.
  ///
  /// A hook an agent declared for itself, and one on an event Devin lacks,
  /// are left out. So is any handler that is not a shell command: Devin
  /// rejects a handler type it does not know by dropping every hook in the
  /// file, not just that one. Before a tool Devin reads a decision and
  /// nothing else, so a hook that only injects context is reported.
  ///
  /// See https://docs.devin.ai/cli/extensibility/hooks/overview.
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
            contents: devinCompatScript,
            harness: harness,
          ),
        ...copy.files,
      ],
      notes: [
        ...copy.notes,
        for (final hook in assets.hooks) ?_leftOut(hook),
        if (runnable.any((hook) => hook.event == 'PreToolUse'))
          const TranslationNote(
            subject: 'the PreToolUse hooks',
            reason:
                'Devin reads a decision before a tool but not injected '
                'context, so one that only adds context runs and the agent '
                'hears none of it',
          ),
        ..._handlerNotes(runnable),
      ],
    );
  }

  /// The `hooks` fragment of `config.json`, or null when there is no command
  /// to run.
  static String? _fragment(
    List<HookAsset> hooks, {
    required Directory hooksRoot,
  }) {
    final events = <String, List<Object?>>{};
    for (final hook in hooks.where(HookScripts.safelyNamed)) {
      final handlers = _handlers(hook, hooksRoot: hooksRoot);
      if (handlers.isEmpty) continue;
      events.putIfAbsent(hook.event, () => []).add({
        'matcher': ?_matcher(hook),
        'hooks': handlers,
      });
    }
    return events.isEmpty ? null : jsonEncode({'hooks': events});
  }

  /// One handler per shell command of [hook].
  static List<Map<String, Object?>> _handlers(
    HookAsset hook, {
    required Directory hooksRoot,
  }) => [
    for (final command in hook.commands)
      if (command.type == HookScripts.commandType)
        {
          'type': command.type,
          'command': HookScripts.command(command, hook, hooksRoot: hooksRoot),
          'timeout': ?command.timeout,
        },
  ];

  /// Why [hooks] leaves [hook] out, or null when Devin can run it.
  static TranslationNote? _leftOut(HookAsset hook) {
    if (hook.agent != null) {
      return TranslationNote(
        subject: "${hook.agent}'s ${hook.event} hook",
        reason:
            'Devin names no subagent in a hook payload, so a hook an agent '
            'declares for itself cannot be scoped to it and is left out',
      );
    }
    if (!_events.contains(hook.event)) {
      return TranslationNote(
        subject: "${hook.plugin}'s ${hook.event} hook",
        reason: 'Devin has no ${hook.event} event, so it is left out',
      );
    }
    return null;
  }

  /// One note per handler type that runs no shell command.
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
          reason:
              'Devin drops every hook in a file that declares a handler type '
              'it does not know, so they are left out',
        ),
    ];
  }

  @override
  HookScripts get scripts =>
      const HookScripts(harness: Harness.devin, preamble: devinPreamble);

  /// The Claude Code events Devin has under the same name.
  static const _events = {
    'PreToolUse',
    'PostToolUse',
    'UserPromptSubmit',
    'SessionStart',
    'SessionEnd',
    'Stop',
  };

  /// Devin's name for each Claude Code built-in tool, as its hooks reference
  /// lists them. `apply_patch` is a file-operation tool beside `edit` and
  /// `write`, so an edit matcher names it too; what its `tool_input` holds is
  /// not documented, so a script that needs `file_path` may find none.
  static const _tools = {
    'Bash': ['exec'],
    'Edit': ['edit', 'apply_patch'],
    'Write': ['write', 'apply_patch'],
    'Read': ['read'],
    'Glob': ['glob'],
    'Grep': ['grep'],
  };

  /// A matcher that is a flat `A|B` list of tool names, the one shape whose
  /// names are mapped; any other regex is handed to Devin as written, which
  /// is what the plugins' `mcp__…` matchers need, since Devin spells an MCP
  /// tool exactly as Claude Code does.
  static final _flatList = RegExp(r'^\w+(\|\w+)*$');

  /// The hooks Devin can run.
  static List<HookAsset> _runnable(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (_leftOut(hook) == null) hook,
  ];

  /// [hook]'s matcher as Devin spells it, null when it declares none.
  ///
  /// Devin matches the regex anywhere in the tool name, so a mapped list is
  /// anchored: unanchored, `write` would also fire on `todo_write` and
  /// `write_to_process`.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? when _flatList.hasMatch(declared) =>
      '^(${{
        for (final name in declared.split('|')) ...(_tools[name] ?? [name]),
      }.join('|')})\$',
    final declared => declared,
  };
}
