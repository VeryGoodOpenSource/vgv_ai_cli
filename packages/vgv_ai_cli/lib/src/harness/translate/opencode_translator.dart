import 'dart:convert';

import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

/// {@template opencode_translator}
/// Configures OpenCode.
///
/// Agents and commands are both markdown with frontmatter. An agent is marked
/// `mode: subagent` so it is delegated to rather than driven directly.
/// {@endtemplate}
class const OpenCodeTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.opencode;

  /// OpenCode types every server and folds a command's args into one array.
  @override
  String settings(PluginAssets assets, {required String skillsRoot}) =>
      jsonEncode({
        r'$schema': 'https://opencode.ai/config.json',
        'mcp': {
          for (final server in assets.mcpServers)
            server.name: switch (server) {
              LocalMCPServer(:final command, :final args, :final env) => {
                'type': 'local',
                'command': [command, ...args],
                if (env.isNotEmpty) 'environment': env,
              },
              RemoteMCPServer(:final url) => {'type': 'remote', 'url': url},
            },
        },
        'instructions': ['AGENTS.md'],
      });

  @override
  Map<String, Object?> agent(
    AgentAsset agent, {
    required String instructions,
  }) => {
    'frontmatter': Frontmatter.render({
      'description': agent.description,
      'mode': 'subagent',
    }),
  };

  @override
  Map<String, Object?> command(SkillAsset skill) => {
    'frontmatter': Frontmatter.render({'description': skill.description}),
  };
}
