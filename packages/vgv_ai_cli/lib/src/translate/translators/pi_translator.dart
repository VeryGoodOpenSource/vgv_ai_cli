import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// {@template pi_translator}
/// Configures Pi.
///
/// Pi is minimal by design, with no subagents, no MCP and no declarative
/// hooks. It reads the shared skills and `AGENTS.md` without configuration,
/// so it gets its instructions and its prompts, which are the skill bodies as
/// written, and nothing that would imitate the rest.
/// {@endtemplate}
class const PiTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.pi;

  @override
  List<TranslationNote> notes(PluginAssets assets) => [
    if (assets.agents.isNotEmpty)
      TranslationNote(
        subject: '${assets.agents.length} agent(s)',
        reason: 'Pi has no subagents, so it gets none',
      ),
    if (assets.mcpServers.isNotEmpty)
      TranslationNote(
        subject: '${assets.mcpServers.length} MCP server(s)',
        reason: 'Pi has no MCP support, so it gets none',
      ),
  ];
}
