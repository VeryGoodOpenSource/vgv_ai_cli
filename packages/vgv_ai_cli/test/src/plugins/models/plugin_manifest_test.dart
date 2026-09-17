import 'dart:convert';

import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/plugins.dart';

PluginAgent _agent(String id) =>
    PluginAgent(id: id, name: id, description: 'd');

ParsedPlugin _plugin(String name, {List<PluginAgent> agents = const []}) =>
    ParsedPlugin(
      source: PluginSource(repo: 'https://example.com/$name', ref: 'v1'),
      metadata: PluginMetadata(name: name),
      agents: agents,
    );

void main() {
  group('PluginSource', () {
    test('serializes, with a null sha until a fetch resolves it', () {
      const source = PluginSource(repo: 'https://example.com/p', ref: 'v1');

      expect(source.toJson(), {
        'repo': 'https://example.com/p',
        'ref': 'v1',
        'resolvedSha': null,
      });
    });

    test('carries a resolved sha when supplied', () {
      const source = PluginSource(
        repo: 'https://example.com/p',
        ref: 'v1',
        resolvedSha: 'abc123',
      );

      expect(source.toJson()['resolvedSha'], 'abc123');
    });
  });

  group('PluginMetadata', () {
    test('serializes every field, with absent ones null', () {
      final metadata = PluginMetadata(name: 'p');

      expect(metadata.toJson(), {
        'name': 'p',
        'version': null,
        'description': null,
        'author': null,
        'homepage': null,
        'repository': null,
        'license': null,
        'keywords': <String>[],
        'extra': <String, dynamic>{},
      });
    });

    test('carries an author of any shape', () {
      final asMap = PluginMetadata(name: 'p', author: {'name': 'VGV'});
      final asString = PluginMetadata(name: 'p', author: 'VGV');

      expect(asMap.toJson()['author'], {'name': 'VGV'});
      expect(asString.toJson()['author'], 'VGV');
    });

    test('exposes unmodifiable collections', () {
      final metadata = PluginMetadata(
        name: 'p',
        keywords: ['a'],
        extra: {'k': 'v'},
      );

      expect(() => metadata.keywords.add('b'), throwsUnsupportedError);
      expect(() => metadata.extra['other'] = 1, throwsUnsupportedError);
    });
  });

  group('ParsedPlugin', () {
    test('sorts agents by id regardless of input order', () {
      final plugin = _plugin(
        'p',
        agents: [_agent('z'), _agent('nested/a'), _agent('b')],
      );

      expect(plugin.agents.map((a) => a.id).toList(), ['b', 'nested/a', 'z']);
    });

    test('serializes its parts', () {
      final json = _plugin('p', agents: [_agent('a')]).toJson();

      expect(json['source'], isA<Map<String, dynamic>>());
      expect(json['metadata'], isA<Map<String, dynamic>>());
      expect(json['agents'], hasLength(1));
    });

    test('exposes an unmodifiable agent list', () {
      final plugin = _plugin('p', agents: [_agent('a')]);

      expect(() => plugin.agents.add(_agent('b')), throwsUnsupportedError);
    });
  });

  group('PluginManifest', () {
    test('defaults to the current schema version', () {
      expect(PluginManifest(plugins: []).schemaVersion, 1);
      expect(PluginManifest.currentSchema, 1);
    });

    test('accepts an explicit schema version', () {
      expect(PluginManifest(plugins: [], schemaVersion: 9).schemaVersion, 9);
    });

    test('sorts plugins by name regardless of input order', () {
      final manifest = PluginManifest(
        plugins: [_plugin('zeta'), _plugin('alpha'), _plugin('mid')],
      );

      expect(manifest.plugins.map((p) => p.metadata.name).toList(), [
        'alpha',
        'mid',
        'zeta',
      ]);
    });

    test('exposes an unmodifiable plugin list', () {
      final manifest = PluginManifest(plugins: [_plugin('p')]);

      expect(() => manifest.plugins.add(_plugin('q')), throwsUnsupportedError);
    });

    test('serializes to a JSON map', () {
      final manifest = PluginManifest(plugins: [_plugin('p')]);

      expect(manifest.toJson()['schemaVersion'], 1);
      expect(manifest.toJson()['plugins'], hasLength(1));
    });

    test('emits indented JSON with a trailing newline', () {
      final output = PluginManifest(plugins: [_plugin('p')]).toJsonString();

      expect(output, endsWith('}\n'));
      expect(output, contains('\n  "schemaVersion": 1,'));
      expect(jsonDecode(output), isA<Map<String, dynamic>>());
    });

    test('encodes a nested extra map without throwing', () {
      final manifest = PluginManifest(
        plugins: [
          ParsedPlugin(
            source: const PluginSource(repo: 'r', ref: 'v1'),
            metadata: PluginMetadata(name: 'p'),
            agents: [
              PluginAgent(
                id: 'a',
                name: 'a',
                description: 'd',
                extra: {
                  'hooks': {
                    'PreToolUse': [
                      {'matcher': 'Bash', 'count': 1, 'on': true, 'x': null},
                    ],
                  },
                },
              ),
            ],
          ),
        ],
      );

      final decoded =
          jsonDecode(manifest.toJsonString()) as Map<String, dynamic>;
      final plugins = decoded['plugins'] as List<dynamic>;
      final agents =
          (plugins.first as Map<String, dynamic>)['agents'] as List<dynamic>;
      final extra =
          (agents.first as Map<String, dynamic>)['extra']
              as Map<String, dynamic>;

      expect(extra['hooks'], isA<Map<String, dynamic>>());
    });
  });
}
