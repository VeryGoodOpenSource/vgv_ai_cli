import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template harness_translator}
/// How one harness spells what the plugins contribute.
///
/// The plugins are written for Claude Code and stay that way. Every
/// difference another harness has is answered here and never there, so a
/// plugin never carries a branch for a harness it was not written for. That
/// holds for what a hook script is handed at run time as much as for the
/// config files, which is why a translator rewrites the command a harness
/// runs rather than ask the plugins to understand a second payload.
///
/// A translator supplies what the `agents` brick cannot produce itself, the
/// settings fragment and any frontmatter or TOML, and the brick decides which
/// files exist. A feature the harness lacks has no folder in the brick, so
/// there is nothing here to imitate it with.
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

  /// Whether this harness runs the plugins' hooks.
  ///
  /// Declared rather than read off [hooks], because [notes] has to say why a
  /// harness gets none and cannot call [hooks] without the paths it takes.
  /// Overriding one without the other would write a harness its hooks and
  /// tell it in the same breath that it has none, so both are read from here.
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

  /// The hooks fragment merged into this harness's own hooks file, or null
  /// when there is nothing it can run, whose brick folder then has no hooks
  /// file.
  ///
  /// Only called when [runsHooks] is set.
  String? hooks(PluginAssets assets) => null;

  /// What the user needs to know about [assets] for this harness: what it
  /// cannot express, and what it will not do until they act.
  ///
  /// The plugins declare a hook as a shell command to run at a lifecycle
  /// point. A harness that cannot be configured to run one gets none, which
  /// is about its config rather than whether it has hooks at all: OpenCode
  /// has lifecycle hooks, but they are TypeScript callbacks a plugin
  /// registers, not a command named in a file.
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
