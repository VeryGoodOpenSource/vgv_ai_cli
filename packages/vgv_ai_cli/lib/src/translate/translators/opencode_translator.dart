import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template opencode_translator}
/// Configures OpenCode.
///
/// Agents and commands are both markdown with frontmatter. An agent is marked
/// `mode: subagent` so it is delegated to rather than driven directly.
/// {@endtemplate}
class const OpenCodeTranslator() extends HarnessTranslator {
  /// {@macro opencode_translator}
  this;

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

  /// OpenCode documents the plural folders, and also loads the singular
  /// ones earlier versions wrote.
  @override
  Map<String, String> formerFolders(Directory home) {
    final root = harness.configDirectory(home).path;
    return {
      p.join(root, 'agents'): p.join(root, 'agent'),
      p.join(root, 'commands'): p.join(root, 'command'),
    };
  }
}
