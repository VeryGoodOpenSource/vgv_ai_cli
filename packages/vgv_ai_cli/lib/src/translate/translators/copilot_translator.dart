import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// {@template copilot_translator}
/// Configures GitHub Copilot CLI.
///
/// Copilot reads `~/.agents/skills` natively and invokes skills by name, so
/// it needs no commands.
/// {@endtemplate}
class const CopilotTranslator() extends HarnessTranslator {
  /// {@macro copilot_translator}
  this;

  @override
  Harness get harness => Harness.copilot;

  /// The file under the hooks root that holds [copilotCompatScript].
  static const compatScript = 'vgv-claude-compat.sh';

  /// Copilot reads every `*.json` under `~/.copilot/hooks/` recursively as
  /// a hooks file, so the script copies live beside that folder.
  @override
  Directory hooksRoot(Directory home) {
    final config = harness.configDirectory(home);
    return config.fileSystem.directory(
      p.join(config.path, 'vgv_ai', HookScripts.hooksFolder),
    );
  }

  /// Copilot documents a `type` on every server.
  @override
  String settings(PluginAssets assets) => jsonEncode({
    'mcpServers': {
      for (final server in assets.mcpServers)
        server.name: {
          'type': switch (server) {
            LocalMCPServer() => 'local',
            RemoteMCPServer() => 'http',
          },
          ...server.toJson(),
        },
    },
  });

  @override
  HarnessFields agent(AgentAsset agent, {required String instructions}) =>
      HarnessFields(
        frontmatter: Frontmatter.render({
          'name': agent.name,
          'description': agent.description,
        }),
      );

  /// The plugins' hooks as `~/.copilot/hooks/vgv.json` spells them, with
  /// Copilot's copy of each plugin's `hooks` folder under [hooksRoot] and
  /// [copilotCompatScript] beside it.
  ///
  /// Under Claude Code's event names, Copilot applies Claude Code's matcher
  /// semantics and tool names, so both carry over. Each command is its own
  /// entry, and a hook an agent declared for itself is left out, since
  /// Copilot's payload names no agent to scope it by.
  ///
  /// See https://docs.github.com/en/copilot/reference/hooks-reference.
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

  /// The `vgv.json` fragment, or null when there is no command to run.
  static String? _fragment(
    List<HookAsset> hooks, {
    required Directory hooksRoot,
  }) {
    final events = <String, List<Object?>>{};
    for (final hook in hooks.where(HookScripts.safelyNamed)) {
      events
          .putIfAbsent(hook.event, () => [])
          .addAll(_entries(hook, hooksRoot: hooksRoot));
    }
    events.removeWhere((_, entries) => entries.isEmpty);
    return events.isEmpty ? null : jsonEncode({'version': 1, 'hooks': events});
  }

  /// One entry per shell command of [hook].
  static List<Object?> _entries(
    HookAsset hook, {
    required Directory hooksRoot,
  }) => [
    for (final command in hook.commands)
      if (command.type == HookScripts.commandType)
        {
          'type': command.type,
          'matcher': ?_matcher(hook),
          'bash': HookScripts.command(command, hook, hooksRoot: hooksRoot),
          'timeoutSec': ?command.timeout,
        },
  ];

  /// One note per hook an agent declared for itself.
  static List<TranslationNote> _scopedNotes(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (hook.agent != null)
        TranslationNote(
          subject: "${hook.agent}'s ${hook.event} hook",
          reason:
              'Copilot names no agent in a tool call, so a hook an agent '
              'declares for itself cannot be scoped to it and is left out',
        ),
  ];

  @override
  HookScripts get scripts =>
      const HookScripts(harness: Harness.copilot, preamble: copilotPreamble);

  /// The prefix and separator of an MCP tool's name in a plugin's matcher,
  /// `mcp__<server>__<tool>`.
  static const _mcpPrefix = 'mcp__';
  static const _mcpSeparator = '__';

  /// The hooks not scoped to an agent.
  static List<HookAsset> _runnable(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (hook.agent == null) hook,
  ];

  /// [hook]'s matcher with each MCP tool respelled as Copilot names it,
  /// `<server>-<tool>`. Read as a top-level alternation, which is how the
  /// plugins write theirs.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? => declared.split('|').map(_copilotTool).join('|'),
    _ => null,
  };

  static String _copilotTool(String alternative) =>
      alternative.startsWith(_mcpPrefix)
      ? alternative.substring(_mcpPrefix.length).replaceAll(_mcpSeparator, '-')
      : alternative;
}
