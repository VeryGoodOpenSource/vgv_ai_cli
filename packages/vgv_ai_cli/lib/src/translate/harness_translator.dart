import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/format/format.dart';
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

  /// Where this harness keeps its copy of the plugins' hook scripts, which
  /// [hooks] points at and writes to.
  Directory hooksRoot(Directory home) => harnessHooksRoot(harness, home: home);

  /// The plugins' hooks as this harness runs them, with the files beside
  /// the fragment under [hooksRoot], or null for a harness whose config
  /// cannot run a shell command: OpenCode's hooks are TypeScript callbacks,
  /// not commands in a file.
  HookTranslation? hooks(PluginAssets assets, {required Directory hooksRoot}) =>
      null;

  /// What the user needs to know about [assets] for this harness, beyond
  /// what [hooks] reports.
  List<TranslationNote> notes(PluginAssets assets) => const [];
}
