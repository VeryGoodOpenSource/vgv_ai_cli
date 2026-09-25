import 'dart:convert';

import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

/// {@template pi_translator}
/// Configures Pi.
///
/// Pi is minimal by design, with no subagents, no MCP and no declarative
/// hooks. It gets its settings and its prompts, which are the skill bodies as
/// written, and nothing that would imitate the rest.
/// {@endtemplate}
class const PiTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.pi;

  @override
  String settings(PluginAssets assets, {required String skillsRoot}) =>
      jsonEncode({
        'skills': [skillsRoot],
      });
}
