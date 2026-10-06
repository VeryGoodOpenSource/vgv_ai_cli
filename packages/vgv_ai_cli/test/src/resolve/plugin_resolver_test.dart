import 'dart:io' show ProcessException, ProcessResult;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';

const _wingspan = PluginRef(
  name: 'wingspan',
  repo: 'acme/wingspan',
  version: '1.0.0',
  gitRef: 'v1.0.0',
);

const _flutter = PluginRef(
  name: 'flutter',
  repo: 'acme/flutter',
  version: '2.0.0',
  gitRef: 'v2.0.0',
);

/// A [PluginParser] that gives each plugin root one agent named after the
/// root's path, and records the roots it was asked to parse.
class _RecordingParser implements PluginParser {
  final roots = <String>[];

  @override
  PluginAssets parse(Directory root) {
    roots.add(root.path);
    return PluginAssets(
      skills: const [],
      agents: [
        AgentAsset(name: root.path, description: '', body: '', skills: []),
      ],
      mcpServers: const [],
    );
  }
}

class _ThrowingParser implements PluginParser {
  const new();

  @override
  PluginAssets parse(Directory root) =>
      throw const PluginParseException('/plugin/agents/a.md', 'bad name');
}

/// Records each process it is asked to run.
class _Processes {
  final calls = <List<String>>[];

  /// A [RunProcess] that fails the test, for runs that must not shell out.
  RunProcess get never =>
      (executable, arguments, {runInShell = false}) =>
          fail('ran $executable ${arguments.join(' ')}');

  /// A [RunProcess] whose `git clone` succeeds by creating its target in
  /// [fs].
  RunProcess clonesInto(FileSystem fs) =>
      (executable, arguments, {runInShell = false}) async {
        calls.add([executable, ...arguments]);
        fs.directory(arguments.last).createSync(recursive: true);
        return ProcessResult(0, 0, '', '');
      };

  /// A [RunProcess] that behaves as if git were not installed.
  RunProcess get noGit => (executable, arguments, {runInShell = false}) async {
    calls.add([executable, ...arguments]);
    throw ProcessException(executable, arguments);
  };
}

void main() {
  group('PluginResolver', () {
    late FileSystem fs;
    late Directory home;
    late _RecordingParser parser;
    late _Processes processes;

    setUp(() {
      fs = MemoryFileSystem.test();
      home = fs.directory('/home/dev')..createSync(recursive: true);
      parser = _RecordingParser();
      processes = _Processes();
    });

    String cached(PluginRef plugin) => fs.path.join(
      home.path,
      '.claude',
      'plugins',
      'cache',
      vgvMarketplaceName,
      plugin.name,
      plugin.version,
    );

    String cloned(PluginRef plugin) => fs.path.join(
      home.path,
      '.vgv_ai',
      'plugins',
      plugin.name,
      plugin.version,
    );

    void cache(PluginRef plugin) => fs
        .file(fs.path.join(cached(plugin), '.claude-plugin', 'plugin.json'))
        .createSync(recursive: true);

    test('uses the real Process.run and parser when none is injected', () {
      expect(const PluginResolver(), isNotNull);
    });

    test('prefers a complete Claude Code cache, and runs no git', () async {
      cache(_wingspan);
      cache(_flutter);
      final resolver = PluginResolver(
        runProcess: processes.never,
        parser: parser,
        plugins: const [_wingspan, _flutter],
      );

      final resolution = await resolver.resolve(home);

      expect(parser.roots, [cached(_wingspan), cached(_flutter)]);
      expect(
        resolution,
        isA<ResolvedAssets>()
            .having((r) => r.plugins, 'plugins', [_wingspan, _flutter])
            .having(
              (r) => r.assets.agents.map((agent) => agent.name),
              'agents',
              [cached(_flutter), cached(_wingspan)],
            ),
      );
    });

    test('clones the pinned tag when the cache is missing', () async {
      final resolver = PluginResolver(
        runProcess: processes.clonesInto(fs),
        parser: parser,
        plugins: const [_wingspan],
      );

      final resolution = await resolver.resolve(home);

      expect(resolution, isA<ResolvedAssets>());
      expect(parser.roots, [cloned(_wingspan)]);
      expect(processes.calls, [
        [
          'git',
          'clone',
          '--depth',
          '1',
          '--branch',
          'v1.0.0',
          'https://github.com/acme/wingspan.git',
          startsWith('${cloned(_wingspan)}.tmp.'),
        ],
      ]);
    });

    test('reuses an earlier clone without running git again', () async {
      fs.directory(cloned(_wingspan)).createSync(recursive: true);
      final resolver = PluginResolver(
        runProcess: processes.never,
        parser: parser,
        plugins: const [_wingspan],
      );

      await expectLater(
        resolver.resolve(home),
        completion(isA<ResolvedAssets>()),
      );
      expect(parser.roots, [cloned(_wingspan)]);
    });

    test('names every reason when no source has the plugin', () async {
      cache(_wingspan);
      final resolver = PluginResolver(
        runProcess: processes.noGit,
        parser: parser,
        plugins: const [_wingspan, _flutter],
      );

      final resolution = await resolver.resolve(home);

      expect(
        resolution,
        isA<UnavailableAssets>()
            .having((r) => r.plugin, 'plugin', _flutter)
            .having((r) => r.reasons, 'reasons', [
              startsWith('No Claude Code cache for flutter'),
              startsWith('git is not installed'),
            ]),
      );
    });

    test('stops at a plugin that cannot be parsed', () async {
      cache(_wingspan);
      cache(_flutter);
      final resolver = PluginResolver(
        runProcess: processes.never,
        parser: const _ThrowingParser(),
        plugins: const [_wingspan, _flutter],
      );

      final resolution = await resolver.resolve(home);

      expect(
        resolution,
        isA<UnparseableAssets>()
            .having((r) => r.plugin, 'plugin', _wingspan)
            .having((r) => r.error.path, 'path', '/plugin/agents/a.md'),
      );
    });

    test('parses with the Claude Code parser by default', () async {
      cache(_wingspan);
      final resolver = PluginResolver(
        runProcess: processes.never,
        plugins: const [_wingspan],
      );

      final resolution = await resolver.resolve(home);

      expect(
        resolution,
        isA<ResolvedAssets>().having((r) => r.assets.skills, 'skills', isEmpty),
      );
    });

    test('resolves the pinned VGV plugins by default', () async {
      vgvPlugins.forEach(cache);
      final resolver = PluginResolver(
        runProcess: processes.never,
        parser: parser,
      );

      final resolution = await resolver.resolve(home);

      expect(
        resolution,
        isA<ResolvedAssets>().having((r) => r.plugins, 'plugins', vgvPlugins),
      );
    });
  });
}
