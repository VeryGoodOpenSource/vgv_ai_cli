import 'dart:io' show Process, ProcessException, ProcessResult;

import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/plugin_source/plugin_ref.dart';
import 'package:vgv_ai_cli/src/plugin_source/resolution.dart';

/// Runs git with [args], optionally from [workingDirectory].
///
/// Injected so tests never reach the network or require a git binary.
typedef RunGit = Future<ProcessResult> Function(
  List<String> args, {
  String? workingDirectory,
});

/// The default [RunGit], which shells out to the real git.
// coverage:ignore-start
// The only process call in this layer. Every test injects a fake, and the
// suite is required to pass with no git binary installed, so this body can
// never execute under test.
Future<ProcessResult> runGitProcess(
  List<String> args, {
  String? workingDirectory,
}) => Process.run(
  'git',
  args,
  workingDirectory: workingDirectory,
  runInShell: true,
);
// coverage:ignore-end

/// {@template plugin_source}
/// Resolves a [PluginRef] to a directory on disk.
/// {@endtemplate}
abstract class PluginSource {
  /// {@macro plugin_source}
  const new();

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
/// {@endtemplate}
class LocalCachePluginSource extends PluginSource {
  /// {@macro local_cache_plugin_source}
  const new({required this.home, this.marketplace = vgvMarketplaceName});

  /// The home directory holding `.claude`.
  final Directory home;

  /// The marketplace's declared name, which names the cache directory.
  final String marketplace;

  @override
  Future<PluginResolution> resolve(PluginRef ref) async {
    final fileSystem = home.fileSystem;
    final pluginRoot = fileSystem.directory(
      p.join(home.path, '.claude', 'plugins', 'cache', marketplace, ref.name),
    );

    if (!pluginRoot.existsSync()) {
      return UnavailablePlugin.single(
        'No Claude Code cache for ${ref.name} at ${pluginRoot.path}',
      );
    }

    final directory = fileSystem.directory(
      p.join(pluginRoot.path, ref.version),
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
      p.join(directory.path, '.claude-plugin', 'plugin.json'),
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
/// {@endtemplate}
class GitPluginSource extends PluginSource {
  /// {@macro git_plugin_source}
  const new({required this.cacheRoot, this.runGit = runGitProcess});

  /// Where clones are kept between runs.
  final Directory cacheRoot;

  /// Runs git. Injected so tests never hit the network.
  final RunGit runGit;

  @override
  Future<PluginResolution> resolve(PluginRef ref) async {
    final fileSystem = cacheRoot.fileSystem;
    final target = fileSystem.directory(
      p.join(cacheRoot.path, ref.name, ref.version),
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

    if (result.exitCode != ExitCode.success.code) {
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

/// {@template chained_plugin_source}
/// Tries each source in order and returns the first that resolves.
/// {@endtemplate}
class ChainedPluginSource extends PluginSource {
  /// {@macro chained_plugin_source}
  const new(this.sources);

  /// The sources to try, in order.
  final List<PluginSource> sources;

  @override
  Future<PluginResolution> resolve(PluginRef ref) async {
    final reasons = <String>[];
    for (final source in sources) {
      final resolution = await source.resolve(ref);
      switch (resolution) {
        case ResolvedPlugin():
          return resolution;
        case UnavailablePlugin(reasons: final sourceReasons):
          reasons.addAll(sourceReasons);
      }
    }
    return UnavailablePlugin(reasons);
  }
}

/// Resolves [ref] through [source], or throws.
///
/// Resolution is all-or-nothing across the pinned plugins: a half-configured
/// harness is worse than an unconfigured one.
Future<Directory> resolvePluginOrThrow(
  PluginRef ref, {
  required PluginSource source,
}) async {
  final resolution = await source.resolve(ref);
  return switch (resolution) {
    ResolvedPlugin(:final directory) => directory,
    UnavailablePlugin(:final reasons) => throw PluginResolutionException(
      ref,
      reasons,
    ),
  };
}
