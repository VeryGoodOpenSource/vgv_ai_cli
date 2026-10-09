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
}
