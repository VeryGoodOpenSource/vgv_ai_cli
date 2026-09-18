import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/install_command.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_fetcher.dart';

import '../plugins/fake_plugin_fetcher.dart';

class _MockLogger extends Mock implements Logger;

class _MockProgress extends Mock implements Progress;

class _ThrowingFetcher implements PluginFetcher {
  @override
  Future<FetchedRepo> fetchMarketplace() async => throw Exception('boom');

  @override
  Future<FetchedRepo> fetchPlugin(String repo, {String? ref, String? commit}) =>
      throw Exception('boom');
}

void main() {
  group('install', () {
    late Logger logger;
    late Progress progress;
    late Directory home;
    late Directory marketplace;
    late Directory wingspan;

    void writeFile(Directory root, String relativePath, String content) {
      File(p.join(root.path, relativePath))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    setUp(() {
      logger = _MockLogger();
      progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);

      home = Directory.systemTemp.createTempSync('install_cmd_home_');
      marketplace = Directory.systemTemp.createTempSync('install_cmd_market_');
      wingspan = Directory.systemTemp.createTempSync('install_cmd_wingspan_');

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
''');
    });

    tearDown(() {
      home.deleteSync(recursive: true);
      marketplace.deleteSync(recursive: true);
      wingspan.deleteSync(recursive: true);
    });

    FakePluginFetcher fetcher() => FakePluginFetcher(
      marketplace: marketplace,
      plugins: {'VeryGoodOpenSource/vgv-wingspan': wingspan},
    );

    Future<int?> runInstall(
      List<String> args, {
      PluginFetcher? withFetcher,
      Directory? withHome,
      Map<String, String>? environment,
    }) {
      final runner = CommandRunner<int>('vgv_ai', 'test')
        ..addCommand(
          InstallCommand(
            logger: logger,
            fetcher: withFetcher,
            home: withHome,
            environment: environment,
          ),
        );
      return runner.run(['install', ...args]);
    }

    test('errors when no harness is selected', () async {
      final exitCode = await runInstall([]);

      expect(exitCode, ExitCode.usage.code);
      verify(
        () => logger.err(any(that: contains('Select at least one harness'))),
      ).called(1);
    });

    test('installs the selected harness and reports success', () async {
      final exitCode = await runInstall(
        ['--pi'],
        withFetcher: fetcher(),
        withHome: home,
      );

      expect(exitCode, ExitCode.success.code);
      expect(
        File(p.join(home.path, '.pi', 'agent', 'settings.json')).existsSync(),
        isTrue,
      );
      verify(() => progress.complete(any())).called(1);
    });

    test('--all installs every harness', () async {
      final exitCode = await runInstall(
        ['--all'],
        withFetcher: fetcher(),
        withHome: home,
      );

      expect(exitCode, ExitCode.success.code);
      expect(
        File(p.join(home.path, '.claude', 'settings.json')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(home.path, '.codex', 'config.toml')).existsSync(),
        isTrue,
      );
    });

    test('honors --skills-root', () async {
      final skillsRoot = Directory(p.join(home.path, 'custom-skills'));

      await runInstall(
        ['--pi', '--skills-root', skillsRoot.path],
        withFetcher: fetcher(),
        withHome: home,
      );

      expect(
        File(p.join(skillsRoot.path, 'skills-lock.json')).existsSync(),
        isTrue,
      );
    });

    test('resolves home from the environment when not injected', () async {
      final exitCode = await runInstall(
        ['--pi'],
        withFetcher: fetcher(),
        environment: {'HOME': home.path},
      );

      expect(exitCode, ExitCode.success.code);
      expect(
        File(p.join(home.path, '.pi', 'agent', 'settings.json')).existsSync(),
        isTrue,
      );
    });

    test('fails when the home directory cannot be resolved', () async {
      final exitCode = await runInstall(
        ['--pi'],
        withFetcher: fetcher(),
        environment: const {},
      );

      expect(exitCode, ExitCode.software.code);
      verify(() => logger.err(any(that: contains('home directory')))).called(1);
      verify(() => progress.fail()).called(1);
    });

    test('reports failure when resolution throws', () async {
      final exitCode = await runInstall(
        ['--pi'],
        withFetcher: _ThrowingFetcher(),
        withHome: home,
      );

      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail()).called(1);
      verify(() => logger.err(any(that: contains('boom')))).called(1);
    });
  });
}
