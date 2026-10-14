import 'dart:io' show ProcessException, ProcessResult;

import 'package:file/file.dart';
import 'package:plugin_source/src/plugin_ref.dart';
import 'package:plugin_source/src/resolution.dart';

/// Runs git with [args].
///
/// Required rather than defaulted to a real `Process.run`. A default would be
/// a line no test can execute, since the suite must pass with no git binary
/// installed, and this repo does not enable coverage-ignore comments. The
/// process wiring belongs with the command that owns the rest of it.
typedef RunGit = Future<ProcessResult> Function(List<String> args);

/// {@template plugin_source}
/// Resolves a [PluginRef] to a directory on disk.
/// {@endtemplate}
abstract class const PluginSource() {
  /// Resolves [ref] from this source.
  Future<PluginResolution> resolve(PluginRef ref);
}

/// {@template local_cache_plugin_source}
/// Resolves plugins from the Claude Code plugin cache.
///
/// Anyone already running Claude Code at the pinned version has the plugin on
/// disk, so this costs nothing and works offline. It is a fast path, not the
/// source of truth: the cache directory is named after the *declared* version
/// and carries no content guarantee.
///
/// [home] is the directory holding `.claude`. [marketplace] is the
/// marketplace's declared name, which names the cache directory.
/// {@endtemplate}
class const LocalCachePluginSource({
  required final Directory home,
  final String marketplace = vgvMarketplaceName,
}) extends PluginSource {
  @override
  Future<PluginResolution> resolve(PluginRef ref) async {
    final fileSystem = home.fileSystem;
    final pluginRoot = fileSystem.directory(
      fileSystem.path.join(
        home.path,
        '.claude',
        'plugins',
        'cache',
        marketplace,
        ref.name,
      ),
    );

    if (!pluginRoot.existsSync()) {
      return UnavailablePlugin.single(
        'No Claude Code cache for ${ref.name} at ${pluginRoot.path}',
      );
    }

    final directory = fileSystem.directory(
      fileSystem.path.join(pluginRoot.path, ref.version),
    );
    if (!directory.existsSync()) {
      return UnavailablePlugin.single(
        'Claude Code has ${ref.name} cached, but not at the pinned version '
        '${ref.version} (looked in ${directory.path})',
      );
    }

    // Claude Code creates the version directory and then clones into it, so a
    // directory can exist while empty or half-written. This is a completeness
    // check, not an integrity one: the git source is what guarantees content.
    //
    // Claude Code also leaves a `.in_use` marker here. It is deliberately not
    // inspected, because it is Claude Code's own state and a populated cache
    // carries it.
    final manifest = fileSystem.file(
      fileSystem.path.join(directory.path, '.claude-plugin', 'plugin.json'),
    );
    if (!manifest.existsSync()) {
      return UnavailablePlugin.single(
        'The cached copy of $ref looks incomplete: no '
        '.claude-plugin/plugin.json in ${directory.path}',
      );
    }

    return ResolvedPlugin(directory);
  }
}

/// {@template git_plugin_source}
/// Resolves plugins by cloning them at their pinned tag.
///
/// [cacheRoot] is where clones are kept between runs. [runGit] runs git, and is
/// required so tests never hit the network.
/// {@endtemplate}
class const GitPluginSource({
  required final Directory cacheRoot,
  required final RunGit runGit,
}) extends PluginSource {
  @override
  Future<PluginResolution> resolve(PluginRef ref) async {
    final fileSystem = cacheRoot.fileSystem;
    final target = fileSystem.directory(
      fileSystem.path.join(cacheRoot.path, ref.name, ref.version),
    );
    if (target.existsSync()) return ResolvedPlugin(target);

    // Clone into a sibling temp path and publish by rename, so the version
    // directory only ever exists complete. This defeats both the interrupted
    // clone that would otherwise be reused forever and the race where two
    // concurrent installs clone to the same path.
    final temp = fileSystem.directory(
      '${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );

    try {
      target.parent.createSync(recursive: true);
    } on FileSystemException catch (error) {
      return UnavailablePlugin.single(
        'Could not create ${target.parent.path}: ${error.message}. '
        'That directory must be writable.',
      );
    }

    final ProcessResult result;
    try {
      result = await runGit([
        'clone',
        '--depth',
        '1',
        '--branch',
        ref.gitRef,
        'https://github.com/${ref.repo}.git',
        temp.path,
      ]);
    } on ProcessException {
      // Process.run throws rather than returning a non-zero exit code when the
      // executable is missing, so this is specifically "no git", not "the
      // clone failed".
      return UnavailablePlugin.single(
        'git is not installed or not on your PATH. Install git, or run Claude '
        'Code once so it populates its plugin cache.',
      );
    }

    if (result.exitCode != 0) {
      _deleteTemp(temp);
      return UnavailablePlugin.single(
        'Could not clone ${ref.repo} at ${ref.gitRef}: ${result.stderr}',
      );
    }

    try {
      temp.renameSync(target.path);
    } on FileSystemException catch (error) {
      _deleteTemp(temp);
      // Almost always means a concurrent run published first. Never delete the
      // target: that tree is good, and it may be in use.
      if (target.existsSync()) return ResolvedPlugin(target);
      return UnavailablePlugin.single(
        'Could not move the clone of $ref into ${target.path}: '
        '${error.message}',
      );
    }

    return ResolvedPlugin(target);
  }

  void _deleteTemp(Directory temp) {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}
