import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_fetcher.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_resolver.dart';

import '../../helpers/fake_plugin_fetcher.dart';

class _PartiallyFailingFetcher implements PluginFetcher {
  new(this._marketplace);

  final Directory _marketplace;
  var _calls = 0;

  @override
  Future<FetchedRepo> fetchMarketplace() async =>
      FetchedRepo(directory: _marketplace, commit: 'market');

  @override
  Future<FetchedRepo> fetchPlugin(String repo, {String? commit}) async {
    _calls++;
    if (_calls == 2) throw Exception('boom');
    return FetchedRepo(
      directory: Directory.systemTemp.createTempSync('resolver_partial_'),
      commit: 'ok',
    );
  }
}

void main() {
  group('PluginResolver', () {
    late Directory marketplace;
    late Directory wingspan;

    void writeFile(Directory root, String relativePath, String content) {
      File(p.join(root.path, relativePath))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    setUp(() {
      marketplace = Directory.systemTemp.createTempSync('resolver_market_');
      wingspan = Directory.systemTemp.createTempSync('resolver_wingspan_');
    });

    tearDown(() {
      marketplace.deleteSync(recursive: true);
      wingspan.deleteSync(recursive: true);
    });

    test(
      'resolves plugins, flattening mcp servers, skills, and agents',
      () async {
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
{"mcpServers": {"wingspan": {"command": "dart", "args": ["run"]}}}
''');
        writeFile(wingspan, 'skills/plan/SKILL.md', '''
---
name: plan
description: Plan the work.
---
''');
        writeFile(wingspan, 'agents/planner.md', '''
---
name: planner
description: Plans things.
---
''');

        final resolver = PluginResolver(
          fetcher: FakePluginFetcher(
            marketplace: marketplace,
            plugins: {'VeryGoodOpenSource/vgv-wingspan': wingspan},
          ),
        );

        final result = await resolver.resolve();

        expect(result.plugins, hasLength(1));
        final plugin = result.plugins.single;
        expect(plugin.name, 'vgv-wingspan');
        expect(plugin.repo, 'VeryGoodOpenSource/vgv-wingspan');
        expect(plugin.commit, 'fixturecommit-VeryGoodOpenSource/vgv-wingspan');
        expect(plugin.directory.path, wingspan.path);

        expect(result.mcpServers.keys, ['wingspan']);
        expect(result.mcpServers['wingspan']!.command, 'dart');
        expect(result.skills.single.name, 'plan');
        expect(plugin.skills.single.source, p.join('skills', 'plan'));
        expect(result.agents.single.name, 'planner');
      },
    );

    test('returns empty when the manifest file is absent', () async {
      final resolver = PluginResolver(
        fetcher: FakePluginFetcher(marketplace: marketplace),
      );

      final result = await resolver.resolve();

      expect(result.plugins, isEmpty);
      expect(result.mcpServers, isEmpty);
      expect(result.skills, isEmpty);
      expect(result.agents, isEmpty);
    });

    test(
      'propagates a mid-resolution failure without returning partial results',
      () async {
        writeFile(marketplace, '.claude-plugin/marketplace.json', '''
{
  "plugins": [
    {
      "name": "first",
      "source": {"source": "github", "repo": "owner/first"}
    },
    {
      "name": "second",
      "source": {"source": "github", "repo": "owner/second"}
    }
  ]
}
''');

        final resolver = PluginResolver(
          fetcher: _PartiallyFailingFetcher(marketplace),
        );

        await expectLater(resolver.resolve(), throwsA(isA<Exception>()));
      },
    );
  });
}
