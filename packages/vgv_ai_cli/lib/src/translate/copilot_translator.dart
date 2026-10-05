import 'dart:convert';

import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template copilot_translator}
/// Configures GitHub Copilot CLI.
///
/// Copilot reads `~/.agents/skills` natively and invokes each skill by name,
/// so it needs no commands. Its agents are markdown with frontmatter, and its
/// MCP servers live in their own `mcp-config.json` rather than in settings.
/// {@endtemplate}
class const CopilotTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.copilot;

  /// Copilot documents a `type` on every server, so one is written rather
  /// than left for it to infer.
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
}
