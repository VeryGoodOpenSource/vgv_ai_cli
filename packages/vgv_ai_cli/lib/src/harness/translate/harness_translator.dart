import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
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
/// One implementation per harness, so a new harness is one new class and one
/// new brick folder. None depends on another translator.
/// {@endtemplate}
abstract class HarnessTranslator {
  /// {@macro harness_translator}
  const new();

  /// Which harness this configures.
  Harness get harness;

  /// The settings fragment merged into the root of this harness's config.
  String settings(PluginAssets assets, {required String skillsRoot});

  /// What the brick renders [agent] with for this harness, under its name.
  ///
  /// [instructions] is the agent body every harness shares.
  Map<String, Object?> agent(
    AgentAsset agent, {
    required String instructions,
  }) => const {};

  /// What the brick renders [skill] as a command with, under its name.
  Map<String, Object?> command(SkillAsset skill) => const {};

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
