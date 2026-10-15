import 'dart:io' show ProcessException, ProcessResult;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/src/plugin_ref.dart';
import 'package:plugin_source/src/resolution.dart';
import 'package:plugin_source/src/sources.dart';
import 'package:test/test.dart';

void main() {
  const ref = PluginRef(
    name: 'vgv-wingspan',
    repo: 'VeryGoodOpenSource/vgv-wingspan',
    version: '0.0.5',
    gitRef: 'v0.0.5',
  );

  late MemoryFileSystem fileSystem;

  setUp(() => fileSystem = MemoryFileSystem());

  group(LocalCachePluginSource, () {
    late Directory home;

    Directory seedCache({required String version, bool withManifest = true}) {
      final directory = fileSystem.directory(
        p.join(
          home.path,
          '.claude',
          'plugins',
          'cache',
          vgvMarketplaceName,
          ref.name,
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

    setUp(() {
      home = fileSystem.directory('/home/dev')..createSync(recursive: true);
    });

    test('resolves a complete cache entry at the pinned version', () async {
      final cached = seedCache(version: '0.0.5');

      await expectLater(
        LocalCachePluginSource(home: home).resolve(ref),
        completion(
          isA<ResolvedPlugin>().having(
            (r) => r.directory.path,
            'directory',
            cached.path,
          ),
        ),
      );
    });

    test('reports a miss when the plugin is not cached at all', () async {
      await expectLater(
        LocalCachePluginSource(home: home).resolve(ref),
        completion(
          isA<UnavailablePlugin>().having(
            (r) => r.reasons.single,
            'reason',
            contains('No Claude Code cache'),
          ),
        ),
      );
    });

    test('does not resolve a different cached version', () async {
      seedCache(version: '0.0.4');

      await expectLater(
        LocalCachePluginSource(home: home).resolve(ref),
        completion(
          isA<UnavailablePlugin>().having(
            (r) => r.reasons.single,
            'reason',
            allOf(contains('not at the pinned version'), contains('0.0.5')),
          ),
        ),
      );
    });

    test('does not resolve an entry with no plugin.json', () async {
      seedCache(version: '0.0.5', withManifest: false);

      await expectLater(
        LocalCachePluginSource(home: home).resolve(ref),
        completion(
          isA<UnavailablePlugin>().having(
            (r) => r.reasons.single,
            'reason',
            contains('looks incomplete'),
          ),
        ),
      );
    });

    test('ignores a .in_use marker', () async {
      final cached = seedCache(version: '0.0.5');
      fileSystem.file(p.join(cached.path, '.in_use')).createSync();

      await expectLater(
        LocalCachePluginSource(home: home).resolve(ref),
        completion(isA<ResolvedPlugin>()),
      );
    });
  });

  group(GitPluginSource, () {
    late Directory cacheRoot;

    ProcessResult ok() => ProcessResult(0, ExitCode.success.code, '', '');

    setUp(() {
      cacheRoot = fileSystem.directory('/home/dev/.vgv_ai/plugins')
        ..createSync(recursive: true);
    });

    test('clones the v-prefixed gitRef, not the cache version', () async {
      late List<String> args;

      await expectLater(
        GitPluginSource(
          cacheRoot: cacheRoot,
          runGit: (a) async {
            args = a;
            fileSystem.directory(a.last).createSync(recursive: true);
            return ok();
          },
        ).resolve(ref),
        completion(isA<ResolvedPlugin>()),
      );
      expect(args, containsAllInOrder(['--branch', 'v0.0.5']));
      expect(args, isNot(contains('0.0.5')));
    });

    test('publishes the version directory only after git succeeds', () async {
      final target = fileSystem.directory(
        p.join(cacheRoot.path, ref.name, '0.0.5'),
      );

      await GitPluginSource(
        cacheRoot: cacheRoot,
        runGit: (a) async {
          fileSystem.directory(a.last).createSync(recursive: true);
          expect(target.existsSync(), isFalse);
          return ok();
        },
      ).resolve(ref);

      expect(target.existsSync(), isTrue);
    });

    test('reuses an existing clone without running git', () async {
      fileSystem
          .directory(p.join(cacheRoot.path, ref.name, '0.0.5'))
          .createSync(recursive: true);
      var ran = false;

      await expectLater(
        GitPluginSource(
          cacheRoot: cacheRoot,
          runGit: (a) async {
            ran = true;
            return ok();
          },
        ).resolve(ref),
        completion(isA<ResolvedPlugin>()),
      );
      expect(ran, isFalse);
    });

    test('reports a clone failure and leaves no temp directory', () async {
      await expectLater(
        GitPluginSource(
          cacheRoot: cacheRoot,
          runGit: (a) async {
            fileSystem.directory(a.last).createSync(recursive: true);
            return ProcessResult(0, 128, '', 'Remote branch v0.0.5 not found');
          },
        ).resolve(ref),
        completion(
          isA<UnavailablePlugin>().having(
            (r) => r.reasons.single,
            'reason',
            contains('Could not clone'),
          ),
        ),
      );
      expect(
        fileSystem.directory(p.join(cacheRoot.path, ref.name)).listSync(),
        isEmpty,
      );
    });

    test('distinguishes a missing git binary from a clone failure', () async {
      await expectLater(
        GitPluginSource(
          cacheRoot: cacheRoot,
          runGit: (a) async => throw const ProcessException('git', []),
        ).resolve(ref),
        completion(
          isA<UnavailablePlugin>().having(
            (r) => r.reasons.single,
            'reason',
            allOf(contains('git is not installed'), contains('Claude Code')),
          ),
        ),
      );
    });

    test('reports a cache root it cannot create', () async {
      fileSystem.file(p.join(cacheRoot.path, ref.name)).createSync();
      var ran = false;

      await expectLater(
        GitPluginSource(
          cacheRoot: cacheRoot,
          runGit: (a) async {
            ran = true;
            return ok();
          },
        ).resolve(ref),
        completion(
          isA<UnavailablePlugin>().having(
            (r) => r.reasons.single,
            'reason',
            contains('must be writable'),
          ),
        ),
      );
      expect(ran, isFalse, reason: 'should fail before invoking git');
    });

    test('reports a rename failure that left no usable target', () async {
      await expectLater(
        GitPluginSource(
          cacheRoot: cacheRoot,
          runGit: (a) async {
            fileSystem.directory(a.last).createSync(recursive: true);
            fileSystem.file(p.join(cacheRoot.path, ref.name, '0.0.5'))
              ..createSync(recursive: true)
              ..writeAsStringSync('not a directory');
            return ok();
          },
        ).resolve(ref),
        completion(
          isA<UnavailablePlugin>().having(
            (r) => r.reasons.single,
            'reason',
            contains('Could not move the clone'),
          ),
        ),
      );
    });

    test('treats a rename collision as a hit from a concurrent run', () async {
      final target = fileSystem.directory(
        p.join(cacheRoot.path, ref.name, '0.0.5'),
      );

      await expectLater(
        GitPluginSource(
          cacheRoot: cacheRoot,
          runGit: (a) async {
            fileSystem.directory(a.last).createSync(recursive: true);
            target.createSync(recursive: true);
            fileSystem.file(p.join(target.path, 'winner.txt')).createSync();
            return ok();
          },
        ).resolve(ref),
        completion(isA<ResolvedPlugin>()),
      );
      expect(
        fileSystem.file(p.join(target.path, 'winner.txt')).existsSync(),
        isTrue,
      );
    });
  });
}
