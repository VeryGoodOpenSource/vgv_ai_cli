import 'dart:convert';

import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/model/model.dart';
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
  String settings(PluginAssets assets) => jsonEncode({
    r'$schema': 'https://opencode.ai/config.json',
    'mcp': {
      for (final server in assets.mcpServers)
        server.name: switch (server) {
          LocalMCPServer(:final command, :final args, :final env) => {
            'type': 'local',
            'command': [command, ...args],
            if (env.isNotEmpty) 'environment': env,
          },
          RemoteMCPServer(:final url, :final headers) => {
            'type': 'remote',
            'url': url,
            if (headers.isNotEmpty) 'headers': headers,
          },
        },
    },
    'instructions': ['AGENTS.md'],
  });

  @override
  HarnessFields agent(AgentAsset agent, {required String instructions}) =>
      HarnessFields(
        frontmatter: Frontmatter.render({
          'description': agent.description,
          'mode': 'subagent',
        }),
      );

  @override
  HarnessFields command(SkillAsset skill) => HarnessFields(
    frontmatter: Frontmatter.render({'description': skill.description}),
  );
}
