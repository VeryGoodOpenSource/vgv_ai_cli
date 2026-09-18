import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/plugin_source/resolution.dart';

const _fs = LocalFileSystem();

/// The fixture reproduces the inconsistencies the real plugins have, so a
/// reader that only handles the documented shape fails here.
Directory _fixture(String name) =>
    _fs.directory(p.join('test', 'fixtures', name));

/// Copies [from] into [to] without shelling out, so the test runs anywhere.
void _copyInto(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final target = p.join(to.path, p.basename(entity.path));
    if (entity is Directory) {
      _copyInto(entity, _fs.directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

void main() {
  late PluginAssets assets;

  setUp(() => assets = const PluginAssetsReader().read(_fixture('plugin')));

  group('skills', () {
    test('reads every directory holding a SKILL.md, sorted by name', () {
      expect(assets.skills.map((s) => s.name), [
        'animations',
        'elements-of-style',
        'testing',
        'ui-package',
      ]);
    });

    test('skips skills/shared, which has no SKILL.md', () {
      // It is a pooled link target, not a skill.
      expect(assets.skills.map((s) => s.name), isNot(contains('shared')));
    });

    test('separates frontmatter from body', () {
      final testing = assets.skills.firstWhere((s) => s.name == 'testing');

      expect(testing.description, startsWith('Best practices'));
      expect(testing.body, startsWith('# Dart Testing'));
      expect(testing.body, isNot(contains('allowed-tools')));
    });

    test('keeps body content past a horizontal rule', () {
      final testing = assets.skills.firstWhere((s) => s.name == 'testing');

      expect(testing.body, contains('must not be mistaken'));
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

    test('reads comma-separated allowed-tools', () {
      final animations = assets.skills.firstWhere(
        (s) => s.name == 'animations',
      );

      expect(animations.frontmatter.allowedTools, ['Read', 'Glob', 'Grep']);
    });

    test('keeps a skill that uses a flat reference.md', () {
      final ui = assets.skills.firstWhere((s) => s.name == 'ui-package');

      expect(
        ui.directory.listSync().map((e) => p.basename(e.path)),
        contains('reference.md'),
      );
    });

    test('falls back to the directory name when frontmatter has none', () {
      for (final skill in assets.skills) {
        expect(skill.name, isNotEmpty);
      }
    });
  });

  group('portableFrontmatter', () {
    late SkillAsset testing;

    setUp(() => testing = assets.skills.firstWhere((s) => s.name == 'testing'));

    test('drops Claude-only keys', () {
      expect(testing.frontmatter.values, contains('effort'));
      expect(testing.frontmatter.values, contains('when_to_use'));
      expect(testing.portableFrontmatter, isNot(contains('effort')));
      expect(testing.portableFrontmatter, isNot(contains('when_to_use')));
    });

    test('keeps portable keys', () {
      expect(
        testing.portableFrontmatter,
        allOf(
          contains('name'),
          contains('description'),
          contains('allowed-tools'),
          contains('model'),
        ),
      );
    });

    test('keeps compatibility, which is prose rather than a Claude flag', () {
      expect(testing.portableFrontmatter, contains('compatibility'));
    });

    test('drops user-invocable', () {
      final style = assets.skills.firstWhere(
        (s) => s.name == 'elements-of-style',
      );

      expect(style.portableFrontmatter, isNot(contains('user-invocable')));
    });
  });

  group('agents', () {
    test('flattens agents out of category directories, sorted', () {
      expect(assets.agents.map((a) => a.name), [
        'flutter-reviewer',
        'test-quality-review-agent',
      ]);
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

    test('flattens a literal block description onto one line', () {
      final agent = assets.agents.firstWhere(
        (a) => a.name == 'test-quality-review-agent',
      );

      expect(
        agent.description,
        'Reviews test coverage and quality across a change.',
      );
    });

    test('reads a folded description', () {
      final agent = assets.agents.firstWhere(
        (a) => a.name == 'flutter-reviewer',
      );

      expect(agent.description, 'Read-only Flutter reviewer.');
    });

    test('keeps the prompt body', () {
      final agent = assets.agents.firstWhere(
        (a) => a.name == 'flutter-reviewer',
      );

      expect(agent.body, 'Review the diff.\n');
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

    test('skips an entry that is not an object', () {
      expect(assets.mcpServers.keys, isNot(contains('ignored')));
    });

    test('is empty when the plugin has no .mcp.json', () {
      final noMcp = const PluginAssetsReader().read(_fixture('plugin_no_mcp'));

      expect(noMcp.mcpServers, isEmpty);
      expect(noMcp.skills, hasLength(1));
    });

    test('throws when .mcp.json is valid JSON but not an object', () {
      expect(
        () => const PluginAssetsReader().read(_fixture('plugin_array_mcp')),
        throwsA(
          isA<PluginParseException>().having(
            (e) => e.message,
            'message',
            contains('JSON object'),
          ),
        ),
      );
    });

    test('throws a PluginParseException on invalid JSON', () {
      // jsonDecode throws FormatException, which the runner would render as a
      // CLI usage error.
      expect(
        () => const PluginAssetsReader().read(_fixture('plugin_bad_mcp')),
        throwsA(
          isA<PluginParseException>().having(
            (e) => e.path,
            'path',
            contains('.mcp.json'),
          ),
        ),
      );
    });
  });

  group('empty plugin', () {
    test('reads as empty rather than throwing', () {
      // The reader stays total. Whether an empty plugin is a problem is the
      // caller's judgement, because only it knows which plugin it asked for.
      final empty = const PluginAssetsReader().read(_fixture('plugin_empty'));

      expect(empty.skills, isEmpty);
      expect(empty.agents, isEmpty);
      expect(empty.mcpServers, isEmpty);
    });
  });

  group('symlinked references', () {
    late Directory temp;

    setUpAll(() {
      // Built here rather than committed: a git checkout on Windows without
      // developer mode materializes a committed symlink as a text file holding
      // the target path, so the regression would silently pass there.
      temp = _fs.systemTempDirectory.createTempSync('vgv_symlink_');
      _copyInto(_fixture('plugin'), _fs.directory(p.join(temp.path, 'plugin')));

      final skill = p.join(temp.path, 'plugin', 'skills', 'testing');
      _fs
          .link(p.join(skill, 'references', 'pooled.md'))
          .createSync(p.join('..', '..', 'shared', 'references', 'pooled.md'));
    });

    tearDownAll(() => temp.deleteSync(recursive: true));

    test('resolve to real content through the reader', () {
      // 21 reference files across 8 wingspan skills link into skills/shared,
      // so anything copying a skill directory must keep them resolvable.
      final linked = const PluginAssetsReader()
          .read(_fs.directory(p.join(temp.path, 'plugin')))
          .skills
          .firstWhere((s) => s.name == 'testing');

      final pooled = _fs.file(
        p.join(linked.directory.path, 'references', 'pooled.md'),
      );

      expect(pooled.existsSync(), isTrue);
      expect(pooled.readAsStringSync(), contains('pooled reference content'));
    });
  });

  group('merge', () {
    test('combines two plugins', () {
      final other = const PluginAssetsReader().read(_fixture('plugin_no_mcp'));

      final merged = assets.merge(other);

      expect(
        merged.skills.map((s) => s.name),
        containsAll(['testing', 'only']),
      );
      expect(merged.mcpServers.keys, containsAll(['dart', 'context7']));
    });

    test('lets the later plugin win a name clash', () {
      final merged = PluginAssets.empty.merge(assets).merge(assets);

      expect(merged.skills, hasLength(assets.skills.length));
      expect(merged.agents, hasLength(assets.agents.length));
    });

    test('empty is a neutral starting point', () {
      final merged = PluginAssets.empty.merge(assets);

      expect(merged.skills, hasLength(assets.skills.length));
    });
  });
}
