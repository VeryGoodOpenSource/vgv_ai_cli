import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_extractor.dart';

void main() {
  group('PluginExtractor', () {
    const extractor = PluginExtractor();
    late Directory plugin;

    setUp(() {
      plugin = Directory.systemTemp.createTempSync('extractor_test_');
    });

    tearDown(() => plugin.deleteSync(recursive: true));

    void writeFile(String relativePath, String content) {
      File(p.join(plugin.path, relativePath))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    group('extractMcpServers', () {
      test('returns empty when .mcp.json is missing', () {
        expect(extractor.extractMcpServers(plugin), isEmpty);
      });

      test('returns empty when the JSON is malformed', () {
        writeFile('.mcp.json', 'not json');
        expect(extractor.extractMcpServers(plugin), isEmpty);
      });

      test('returns empty when mcpServers is absent', () {
        writeFile('.mcp.json', '{"other": {}}');
        expect(extractor.extractMcpServers(plugin), isEmpty);
      });

      test('parses local and remote servers', () {
        writeFile('.mcp.json', '''
{
  "mcpServers": {
    "local": {"command": "dart", "args": ["run", "server"]},
    "remote": {"url": "https://example.com/mcp"}
  }
}
''');

        final servers = extractor.extractMcpServers(plugin);

        expect(servers.keys, unorderedEquals(['local', 'remote']));
        expect(servers['local']!.command, 'dart');
        expect(servers['local']!.args, ['run', 'server']);
        expect(servers['remote']!.url, 'https://example.com/mcp');
        expect(servers['remote']!.isRemote, isTrue);
      });

      test('skips entries that are not maps', () {
        writeFile('.mcp.json', '{"mcpServers": {"bad": 1, "ok": {}}}');

        final servers = extractor.extractMcpServers(plugin);

        expect(servers.keys, ['ok']);
      });
    });

    group('extractSkills', () {
      test('returns empty when skills/ is missing', () {
        expect(extractor.extractSkills(plugin), isEmpty);
      });

      test('parses each skill and records its source path', () {
        writeFile('skills/plan/SKILL.md', '''
---
name: plan
description: Plan the work.
---

Body.
''');
        writeFile('skills/review/SKILL.md', '''
---
name: review
description: Review the work.
---
''');

        final skills = extractor.extractSkills(plugin);

        expect(skills, hasLength(2));
        expect(skills.first.skill.name, 'plan');
        expect(skills.first.skill.description, 'Plan the work.');
        expect(skills.first.source, p.join('skills', 'plan'));
        expect(skills.last.skill.name, 'review');
        expect(skills.last.source, p.join('skills', 'review'));
      });

      test('skips directories without a SKILL.md', () {
        Directory(p.join(plugin.path, 'skills', 'empty'))
            .createSync(recursive: true);

        expect(extractor.extractSkills(plugin), isEmpty);
      });

      test('skips skills missing name or description', () {
        writeFile('skills/nameless/SKILL.md', '''
---
description: No name here.
---
''');

        expect(extractor.extractSkills(plugin), isEmpty);
      });
    });

    group('extractAgents', () {
      test('returns empty when agents/ is missing', () {
        expect(extractor.extractAgents(plugin), isEmpty);
      });

      test('parses agents recursively, ignoring non-markdown files', () {
        writeFile('agents/planner.md', '''
---
name: planner
description: Plans things.
---
''');
        writeFile('agents/nested/builder.md', '''
---
name: builder
description: Builds things.
---
''');
        writeFile('agents/notes.txt', 'ignored');

        final agents = extractor.extractAgents(plugin);

        expect(agents, hasLength(2));
        expect(agents.map((agent) => agent.name), ['builder', 'planner']);
      });

      test('skips agents missing name or description', () {
        writeFile('agents/broken.md', '''
---
name: broken
---
''');

        expect(extractor.extractAgents(plugin), isEmpty);
      });
    });
  });
}
