import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/antigravity_compat.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/hook_scripts.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template antigravity_translator}
/// Configures Antigravity CLI.
///
/// Everything goes into one Antigravity plugin, `plugins/vgv/` under the
/// config it shares with the Antigravity IDE, which is how Antigravity
/// bundles skills, agents, MCP servers and hooks. It reads neither
/// `~/.agents/skills` nor a commands folder: the skills are copied into the
/// plugin and each becomes a `/<name>` command on its own. The skills and
/// agents register natively, so no rule indexes them.
///
/// See https://antigravity.google/docs/plugins/.
/// {@endtemplate}
class const AntigravityTranslator() extends HarnessTranslator {
  /// The plugin everything is installed as.
  static const plugin = 'vgv';

  /// The file under the hooks root that holds [antigravityCompatScript].
  static const compatScript = 'vgv-claude-compat.sh';

  @override
  Harness get harness => Harness.antigravity;

  @override
  bool get readsSharedSkills => false;

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

  /// The plugins' hooks as the plugin's `hooks.json` spells them: one set
  /// per source plugin, under the event names Antigravity shares with Claude
  /// Code, with matchers respelled to its tool names, a timeout in seconds,
  /// and the event in `VGV_HOOK_EVENT` on each command, since the payload
  /// does not name it. A tool event lists registrations of a matcher and
  /// its handlers; any other event lists the handlers themselves. The
  /// scripts are copied under [hooksRoot] with [antigravityCompatScript]
  /// beside them.
  ///
  /// A hook an agent declared for itself, and one on an event Antigravity
  /// lacks, are left out. After a tool Antigravity reads nothing a hook
  /// says, so those hooks run but the agent hears none of it.
  ///
  /// See https://antigravity.google/docs/hooks/.
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
            contents: antigravityCompatScript,
            harness: harness,
          ),
        ...copy.files,
      ],
      notes: [
        ...copy.notes,
        for (final hook in assets.hooks) ?_leftOut(hook),
        if (runnable.any((hook) => hook.event == 'PostToolUse'))
          const TranslationNote(
            subject: 'the PostToolUse hooks',
            reason:
                'Antigravity reads nothing a hook says after a tool, so they '
                'run but the agent hears none of it',
          ),
        ..._handlerNotes(runnable),
      ],
    );
  }

  /// The `hooks.json` fragment, or null when there is no command to run.
  static String? _fragment(
    List<HookAsset> hooks, {
    required Directory hooksRoot,
  }) {
    final commands = hooks
        .where(HookScripts.safelyNamed)
        .where(HookScripts.runsCommand)
        .toList();
    if (commands.isEmpty) return null;
    return jsonEncode({
      for (final MapEntry(key: source, value: ofPlugin)
          in commands.groupListsBy((h) => h.plugin).entries)
        source: {
          for (final MapEntry(key: event, value: registrations)
              in ofPlugin.groupListsBy((h) => h.event).entries)
            event: _entries(event, registrations, hooksRoot: hooksRoot),
        },
    });
  }

  /// What [event] lists: a registration per hook for a tool event, the
  /// handlers themselves for any other.
  static List<Map<String, Object?>> _entries(
    String event,
    List<HookAsset> hooks, {
    required Directory hooksRoot,
  }) => [
    for (final hook in hooks)
      if (_toolEvents.contains(event))
        _registration(hook, hooksRoot: hooksRoot)
      else
        ..._handlers(hook, hooksRoot: hooksRoot),
  ];

  /// [hook]'s matcher and its handlers, as a tool event lists them.
  static Map<String, Object?> _registration(
    HookAsset hook, {
    required Directory hooksRoot,
  }) => {
    'matcher': ?_matcher(hook),
    'hooks': _handlers(hook, hooksRoot: hooksRoot),
  };

  /// One handler per shell command of [hook].
  static List<Map<String, Object?>> _handlers(
    HookAsset hook, {
    required Directory hooksRoot,
  }) => [
    for (final command in hook.commands)
      if (command.type == HookScripts.commandType)
        {
          'type': command.type,
          'command':
              'VGV_HOOK_EVENT=${hook.event} '
              '${HookScripts.command(command, hook, hooksRoot: hooksRoot)}',
          'timeout': ?command.timeout,
        },
  ];

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
          reason: 'Antigravity runs a shell command only, so they are left out',
        ),
    ];
  }

  @override
  HookScripts get scripts => const HookScripts(
    harness: Harness.antigravity,
    preamble: antigravityPreamble,
  );

  /// The Claude Code events Antigravity has under the same name.
  static const _events = {'PreToolUse', 'PostToolUse', 'SessionStart', 'Stop'};

  /// The events whose registrations carry a matcher.
  static const _toolEvents = {'PreToolUse', 'PostToolUse'};

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

  /// How Claude Code spells an MCP tool in a matcher. Antigravity calls
  /// every MCP tool through one tool, [_mcpTool], naming the server and the
  /// tool in its arguments, which the compat script hands the script.
  static const _mcpPrefix = 'mcp__';
  static const _mcpTool = 'call_mcp_tool';

  /// The hooks Antigravity can run.
  static List<HookAsset> _runnable(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (_leftOut(hook) == null) hook,
  ];

  /// [hook]'s matcher with each alternative respelled to Antigravity's tool
  /// name, written once, or null when it declares none.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? => {
      for (final alternative in declared.split('|'))
        _antigravityTool(alternative),
    }.join('|'),
    _ => null,
  };

  /// [alternative] as Antigravity names the tool it matches: every MCP tool
  /// is [_mcpTool], and the script tells them apart by server.
  static String _antigravityTool(String alternative) =>
      _tools[alternative] ??
      (alternative.startsWith(_mcpPrefix) ? _mcpTool : alternative);
}
