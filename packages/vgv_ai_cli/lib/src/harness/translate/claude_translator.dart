import 'dart:convert';

import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

/// {@template claude_translator}
/// Configures Claude Code, which needs no assets translated.
///
/// Claude Code is the one harness that installs the plugins natively, so this
/// points it at the marketplace and enables the plugins there. Copying the
/// skills and agents as well would duplicate what the plugin system already
/// does, and the two copies would drift apart on the next plugin release.
/// {@endtemplate}
class const ClaudeTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.claude;

  /// The plugin system already installs the skills.
  @override
  bool get readsSharedSkills => false;

  @override
  String settings(PluginAssets assets) => jsonEncode({
    'extraKnownMarketplaces': {
      vgvMarketplaceName: {
        'source': {'source': 'github', 'repo': vgvMarketplaceRepo},
      },
    },
    'enabledPlugins': {
      for (final plugin in vgvPlugins)
        '${plugin.name}@$vgvMarketplaceName': true,
    },
  });

  /// Nothing: the plugins run here exactly as their authors wrote them,
  /// hooks included.
  @override
  List<TranslationNote> notes(PluginAssets assets) => const [];
}
