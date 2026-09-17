import 'dart:io';

import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';

/// The fixture deliberately reproduces the inconsistencies the real plugins
/// have, so a parser that only handles the documented shape fails here.
final _fixture = Directory('test/fixtures/plugin');

void main() {
  late PluginAssets assets;

  setUp(() => assets = PluginAssetsReader().read(_fixture));

  group('PluginAssetsReader', () {
    group('skills', () {
      test('skips a directory with no SKILL.md', () {
        expect(
          assets.skills.map((s) => s.name),
          isNot(contains('shared')),
          reason: 'skills/shared is a reference pool, not a skill',
        );
        expect(assets.skills, hasLength(4));
      });

      test('parses frontmatter and body separately', () {
        final testing = assets.skills.firstWhere((s) => s.name == 'testing');

        expect(testing.description, 'Best practices for Dart unit tests.');
        expect(testing.body, startsWith('# Dart Testing'));
        expect(testing.body, isNot(contains('allowed-tools')));
      });

      test('treats an absent user-invocable as invocable', () {
        final testing = assets.skills.firstWhere((s) => s.name == 'testing');
        expect(testing.userInvocable, isTrue);
      });

      test('honours an explicit user-invocable: false', () {
        final style = assets.skills.firstWhere(
          (s) => s.name == 'elements-of-style',
        );
        expect(style.userInvocable, isFalse);
      });

      test('strips Claude-only keys from portable frontmatter', () {
        final testing = assets.skills.firstWhere((s) => s.name == 'testing');

        expect(testing.frontmatter, contains('effort'));
        expect(testing.frontmatter, contains('when_to_use'));
        expect(testing.portableFrontmatter, isNot(contains('effort')));
        expect(testing.portableFrontmatter, isNot(contains('when_to_use')));
        expect(
          testing.portableFrontmatter,
          allOf(
            contains('name'),
            contains('description'),
            contains('allowed-tools'),
          ),
        );
      });

      test('reads comma-separated allowed-tools', () {
        final animations = assets.skills.firstWhere(
          (s) => s.name == 'animations',
        );
        expect(animations.frontmatter['allowed-tools'], 'Read,Glob,Grep');
      });

      test('keeps a skill that uses a flat reference.md', () {
        final ui = assets.skills.firstWhere((s) => s.name == 'ui-package');
        expect(
          Directory(ui.directory.path)
              .listSync()
              .map((e) => e.path.split('/').last),
          contains('reference.md'),
        );
      });
    });

    group('agents', () {
      test('flattens agents out of category directories', () {
        expect(
          assets.agents.map((a) => a.name),
          containsAll(<String>[
            'flutter-reviewer',
            'test-quality-review-agent',
          ]),
        );
      });

      test('parses an inline skills list', () {
        final agent = assets.agents.firstWhere(
          (a) => a.name == 'test-quality-review-agent',
        );
        expect(agent.skills, ['elements-of-style']);
      });

      test('parses a block sequence skills list', () {
        final agent = assets.agents.firstWhere(
          (a) => a.name == 'flutter-reviewer',
        );
        expect(agent.skills, ['testing', 'animations']);
      });

      test('flattens a block description onto one line', () {
        final agent = assets.agents.firstWhere(
          (a) => a.name == 'test-quality-review-agent',
        );
        expect(agent.description, startsWith('Reviews test coverage'));
        expect(agent.description, isNot(contains('\n')));
      });

      test('reads a folded description', () {
        final agent = assets.agents.firstWhere(
          (a) => a.name == 'flutter-reviewer',
        );
        expect(agent.description, 'Read-only Flutter reviewer.');
      });
    });

    group('mcpServers', () {
      test('reads both local and remote declarations', () {
        expect(assets.mcpServers.keys, containsAll(['dart', 'context7']));
        expect(assets.mcpServers['dart']!['command'], 'dart');
        expect(
          assets.mcpServers['context7']!['url'],
          'https://mcp.context7.com/mcp',
        );
      });
    });

    group('merge', () {
      test('combines two plugins and lets the later one win', () {
        final merged = PluginAssets.empty.merge(assets).merge(assets);

        expect(merged.skills, hasLength(assets.skills.length));
        expect(merged.agents, hasLength(assets.agents.length));
      });
    });

    test('returns empty for a directory with nothing in it', () {
      final empty = Directory.systemTemp.createTempSync('vgv_empty_');
      addTearDown(() => empty.deleteSync(recursive: true));

      final result = PluginAssetsReader().read(empty);

      expect(result.skills, isEmpty);
      expect(result.agents, isEmpty);
      expect(result.mcpServers, isEmpty);
    });
  });
}
