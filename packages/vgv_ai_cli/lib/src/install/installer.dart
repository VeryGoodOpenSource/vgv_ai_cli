import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/generation/generation.dart';
import 'package:vgv_ai_cli/src/materialize/materialize.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_resolver.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';

/// {@template installer}
/// Orchestrates a full `install`: resolve plugins, render the brick to staging,
/// materialize skills, and reconcile staging into the user's real config.
///
/// The filesystem roots ([home] for config, plus the skills root) are injected
/// so tests can point the whole pipeline at a temp directory.
/// {@endtemplate}
class Installer {
  /// {@macro installer}
  const new({
    required this.resolver,
    required this.home,
    this.renderer = const StagingRenderer(),
    this.materializer = const SkillMaterializer(),
    this.jsonReconciler = const JsonReconciler(),
    this.tomlReconciler = const TomlReconciler(),
    this.overwriteReconciler = const OverwriteReconciler(),
  });

  /// Resolves the marketplace plugins into brick inputs.
  final PluginResolver resolver;

  /// The home directory `~`-prefixed config paths resolve against.
  final Directory home;

  /// Renders the bundled brick into a staging directory.
  final StagingRenderer renderer;

  /// Copies resolved skills into the skills root and writes the lockfile.
  final SkillMaterializer materializer;

  /// Merges JSON config files.
  final JsonReconciler jsonReconciler;

  /// Merges Codex's TOML config.
  final TomlReconciler tomlReconciler;

  /// Overwrites fully managed files (the per-harness `AGENTS.md`).
  final OverwriteReconciler overwriteReconciler;

  /// Installs [harnesses], materializing skills under [skillsRoot].
  ///
  /// When [update] is false, previously locked commits are reused so the
  /// install is reproducible; when true, plugins are re-resolved at their
  /// default branch head.
  Future<void> install({
    required HarnessSelection harnesses,
    required String skillsRoot,
    bool update = false,
  }) async {
    final skillsRootDirectory = Directory(_expandHome(skillsRoot));

    final pins = update
        ? const <String, String>{}
        : _readPins(skillsRootDirectory);
    final resolved = await resolver.resolve(pins: pins);

    final staging = Directory.systemTemp.createTempSync('vgv_ai_staging_');
    try {
      await renderer.render(
        vars: buildAgentsVars(
          plugins: resolved,
          harnesses: harnesses,
          skillsRoot: skillsRoot,
        ),
        target: staging,
      );

      await materializer.materialize(
        plugins: resolved,
        destination: skillsRootDirectory,
        skillsRoot: skillsRoot,
      );

      await _reconcile(staging);
    } finally {
      staging.deleteSync(recursive: true);
    }
  }

  Future<void> _reconcile(Directory staging) async {
    for (final MapEntry(key: stagingPath, value: mapping)
        in _destinations().entries) {
      final staged = File(p.join(staging.path, stagingPath));
      if (!staged.existsSync()) continue;
      await mapping.reconciler.reconcile(
        staged: staged,
        destination: mapping.destination,
      );
    }
  }

  /// Maps each staged file onto its real destination and reconciler.
  Map<String, ({File destination, Reconciler reconciler})> _destinations() {
    File config(List<String> segments) =>
        File(p.joinAll([home.path, ...segments]));

    return {
      p.join('claude', 'settings.json'): (
        destination: config(['.claude', 'settings.json']),
        reconciler: jsonReconciler,
      ),
      p.join('gemini', 'settings.json'): (
        destination: config(['.gemini', 'settings.json']),
        reconciler: jsonReconciler,
      ),
      p.join('gemini', 'AGENTS.md'): (
        destination: config(['.gemini', 'AGENTS.md']),
        reconciler: overwriteReconciler,
      ),
      p.join('codex', 'config.toml'): (
        destination: config(['.codex', 'config.toml']),
        reconciler: tomlReconciler,
      ),
      p.join('codex', 'AGENTS.md'): (
        destination: config(['.codex', 'AGENTS.md']),
        reconciler: overwriteReconciler,
      ),
      p.join('opencode', 'opencode.json'): (
        destination: config(['.config', 'opencode', 'opencode.json']),
        reconciler: jsonReconciler,
      ),
      p.join('opencode', 'AGENTS.md'): (
        destination: config(['.config', 'opencode', 'AGENTS.md']),
        reconciler: overwriteReconciler,
      ),
      p.join('pi', 'settings.json'): (
        destination: config(['.pi', 'agent', 'settings.json']),
        reconciler: jsonReconciler,
      ),
    };
  }

  Map<String, String> _readPins(Directory skillsRootDirectory) {
    final lock = File(p.join(skillsRootDirectory.path, 'skills-lock.json'));
    if (!lock.existsSync()) return const {};
    return SkillsLock.pinsFromJson(lock.readAsStringSync());
  }

  String _expandHome(String path) {
    if (path == '~') return home.path;
    if (path.startsWith('~/') || path.startsWith(r'~\')) {
      return p.join(home.path, path.substring(2));
    }
    return path;
  }
}
