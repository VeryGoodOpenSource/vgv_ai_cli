import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/model/model.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

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

  /// Everything in [assets] this harness cannot express.
  ///
  /// The plugins' hook scripts read Claude Code's payload, which no other
  /// harness sends, so a hook wired in elsewhere would run and do nothing.
  /// They are left out until the scripts are harness-aware.
  List<TranslationNote> notes(PluginAssets assets) => [
    if (assets.hooks.isNotEmpty)
      TranslationNote(
        subject: '${assets.hooks.length} hook(s)',
        reason:
            'the plugin hook scripts only understand Claude Code, so '
            '${harness.displayName} gets none for now',
      ),
  ];
}
