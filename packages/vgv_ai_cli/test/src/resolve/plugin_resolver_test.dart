import 'dart:io' show ProcessException, ProcessResult;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';

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

/// A [PluginParser] that throws for any root under [rejected], naming the
/// root, and otherwise parses like [_RecordingParser].
class _RejectingParser(final String rejected) extends _RecordingParser {
  @override
  PluginAssets parse(Directory root) {
    if (root.path.startsWith(rejected)) {
      throw PluginParseException(root.path, 'bad name');
    }
    return super.parse(root);
  }
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
  group(PluginResolver, () {
    const wingspan = PluginRef(
      name: 'wingspan',
      repo: 'acme/wingspan',
      version: '1.0.0',
      gitRef: 'v1.0.0',
    );

    const flutter = PluginRef(
      name: 'flutter',
      repo: 'acme/flutter',
      version: '2.0.0',
      gitRef: 'v2.0.0',
    );

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
      cache(wingspan);
      cache(flutter);
      final resolver = PluginResolver(
        runProcess: processes.never,
        parser: parser,
        plugins: const [wingspan, flutter],
      );

      final resolution = await resolver.resolve(home);

      expect(parser.roots, [cached(wingspan), cached(flutter)]);
      expect(
        resolution,
        isA<ResolvedAssets>()
            .having((r) => r.plugins, 'plugins', [wingspan, flutter])
            .having(
              (r) => r.assets.agents.map((agent) => agent.name),
              'agents',
              [cached(flutter), cached(wingspan)],
            ),
      );
    });

    test('clones the pinned tag when the cache is missing', () async {
      final resolver = PluginResolver(
        runProcess: processes.clonesInto(fs),
        parser: parser,
        plugins: const [wingspan],
      );

      final resolution = await resolver.resolve(home);

      expect(resolution, isA<ResolvedAssets>());
      expect(parser.roots, [cloned(wingspan)]);
      expect(processes.calls, [
        [
          'git',
          'clone',
          '--depth',
          '1',
          '--branch',
          'v1.0.0',
          'https://github.com/acme/wingspan.git',
          startsWith('${cloned(wingspan)}.tmp.'),
        ],
      ]);
    });

    test('reuses an earlier clone without running git again', () async {
      fs.directory(cloned(wingspan)).createSync(recursive: true);
      final resolver = PluginResolver(
        runProcess: processes.never,
        parser: parser,
        plugins: const [wingspan],
      );

      await expectLater(
        resolver.resolve(home),
        completion(isA<ResolvedAssets>()),
      );
      expect(parser.roots, [cloned(wingspan)]);
    });

    test('names every reason when no source has the plugin', () async {
      cache(wingspan);
      final resolver = PluginResolver(
        runProcess: processes.noGit,
        parser: parser,
        plugins: const [wingspan, flutter],
      );

      final resolution = await resolver.resolve(home);

      expect(
        resolution,
        isA<UnavailableAssets>()
            .having((r) => r.plugin, 'plugin', flutter)
            .having((r) => r.reasons, 'reasons', [
              startsWith('No Claude Code cache for flutter'),
              startsWith('git is not installed'),
            ]),
      );
    });

    test('clones the pinned tag when the cached copy does not parse', () async {
      cache(wingspan);
      final rejecting = _RejectingParser(fs.path.join(home.path, '.claude'));
      final resolver = PluginResolver(
        runProcess: processes.clonesInto(fs),
        parser: rejecting,
        plugins: const [wingspan],
      );

      final resolution = await resolver.resolve(home);

      expect(resolution, isA<ResolvedAssets>());
      expect(rejecting.roots, [cloned(wingspan)]);
      expect(processes.calls, hasLength(1));
    });

    test('stops at a plugin no source has a parseable copy of', () async {
      cache(wingspan);
      cache(flutter);
      final resolver = PluginResolver(
        runProcess: processes.noGit,
        parser: _RejectingParser(home.path),
        plugins: const [wingspan, flutter],
      );

      final resolution = await resolver.resolve(home);

      expect(
        resolution,
        isA<UnparseableAssets>()
            .having((r) => r.plugin, 'plugin', wingspan)
            .having((r) => r.error.path, 'path', cached(wingspan)),
      );
    });

    test('reports the last parse error when every copy fails', () async {
      cache(wingspan);
      final resolver = PluginResolver(
        runProcess: processes.clonesInto(fs),
        parser: _RejectingParser(home.path),
        plugins: const [wingspan],
      );

      final resolution = await resolver.resolve(home);

      expect(
        resolution,
        isA<UnparseableAssets>().having(
          (r) => r.error.path,
          'path',
          cloned(wingspan),
        ),
      );
    });

    test('parses with the Claude Code parser by default', () async {
      cache(wingspan);
      final resolver = PluginResolver(
        runProcess: processes.never,
        plugins: const [wingspan],
      );

      final resolution = await resolver.resolve(home);

      expect(
        resolution,
        isA<ResolvedAssets>().having((r) => r.assets.skills, 'skills', isEmpty),
      );
    });

    test('resolves only the plugins `only` names', () async {
      cache(wingspan);
      final resolver = PluginResolver(
        runProcess: processes.never,
        parser: parser,
        plugins: const [wingspan, flutter],
      );

      final resolution = await resolver.resolve(home, only: {wingspan.name});

      expect(parser.roots, [cached(wingspan)]);
      expect(
        resolution,
        isA<ResolvedAssets>().having((r) => r.plugins, 'plugins', [wingspan]),
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
