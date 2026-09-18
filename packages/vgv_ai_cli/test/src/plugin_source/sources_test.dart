import 'dart:io' show ProcessException, ProcessResult;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_ref.dart';
import 'package:vgv_ai_cli/src/plugin_source/resolution.dart';
import 'package:vgv_ai_cli/src/plugin_source/sources.dart';

const _ref = PluginRef(
  name: 'vgv-wingspan',
  repo: 'VeryGoodOpenSource/vgv-wingspan',
  version: '0.0.5',
  gitRef: 'v0.0.5',
);

/// Builds a cache entry, optionally omitting the manifest that marks it
/// complete.
Directory _seedCache(
  FileSystem fileSystem, {
  required String version,
  bool withManifest = true,
}) {
  final directory = fileSystem.directory(
    p.join(
      '/home/dev',
      '.claude',
      'plugins',
      'cache',
      vgvMarketplaceName,
      _ref.name,
      version,
    ),
  )..createSync(recursive: true);
  if (withManifest) {
    fileSystem.file(p.join(directory.path, '.claude-plugin', 'plugin.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"name":"vgv-wingspan"}');
  }
  return directory;
}

ProcessResult _ok() => ProcessResult(0, ExitCode.success.code, '', '');

void main() {
  late MemoryFileSystem fileSystem;
  late Directory home;

  setUp(() {
    fileSystem = MemoryFileSystem();
    home = fileSystem.directory('/home/dev')..createSync(recursive: true);
  });

  group('LocalCachePluginSource', () {
    test('resolves a complete cache entry at the pinned version', () async {
      final cached = _seedCache(fileSystem, version: '0.0.5');

      final resolution = await LocalCachePluginSource(home: home).resolve(_ref);

      expect(resolution, isA<ResolvedPlugin>());
      expect((resolution as ResolvedPlugin).directory.path, cached.path);
    });

    test('reports a miss when the plugin is not cached at all', () async {
      final resolution = await LocalCachePluginSource(home: home).resolve(_ref);

      expect(
        (resolution as UnavailablePlugin).reasons.single,
        contains('No Claude Code cache'),
      );
    });

    test('does not resolve a different cached version', () async {
      // The live cache really does drift from the pin this way.
      _seedCache(fileSystem, version: '0.0.4');

      final resolution = await LocalCachePluginSource(home: home).resolve(_ref);

      final reason = (resolution as UnavailablePlugin).reasons.single;
      expect(reason, contains('not at the pinned version'));
      expect(reason, contains('0.0.5'));
    });

    test('does not resolve an entry with no plugin.json', () async {
      // Claude Code creates the version directory and then clones into it, so
      // this window is real.
      _seedCache(fileSystem, version: '0.0.5', withManifest: false);

      final resolution = await LocalCachePluginSource(home: home).resolve(_ref);

      expect(
        (resolution as UnavailablePlugin).reasons.single,
        contains('looks incomplete'),
      );
    });

    test('ignores a .in_use marker', () async {
      _seedCache(fileSystem, version: '0.0.5');
      fileSystem
          .file(
            p.join(
              home.path,
              '.claude',
              'plugins',
              'cache',
              vgvMarketplaceName,
              _ref.name,
              '0.0.5',
              '.in_use',
            ),
          )
          .createSync();

      final resolution = await LocalCachePluginSource(home: home).resolve(_ref);

      expect(resolution, isA<ResolvedPlugin>());
    });
  });

  group('GitPluginSource', () {
    late Directory cacheRoot;

    setUp(() {
      cacheRoot = fileSystem.directory('/home/dev/.vgv_ai/plugins')
        ..createSync(recursive: true);
    });

    test('clones the v-prefixed gitRef, not the cache version', () async {
      late List<String> args;

      final resolution = await GitPluginSource(
        cacheRoot: cacheRoot,
        runGit: (a) async {
          args = a;
          fileSystem.directory(a.last).createSync(recursive: true);
          return _ok();
        },
      ).resolve(_ref);

      expect(resolution, isA<ResolvedPlugin>());
      expect(args, containsAllInOrder(['--branch', 'v0.0.5']));
      expect(args, isNot(contains('0.0.5')));
    });

    test('publishes the version directory only after git succeeds', () async {
      final target = fileSystem.directory(
        p.join(cacheRoot.path, _ref.name, '0.0.5'),
      );

      await GitPluginSource(
        cacheRoot: cacheRoot,
        runGit: (a) async {
          // Mid-clone the temp path exists and the target must not.
          fileSystem.directory(a.last).createSync(recursive: true);
          expect(target.existsSync(), isFalse);
          return _ok();
        },
      ).resolve(_ref);

      expect(target.existsSync(), isTrue);
    });

    test('reuses an existing clone without running git', () async {
      fileSystem
          .directory(p.join(cacheRoot.path, _ref.name, '0.0.5'))
          .createSync(recursive: true);
      var ran = false;

      final resolution = await GitPluginSource(
        cacheRoot: cacheRoot,
        runGit: (a) async {
          ran = true;
          return _ok();
        },
      ).resolve(_ref);

      expect(resolution, isA<ResolvedPlugin>());
      expect(ran, isFalse);
    });

    test('reports a clone failure and leaves no temp directory', () async {
      final resolution = await GitPluginSource(
        cacheRoot: cacheRoot,
        runGit: (a) async {
          fileSystem.directory(a.last).createSync(recursive: true);
          return ProcessResult(0, 128, '', 'Remote branch v0.0.5 not found');
        },
      ).resolve(_ref);

      expect(
        (resolution as UnavailablePlugin).reasons.single,
        contains('Could not clone'),
      );
      final leftovers = fileSystem
          .directory(p.join(cacheRoot.path, _ref.name))
          .listSync();
      expect(leftovers, isEmpty);
    });

    test('distinguishes a missing git binary from a clone failure', () async {
      // Process.run throws rather than returning a non-zero exit code when the
      // executable is absent.
      final resolution = await GitPluginSource(
        cacheRoot: cacheRoot,
        runGit: (a) async => throw const ProcessException('git', []),
      ).resolve(_ref);

      final reason = (resolution as UnavailablePlugin).reasons.single;
      expect(reason, contains('git is not installed'));
      expect(reason, contains('Claude Code'));
    });

    test('reports a cache root it cannot create', () async {
      // A plain file where the plugin directory needs to go, so createSync
      // fails the way an unwritable location would.
      fileSystem.file(p.join(cacheRoot.path, _ref.name)).createSync();
      var ran = false;

      final resolution = await GitPluginSource(
        cacheRoot: cacheRoot,
        runGit: (a) async {
          ran = true;
          return _ok();
        },
      ).resolve(_ref);

      expect(
        (resolution as UnavailablePlugin).reasons.single,
        contains('must be writable'),
      );
      expect(ran, isFalse, reason: 'should fail before invoking git');
    });

    test('reports a rename failure that left no usable target', () async {
      // A plain file sitting on the target path: the rename fails, and unlike
      // the concurrent-install case there is no good tree to fall back to.
      final resolution = await GitPluginSource(
        cacheRoot: cacheRoot,
        runGit: (a) async {
          fileSystem.directory(a.last).createSync(recursive: true);
          fileSystem.file(p.join(cacheRoot.path, _ref.name, '0.0.5'))
            ..createSync(recursive: true)
            ..writeAsStringSync('not a directory');
          return _ok();
        },
      ).resolve(_ref);

      expect(
        (resolution as UnavailablePlugin).reasons.single,
        contains('Could not move the clone'),
      );
    });

    test('treats a rename collision as a hit from a concurrent run', () async {
      final target = fileSystem.directory(
        p.join(cacheRoot.path, _ref.name, '0.0.5'),
      );

      final resolution = await GitPluginSource(
        cacheRoot: cacheRoot,
        runGit: (a) async {
          fileSystem.directory(a.last).createSync(recursive: true);
          // A concurrent install publishes first, so the rename will collide.
          target.createSync(recursive: true);
          fileSystem.file(p.join(target.path, 'winner.txt')).createSync();
          return _ok();
        },
      ).resolve(_ref);

      expect(resolution, isA<ResolvedPlugin>());
      // The winner's tree survives untouched.
      expect(
        fileSystem.file(p.join(target.path, 'winner.txt')).existsSync(),
        isTrue,
      );
    });
  });

  group('ChainedPluginSource', () {
    test('returns the first source that resolves', () async {
      _seedCache(fileSystem, version: '0.0.5');
      var clonedGit = false;

      final resolution = await ChainedPluginSource([
        LocalCachePluginSource(home: home),
        GitPluginSource(
          cacheRoot: fileSystem.directory('/cache')
            ..createSync(recursive: true),
          runGit: (a) async {
            clonedGit = true;
            return _ok();
          },
        ),
      ]).resolve(_ref);

      expect(resolution, isA<ResolvedPlugin>());
      expect(clonedGit, isFalse, reason: 'cache hit should short-circuit');
    });

    test('falls through to git when the cache misses', () async {
      final resolution = await ChainedPluginSource([
        LocalCachePluginSource(home: home),
        GitPluginSource(
          cacheRoot: fileSystem.directory('/cache')
            ..createSync(recursive: true),
          runGit: (a) async {
            fileSystem.directory(a.last).createSync(recursive: true);
            return _ok();
          },
        ),
      ]).resolve(_ref);

      expect(resolution, isA<ResolvedPlugin>());
    });

    test('accumulates every reason in order when all sources fail', () async {
      final resolution = await ChainedPluginSource([
        LocalCachePluginSource(home: home),
        GitPluginSource(
          cacheRoot: fileSystem.directory('/cache')
            ..createSync(recursive: true),
          runGit: (a) async => throw const ProcessException('git', []),
        ),
      ]).resolve(_ref);

      final reasons = (resolution as UnavailablePlugin).reasons;
      expect(reasons, hasLength(2));
      expect(reasons.first, contains('No Claude Code cache'));
      expect(reasons.last, contains('git is not installed'));
    });

    test('explains itself when it has no sources at all', () async {
      // Otherwise the exception renders "Could not resolve x:" and stops.
      final resolution = await const ChainedPluginSource([]).resolve(_ref);

      expect((resolution as UnavailablePlugin).reasons, [
        'no plugin sources were configured',
      ]);
    });
  });

  group('resolvePluginOrThrow', () {
    test('returns the directory on a hit', () async {
      final cached = _seedCache(fileSystem, version: '0.0.5');

      final directory = await resolvePluginOrThrow(
        _ref,
        source: LocalCachePluginSource(home: home),
      );

      expect(directory.path, cached.path);
    });

    test('throws with every reason when nothing resolves', () async {
      await expectLater(
        resolvePluginOrThrow(_ref, source: LocalCachePluginSource(home: home)),
        throwsA(
          isA<PluginResolutionException>()
              .having((e) => e.ref, 'ref', _ref)
              .having((e) => e.reasons, 'reasons', hasLength(1)),
        ),
      );
    });
  });
}
