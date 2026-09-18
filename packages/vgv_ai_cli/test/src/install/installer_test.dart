import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/generation/generation.dart';
import 'package:vgv_ai_cli/src/install/installer.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_resolver.dart';

import '../../helpers/fake_plugin_fetcher.dart';

void main() {
  group('Installer', () {
    late Directory home;
    late Directory marketplace;
    late Directory wingspan;

    void writeFile(Directory root, String relativePath, String content) {
      File(p.join(root.path, relativePath))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    setUp(() {
      home = Directory.systemTemp.createTempSync('installer_home_');
      marketplace = Directory.systemTemp.createTempSync('installer_market_');
      wingspan = Directory.systemTemp.createTempSync('installer_wingspan_');

      writeFile(marketplace, '.claude-plugin/marketplace.json', '''
{
  "plugins": [
    {
      "name": "vgv-wingspan",
      "source": {"source": "github", "repo": "VeryGoodOpenSource/vgv-wingspan"}
    }
  ]
}
''');
      writeFile(wingspan, '.mcp.json', '''
{"mcpServers": {"dart": {"command": "dart", "args": ["mcp-server"]}}}
''');
      writeFile(wingspan, 'skills/plan/SKILL.md', '''
---
name: plan
description: Plan work.
---

Plan body.
''');
    });

    tearDown(() {
      home.deleteSync(recursive: true);
      marketplace.deleteSync(recursive: true);
      wingspan.deleteSync(recursive: true);
    });

    FakePluginFetcher fetcher({String commit = 'fixturecommit'}) =>
        FakePluginFetcher(
          marketplace: marketplace,
          plugins: {'VeryGoodOpenSource/vgv-wingspan': wingspan},
          commit: commit,
        );

    Installer installer(FakePluginFetcher f) => Installer(
      resolver: PluginResolver(fetcher: f),
      home: home,
    );

    File homeFile(List<String> segments) =>
        File(p.joinAll([home.path, ...segments]));

    test(
      'writes only the selected harness config into the real config',
      () async {
        await installer(fetcher()).install(
          harnesses: const HarnessSelection(pi: true),
          skillsRoot: '~/.agents/skills',
        );

        expect(
          homeFile(['.pi', 'agent', 'settings.json']).existsSync(),
          isTrue,
        );
        expect(homeFile(['.gemini', 'settings.json']).existsSync(), isFalse);
        expect(homeFile(['.claude', 'settings.json']).existsSync(), isFalse);
      },
    );

    test('materializes skills under the skills root and pins them', () async {
      await installer(fetcher()).install(
        harnesses: const HarnessSelection(pi: true),
        skillsRoot: '~/.agents/skills',
      );

      final skill = homeFile([
        '.agents',
        'skills',
        'vgv-wingspan',
        'plan',
        'SKILL.md',
      ]);
      expect(skill.existsSync(), isTrue);

      final lock = jsonDecode(
        homeFile(['.agents', 'skills', 'skills-lock.json']).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect((lock['plugins'] as Map)['vgv-wingspan'], isNotNull);
    });

    test('preserves user keys when merging into an existing config', () async {
      final settings = homeFile(['.gemini', 'settings.json'])
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"theme": "dark"}');

      await installer(fetcher()).install(
        harnesses: const HarnessSelection(gemini: true),
        skillsRoot: '~/.agents/skills',
      );

      final merged =
          jsonDecode(settings.readAsStringSync()) as Map<String, dynamic>;
      expect(merged['theme'], 'dark');
      expect(merged['mcpServers'], contains('dart'));
    });

    test('reuses the locked commit on a pinned re-run', () async {
      await installer(fetcher(commit: 'sha-one')).install(
        harnesses: const HarnessSelection(pi: true),
        skillsRoot: '~/.agents/skills',
      );

      final second = fetcher(commit: 'sha-two');
      await installer(second).install(
        harnesses: const HarnessSelection(pi: true),
        skillsRoot: '~/.agents/skills',
      );

      expect(
        second.pinnedCommits['VeryGoodOpenSource/vgv-wingspan'],
        'sha-one-VeryGoodOpenSource/vgv-wingspan',
      );
    });

    test('ignores the lock and refreshes when update is set', () async {
      await installer(fetcher(commit: 'sha-one')).install(
        harnesses: const HarnessSelection(pi: true),
        skillsRoot: '~/.agents/skills',
      );

      final second = fetcher(commit: 'sha-two');
      await installer(second).install(
        harnesses: const HarnessSelection(pi: true),
        skillsRoot: '~/.agents/skills',
        update: true,
      );

      expect(second.pinnedCommits, isEmpty);
    });
  });
}
