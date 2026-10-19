import 'dart:convert';
import 'dart:io';

import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';

import '../../tool/bump_plugin_pins.dart';

void main() {
  const wingspan = PluginRef(
    name: 'vgv-wingspan',
    repo: 'VeryGoodOpenSource/vgv-wingspan',
    version: '0.0.5',
    gitRef: 'v0.0.5',
  );

  const pinsSource = '''
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

  ProcessResult ok(String stdout) => ProcessResult(0, 0, stdout, '');

  group('bumpFor', () {
    test('is null when the release is the pin', () {
      expect(
        bumpFor(wingspan, const PluginRelease(tag: 'v0.0.5', version: '0.0.5')),
        isNull,
      );
    });

    test('moves the pin to the release tag and plugin.json version', () {
      final bump = bumpFor(
        wingspan,
        const PluginRelease(tag: 'v0.1.0', version: '0.1.0'),
      );

      expect(bump?.name, wingspan.name);
      expect(bump?.repo, wingspan.repo);
      expect(bump?.version, '0.1.0');
      expect(bump?.gitRef, 'v0.1.0');
    });

    test('bumps when only the tag differs', () {
      final bump = bumpFor(
        wingspan,
        const PluginRelease(tag: 'v0.0.5-fix', version: '0.0.5'),
      );

      expect(bump?.gitRef, 'v0.0.5-fix');
    });
  });

  group('rewritePin', () {
    test('rewrites only the block whose repo matches', () {
      final rewritten = rewritePin(
        pinsSource,
        const PluginRef(
          name: 'vgv-wingspan',
          repo: 'VeryGoodOpenSource/vgv-wingspan',
          version: '0.1.0',
          gitRef: 'v0.1.0',
        ),
      );

      expect(
        rewritten,
        pinsSource.replaceFirst(
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
          pinsSource,
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
        () => rewritePin('$pinsSource$pinsSource', wingspan),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when the block has no version', () {
      expect(
        () => rewritePin(
          pinsSource.replaceFirst("    version: '0.0.5',\n", ''),
          wingspan,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when the block has no gitRef', () {
      expect(
        () => rewritePin(
          pinsSource.replaceFirst("    gitRef: 'v0.0.5',\n", ''),
          wingspan,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('latestRelease', () {
    test('reads the release tag and the plugin.json version at it', () async {
      final calls = <List<String>>[];
      final release = await latestRelease(
        wingspan,
        runGh: (args) async {
          calls.add(args);
          return args[1].contains('releases/latest')
              ? ok('v0.1.0\n')
              : ok(jsonEncode({'name': 'vgv-wingspan', 'version': '0.1.0'}));
        },
      );

      expect(release.tag, 'v0.1.0');
      expect(release.version, '0.1.0');
      expect(calls.last[1], contains('plugin.json?ref=v0.1.0'));
    });

    test('throws with stderr when gh fails', () {
      expect(
        () => latestRelease(
          wingspan,
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
          wingspan,
          runGh: (args) async =>
              args[1].contains('releases/latest') ? ok('v0.1.0') : ok('{}'),
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
      file = File('${temp.path}/plugin_ref.dart')
        ..writeAsStringSync(pinsSource);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    RunGh releases(Map<String, String> tags) => (args) async {
      final repo = tags.keys.firstWhere((repo) => args[1].contains(repo));
      final tag = tags[repo]!;
      return args[1].contains('releases/latest')
          ? ok(tag)
          : ok(jsonEncode({'version': tag.substring(1)}));
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
      expect(file.readAsStringSync(), pinsSource);
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

      expect(
        bumps.single.toString(),
        'vgv-wingspan: 0.0.5 (v0.0.5) -> 0.1.0 (v0.1.0) '
        'https://github.com/VeryGoodOpenSource/vgv-wingspan/releases/tag/v0.1.0',
      );
      expect(
        file.readAsStringSync(),
        pinsSource.replaceFirst(
          "version: '0.0.5',\n    gitRef: 'v0.0.5',",
          "version: '0.1.0',\n    gitRef: 'v0.1.0',",
        ),
      );
    });
  });
}
