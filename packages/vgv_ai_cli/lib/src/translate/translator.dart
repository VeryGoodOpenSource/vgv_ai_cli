import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/agents_brick.dart';
import 'package:vgv_ai_cli/src/translate/agents_vars.dart';
import 'package:vgv_ai_cli/src/translate/claude_translator.dart';
import 'package:vgv_ai_cli/src/translate/codex_translator.dart';
import 'package:vgv_ai_cli/src/translate/format/format.dart';
import 'package:vgv_ai_cli/src/translate/gemini_translator.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';
import 'package:vgv_ai_cli/src/translate/opencode_translator.dart';
import 'package:vgv_ai_cli/src/translate/pi_translator.dart';
import 'package:vgv_ai_cli/src/translate/rendered_change.dart';
import 'package:vgv_ai_cli/src/translate/skills_translator.dart';

/// Every harness translator, in reporting order.
const harnessTranslators = <HarnessTranslator>[
  ClaudeTranslator(),
  GeminiTranslator(),
  CodexTranslator(),
  OpenCodeTranslator(),
  PiTranslator(),
];

/// {@template translator}
/// Plans every change that installs the plugins into the selected harnesses.
/// {@endtemplate}
class const Translator({
  final List<HarnessTranslator> translators = harnessTranslators,
  final AgentsBrick brick = const AgentsBrick(),
  final SkillsTranslator skills = const SkillsTranslator(),
}) {
  /// The changes and notes for each of [selected], plus the shared skills
  /// when any of them reads them.
  Future<TranslationPlan> translate({
    required PluginAssets assets,
    required Directory home,
    required Set<Harness> selected,
  }) async {
    final chosen = [
      for (final translator in translators)
        if (selected.contains(translator.harness)) translator,
    ];
    final vars = AgentsVars(translators: chosen, assets: assets, home: home);
    final rendered = await brick.render(vars.toMap());
    final changes = [
      for (final MapEntry(key: path, value: contents) in rendered.entries)
        renderedChange(path, contents: contents, home: home),
    ].groupListsBy((change) => change.harness);

    return TranslationPlan(
      shared: chosen.any((translator) => translator.readsSharedSkills)
          ? skills.translate(assets: assets, home: home)
          : null,
      harnesses: {
        for (final translator in chosen)
          translator.harness: TranslationResult(
            changes: [
              ...?changes[translator.harness],
              ...translator.hookFiles(
                assets,
                hooksRoot: harnessHooksRoot(
                  translator.harness.configDirectory(home),
                ),
              ),
            ],
            notes: translator.notes(assets),
          ),
      },
    );
  }
}
