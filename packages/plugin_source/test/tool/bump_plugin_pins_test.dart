import 'dart:convert';
import 'dart:io';

import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';

import '../../tool/bump_plugin_pins.dart';

const _wingspan = PluginRef(
  name: 'vgv-wingspan',
  repo: 'VeryGoodOpenSource/vgv-wingspan',
  version: '0.0.5',
  gitRef: 'v0.0.5',
);

const _source = '''
const vgvPlugins = <PluginRef>[
  PluginRef(
    name: 'vgv-wingspan',
    repo: 'VeryGoodOpenSource/vgv-wingspan',
    version: '0.0.5',
    gitRef: 'v0.0.5',
  ),
  PluginRef(
    name: 'vgv-ai-flutter-plugin',
    repo: 'VeryGoodOpenSource/vgv-ai-flutter-plugin',
    version: '0.0.5',
    gitRef: 'v0.0.5',
  ),
];
''';

void main() {
  group('bumpFor', () {
    test('is null when the release is the pin', () {
      expect(
        bumpFor(
          _wingspan,
          const PluginRelease(tag: 'v0.0.5', version: '0.0.5'),
        ),
        isNull,
      );
    });

    test('moves the pin to the release tag and plugin.json version', () {
      final bump = bumpFor(
        _wingspan,
        const PluginRelease(tag: 'v0.1.0', version: '0.1.0'),
      );

      expect(bump?.name, _wingspan.name);
      expect(bump?.repo, _wingspan.repo);
      expect(bump?.version, '0.1.0');
      expect(bump?.gitRef, 'v0.1.0');
    });

    test('bumps when only the tag differs', () {
      final bump = bumpFor(
        _wingspan,
        const PluginRelease(tag: 'v0.0.5-fix', version: '0.0.5'),
      );

      expect(bump?.gitRef, 'v0.0.5-fix');
    });
  });

  group('rewritePin', () {
    test('rewrites only the block whose repo matches', () {
      final rewritten = rewritePin(
        _source,
        const PluginRef(
          name: 'vgv-wingspan',
          repo: 'VeryGoodOpenSource/vgv-wingspan',
          version: '0.1.0',
          gitRef: 'v0.1.0',
        ),
      );

      expect(
        rewritten,
        _source.replaceFirst(
          "version: '0.0.5',\n    gitRef: 'v0.0.5',",
          "version: '0.1.0',\n    gitRef: 'v0.1.0',",
        ),
      );
    });

    test('is the identity for the current pins in plugin_ref.dart', () {
      final source = File('lib/src/plugin_ref.dart').readAsStringSync();

      expect(vgvPlugins.fold(source, rewritePin), source);
    });

    test('throws when no block has the repo', () {
      expect(
        () => rewritePin(
          _source,
          const PluginRef(
            name: 'other',
            repo: 'VeryGoodOpenSource/other',
            version: '0.1.0',
            gitRef: 'v0.1.0',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when several blocks have the repo', () {
      expect(
        () => rewritePin('$_source$_source', _wingspan),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when the block has no version', () {
      expect(
        () => rewritePin(
          _source.replaceFirst("    version: '0.0.5',\n", ''),
          _wingspan,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when the block has no gitRef', () {
      expect(
        () => rewritePin(
          _source.replaceFirst("    gitRef: 'v0.0.5',\n", ''),
          _wingspan,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('latestRelease', () {
    test('reads the release tag and the plugin.json version at it', () async {
      final calls = <List<String>>[];
      final release = await latestRelease(
        _wingspan,
        runGh: (args) async {
          calls.add(args);
          return args[1].contains('releases/latest')
              ? _ok('v0.1.0\n')
              : _ok(jsonEncode({'name': 'vgv-wingspan', 'version': '0.1.0'}));
        },
      );

      expect(release.tag, 'v0.1.0');
      expect(release.version, '0.1.0');
      expect(calls.last[1], contains('plugin.json?ref=v0.1.0'));
    });

    test('throws with stderr when gh fails', () {
      expect(
        () => latestRelease(
          _wingspan,
          runGh: (args) async => ProcessResult(0, 1, '', 'HTTP 404'),
        ),
        throwsA(
          isA<ProcessException>().having(
            (error) => error.message,
            'message',
            'HTTP 404',
          ),
        ),
      );
    });

    test('throws when plugin.json has no version', () {
      expect(
        () => latestRelease(
          _wingspan,
          runGh: (args) async =>
              args[1].contains('releases/latest') ? _ok('v0.1.0') : _ok('{}'),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('bumpPins', () {
    late Directory temp;
    late File file;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('bump_plugin_pins_test.');
      file = File('${temp.path}/plugin_ref.dart')..writeAsStringSync(_source);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    RunGh releases(Map<String, String> tags) => (args) async {
      final repo = tags.keys.firstWhere((repo) => args[1].contains(repo));
      final tag = tags[repo]!;
      return args[1].contains('releases/latest')
          ? _ok(tag)
          : _ok(jsonEncode({'version': tag.substring(1)}));
    };

    test('leaves the file untouched when every pin is current', () async {
      final modified = file.lastModifiedSync();

      final bumps = await bumpPins(
        file,
        runGh: releases({
          'vgv-wingspan': 'v0.0.5',
          'vgv-ai-flutter-plugin': 'v0.0.5',
        }),
      );

      expect(bumps, isEmpty);
      expect(file.readAsStringSync(), _source);
      expect(file.lastModifiedSync(), modified);
    });

    test('rewrites only the pins that are behind', () async {
      final bumps = await bumpPins(
        file,
        runGh: releases({
          'vgv-wingspan': 'v0.1.0',
          'vgv-ai-flutter-plugin': 'v0.0.5',
        }),
      );

      expect(bumps.map((bump) => bump.toString()), [
        'vgv-wingspan: 0.0.5 (v0.0.5) -> 0.1.0 (v0.1.0)',
      ]);
      expect(
        file.readAsStringSync(),
        _source.replaceFirst(
          "version: '0.0.5',\n    gitRef: 'v0.0.5',",
          "version: '0.1.0',\n    gitRef: 'v0.1.0',",
        ),
      );
    });
  });
}

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
