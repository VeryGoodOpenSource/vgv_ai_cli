import 'dart:convert';

import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template pi_translator}
/// Configures Pi.
///
/// Pi is minimal by design, with no subagents and no declarative hooks. It
/// reads the shared skills and `AGENTS.md` without configuration, so it gets
/// its instructions, its prompts (the skill bodies as written), and the MCP
/// servers in `~/.pi/agent/mcp.json`, which Pi reads from 0.99.0.
/// {@endtemplate}
class const PiTranslator() extends HarnessTranslator {
  /// {@macro pi_translator}
  this;

  @override
  Harness get harness => Harness.pi;

  @override
  String settings(PluginAssets assets) => jsonEncode({
    'mcpServers': {
      for (final server in assets.mcpServers) server.name: server.toJson(),
    },
  });

  @override
  List<TranslationNote> notes(PluginAssets assets) => [
    if (assets.agents.isNotEmpty)
      TranslationNote(
        subject: '${assets.agents.length} agent(s)',
        reason: 'Pi has no subagents, so it gets none',
      ),
  ];

  /// Pi loads a project's skills and prompts only once the project is
  /// trusted.
  @override
  List<TranslationNote> projectNotes(PluginAssets assets) => [
    if (assets.skills.isNotEmpty)
      const TranslationNote(
        subject: "the project's skills and prompts",
        reason: 'Pi loads them only once you trust the project',
      ),
  ];
}
