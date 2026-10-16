import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/agents_brick.dart';
import 'package:vgv_ai_cli/src/translate/agents_vars.dart';
import 'package:vgv_ai_cli/src/translate/format/format.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';
import 'package:vgv_ai_cli/src/translate/rendered_change.dart';
import 'package:vgv_ai_cli/src/translate/translators/translators.dart';

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
    final hooks = {
      for (final translator in chosen)
        translator.harness: translator.hooks(
          assets,
          hooksRoot: translator.hooksRoot(home),
        ),
    };
    final vars = AgentsVars(
      translators: chosen,
      assets: assets,
      skillsRoot: agentsSkillsRoot(home).path,
      hooks: {
        for (final MapEntry(key: harness, value: translation) in hooks.entries)
          harness: ?translation?.fragment,
      },
    );
    final rendered = await brick.render(vars.toMap());
    final changes = [
      for (final MapEntry(key: path, value: contents) in rendered.entries)
        renderedChange(path, contents: contents, home: home),
    ].groupListsBy((change) => change.harness);

    return TranslationPlan(
      shared: chosen.any((translator) => translator.readsSharedSkills)
          ? skills.translate(assets: assets, root: agentsSkillsRoot(home))
          : null,
      harnesses: {
        for (final translator in chosen)
          translator.harness: _result(
            translator,
            rendered: changes[translator.harness],
            hooks: hooks[translator.harness],
            assets: assets,
            home: home,
          ),
      },
    );
  }

  /// [translator]'s [rendered] files, the ones beside its [hooks], and its
  /// own copy of the skills when it keeps one, with its notes. A harness
  /// that runs no hooks is told so here, since every translator would
  /// otherwise say it the same way.
  TranslationResult _result(
    HarnessTranslator translator, {
    required List<PlannedChange>? rendered,
    required HookTranslation? hooks,
    required PluginAssets assets,
    required Directory home,
  }) {
    final own = switch (translator.skillsRoot(home)) {
      final root? => skills.translate(
        assets: assets,
        root: root,
        harness: translator.harness,
      ),
      _ => null,
    };
    return TranslationResult(
      changes: [...?rendered, ...?hooks?.files, ...?own?.changes],
      notes: [
        ...translator.notes(assets),
        ...?hooks?.notes,
        ...?own?.notes,
        if (hooks == null && assets.hooks.isNotEmpty)
          TranslationNote(
            subject: '${assets.hooks.length} hook(s)',
            reason:
                'the plugins ship them as shell commands, and nothing in '
                "${translator.harness.displayName}'s config runs one",
          ),
      ],
    );
  }
}
