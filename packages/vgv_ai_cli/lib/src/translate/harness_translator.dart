import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template harness_translator}
/// How one harness spells what the plugins contribute.
///
/// A translator changes spelling, never semantics. It supplies what the
/// `agents` brick cannot produce itself, the settings fragment and any
/// frontmatter or TOML, and the brick decides which files exist. A feature the
/// harness lacks has no folder in the brick, so there is nothing here to
/// imitate it with.
///
/// One implementation per harness, and none depends on another translator.
/// See `Harness` for every step of adding a harness.
/// {@endtemplate}
abstract class HarnessTranslator {
  /// {@macro harness_translator}
  const new();

  /// Which harness this configures.
  Harness get harness;

  /// Whether this harness loads the shared copy of the skills under
  /// `~/.agents/skills`.
  bool get readsSharedSkills => true;

  /// The settings fragment merged into the root of this harness's config,
  /// or null for a harness with nothing to set, whose brick folder then has
  /// no settings file.
  String? settings(PluginAssets assets) => null;

  /// What the brick renders [agent] with for this harness, under its name.
  ///
  /// [instructions] is the agent body every harness shares.
  HarnessFields agent(AgentAsset agent, {required String instructions}) =>
      const HarnessFields();

  /// What the brick renders [skill] as a command with, under its name.
  HarnessFields command(SkillAsset skill) => const HarnessFields();

  /// The hooks fragment merged into this harness's own hooks file, or null
  /// for a harness that runs none of them, whose brick folder then has no
  /// hooks file.
  ///
  /// [hooksRoot] is where the brick writes this harness's hook helper
  /// scripts, for a translator whose commands have to name one.
  String? hooks(PluginAssets assets, {required String hooksRoot}) => null;

  /// What the user needs to know about [assets] for this harness: what it
  /// cannot express, and what it will not do until they act.
  ///
  /// A hook is a shell command the harness runs at a lifecycle point, so a
  /// harness with no hooks system of its own has nowhere to put one.
  List<TranslationNote> notes(PluginAssets assets) => [
    if (assets.hooks.isNotEmpty)
      TranslationNote(
        subject: '${assets.hooks.length} hook(s)',
        reason: '${harness.displayName} has no hooks system to run them from',
      ),
  ];
}
