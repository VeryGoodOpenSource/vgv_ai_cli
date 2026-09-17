import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/plugin_source/plugin_ref.dart';

/// Thrown when a plugin cannot be resolved from any source.
class PluginResolutionException implements Exception {
  /// Creates a [PluginResolutionException].
  const new(this.ref, this.reason);

  /// The plugin that could not be resolved.
  final PluginRef ref;

  /// Why resolution failed.
  final String reason;

  @override
  String toString() => 'Could not resolve $ref: $reason';
}

/// {@template plugin_source}
/// Resolves a [PluginRef] to a directory on disk.
/// {@endtemplate}
abstract class PluginSource {
  /// {@macro plugin_source}
  const new();

  /// Resolves [ref], or returns `null` when this source cannot supply it.
  Future<Directory?> resolve(PluginRef ref, {required Logger logger});
}

/// Resolves plugins from the Claude Code plugin cache.
///
/// Anyone already running Claude Code has the plugins on disk at the pinned
/// version, so this costs nothing and works offline.
class LocalCachePluginSource extends PluginSource {
  /// Creates a [LocalCachePluginSource] rooted at [home].
  const new({required this.home, this.marketplace = vgvMarketplaceName});

  /// The home directory holding `.claude`.
  final Directory home;

  /// The marketplace's declared name, which names the cache directory.
  final String marketplace;

  @override
  Future<Directory?> resolve(PluginRef ref, {required Logger logger}) async {
    final directory = Directory(
      p.join(
        home.path,
        '.claude',
        'plugins',
        'cache',
        marketplace,
        ref.name,
        ref.version,
      ),
    );
    if (!directory.existsSync()) {
      logger.detail('No cached copy of $ref at ${directory.path}');
      return null;
    }
    logger.detail('Resolved $ref from the Claude Code cache');
    return directory;
  }
}

/// Resolves plugins by cloning them at their pinned version.
class GitPluginSource extends PluginSource {
  /// Creates a [GitPluginSource] caching clones under [cacheRoot].
  const new({required this.cacheRoot, this.runGit = _runGit});

  /// Where clones are kept between runs.
  final Directory cacheRoot;

  /// Runs git. Injected so tests never hit the network.
  final Future<ProcessResult> Function(List<String> args, {String? cwd}) runGit;

  static Future<ProcessResult> _runGit(List<String> args, {String? cwd}) =>
      Process.run('git', args, workingDirectory: cwd, runInShell: true);

  @override
  Future<Directory?> resolve(PluginRef ref, {required Logger logger}) async {
    final target = Directory(p.join(cacheRoot.path, ref.name, ref.version));
    if (target.existsSync()) {
      logger.detail('Reusing clone of $ref at ${target.path}');
      return target;
    }

    target.parent.createSync(recursive: true);
    logger.detail('Cloning $ref from ${ref.repo}');
    final result = await runGit([
      'clone',
      '--depth',
      '1',
      '--branch',
      ref.version,
      'https://github.com/${ref.repo}.git',
      target.path,
    ]);

    if (result.exitCode != ExitCode.success.code) {
      if (target.existsSync()) target.deleteSync(recursive: true);
      logger.detail('Clone of $ref failed: ${result.stderr}');
      return null;
    }
    return target;
  }
}

/// Tries each source in order and returns the first that resolves.
class ChainedPluginSource extends PluginSource {
  /// Creates a [ChainedPluginSource] over [sources].
  const new(this.sources);

  /// The sources to try, in order.
  final List<PluginSource> sources;

  @override
  Future<Directory?> resolve(PluginRef ref, {required Logger logger}) async {
    for (final source in sources) {
      final resolved = await source.resolve(ref, logger: logger);
      if (resolved != null) return resolved;
    }
    return null;
  }
}
