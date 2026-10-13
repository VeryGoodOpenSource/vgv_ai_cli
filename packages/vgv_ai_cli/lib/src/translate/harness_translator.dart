import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template harness_translator}
/// How one harness spells what the plugins contribute.
///
/// The plugins are written for Claude Code and stay that way: every
/// difference another harness has is answered here, config files and hook
/// payloads alike.
///
/// A translator supplies what the `agents` brick cannot produce itself, and
/// the brick decides which files exist. A feature the harness lacks has no
/// folder in the brick.
///
/// One implementation per harness, and none depends on another translator.
/// See `Harness` for every step of adding a harness.
/// {@endtemplate}
abstract class const HarnessTranslator() {
  /// Which harness this configures.
  Harness get harness;

  /// Whether this harness loads the shared copy of the skills under
  /// `~/.agents/skills`.
  bool get readsSharedSkills => true;

  /// Whether this harness runs the plugins' hooks. Declared, not derived from
  /// [hooks], because [notes] reads it without the paths [hooks] takes.
  bool get runsHooks => false;

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

  /// The hooks fragment merged into this harness's hooks file, or null.
  /// Only called when [runsHooks] is set; [hookFiles] writes under
  /// [hooksRoot].
  String? hooks(PluginAssets assets, {required Directory hooksRoot}) => null;

  /// The files this harness needs beside [hooks], under [hooksRoot]. Planned
  /// rather than rendered so a copied script keeps its mode. Only called when
  /// [runsHooks] is set.
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) => const [];

  /// What the user needs to know about [assets] for this harness.
  ///
  /// A harness whose config cannot run a shell command gets no hooks:
  /// OpenCode's hooks are TypeScript callbacks, not commands in a file.
  List<TranslationNote> notes(PluginAssets assets) => [
    if (!runsHooks && assets.hooks.isNotEmpty)
      TranslationNote(
        subject: '${assets.hooks.length} hook(s)',
        reason:
            'the plugins ship them as shell commands, and nothing in '
            "${harness.displayName}'s config runs one",
      ),
  ];
}
