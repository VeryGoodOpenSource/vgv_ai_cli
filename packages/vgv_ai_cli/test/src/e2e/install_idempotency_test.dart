import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/install_command.dart';
import 'package:vgv_ai_cli/src/document/markdown_sections.dart';
import 'package:vgv_ai_cli/src/manifest/manifest_auditor.dart';
import 'package:vgv_ai_cli/src/manifest/manifest_store.dart';
import 'package:vgv_ai_cli/src/manifest/model/reverse_outcome.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/model/planned_change.dart';
import 'package:vgv_ai_cli/src/version.dart';

class _MockLogger extends Mock implements Logger;

class _MockProgress extends Mock implements Progress;

class _MockPubUpdater extends Mock implements PubUpdater;

class _FakeSource extends PluginSource {
  const new(this.directory);

  final Directory directory;

  @override
  Future<PluginResolution> resolve(PluginRef ref) async =>
      ResolvedPlugin(directory);
}

class _FakeParser implements PluginParser {
  const new(this.assets);

  final PluginAssets assets;

  @override
  PluginAssets parse(Directory root) => assets;
}

/// Installs the plugins into every harness with the real translator and
/// reconciler, the way a user running `vgv_ai install` twice would.
void main() {
  group('install idempotency', () {
    late FileSystem fs;
    late Directory home;
    late Logger logger;
    late PluginAssets assets;

    setUp(() {
      fs = MemoryFileSystem.test();
      home = fs.directory('/home/dev')..createSync(recursive: true);
      logger = _MockLogger();
      when(() => logger.progress(any())).thenReturn(_MockProgress());

      final skill = fs.directory('/plugin/skills/green-gate');
      skill.childFile('SKILL.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nname: green-gate\n---\nRun the gate.\n');
      fs.file(p.join(skill.path, 'scripts', 'gate.sh'))
        ..createSync(recursive: true)
        ..writeAsStringSync(r'sh ${CLAUDE_SKILL_DIR}/scripts/check.sh');

      assets = PluginAssets(
        skills: [
          SkillAsset(
            name: 'green-gate',
            description: 'Drives a package to green.',
            body: 'Run the gate.',
            userInvocable: true,
            allowedTools: const ['Bash'],
            portableFrontmatter: const {'name': 'green-gate'},
            directory: skill,
          ),
        ],
        agents: const [
          AgentAsset(
            name: 'reviewer',
            description: 'Reviews code.',
            body: 'Review the diff.',
            skills: ['green-gate'],
          ),
        ],
        mcpServers: const [
          LocalMCPServer(name: 'dart', command: 'dart', args: ['mcp-server']),
          RemoteMCPServer(name: 'docs', url: 'https://docs.example.com/mcp'),
        ],
      );
    });

    Future<int> install() {
      final pubUpdater = _MockPubUpdater();
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => packageVersion);

      return VgvAiCliCommandRunner(
        logger: logger,
        pubUpdater: pubUpdater,
        installCommand: InstallCommand(
          logger: logger,
          home: home,
          pluginSource: _FakeSource(fs.directory('/plugin')),
          parser: _FakeParser(assets),
        ),
      ).run([
        'install',
        for (final harness in Harness.values) ...['--only', harness.name],
      ]);
    }

    /// Every file under home, by path, to the hash of its bytes.
    Map<String, String> snapshot() => {
      for (final entity in home.listSync(recursive: true))
        if (entity is File)
          entity.path: sha256.convert(entity.readAsBytesSync()).toString(),
    };

    File file(String relative) => fs.file(p.join(home.path, relative));

    File seed(String relative, String contents) => file(relative)
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

    int count(String text, String pattern) => pattern.allMatches(text).length;

    test('a second run changes nothing', () async {
      expect(await install(), ExitCode.success.code);
      final first = snapshot();
      clearInteractions(logger);

      expect(await install(), ExitCode.success.code);

      expect(snapshot(), first);
      verify(() => logger.info('Everything is already up to date.')).called(1);
    });

    test("keeps the user's content and adds no duplicates", () async {
      const agents = '# Mine\n\nBe terse.\n';
      const config =
          '# My Codex setup\n'
          'model = "gpt-5" # explicit\n'
          '\n'
          '[mcp_servers.mine]\n'
          'command = "mine"\n';
      seed('.gemini/AGENTS.md', agents);
      seed('.codex/config.toml', config);
      seed(
        '.gemini/settings.json',
        jsonEncode({'model': 'pro', 'theme': 'dark'}),
      );

      await install();
      final first = snapshot();
      await install();

      expect(snapshot(), first);

      final instructions = file('.gemini/AGENTS.md').readAsStringSync();
      expect(instructions, startsWith(agents));
      expect(count(instructions, sectionStart('instructions')), 1);
      expect(count(instructions, sectionEnd('instructions')), 1);

      final toml = file('.codex/config.toml').readAsStringSync();
      expect(toml, startsWith(config));
      expect(count(toml, '[mcp_servers.dart]'), 1);
      expect(count(toml, '[mcp_servers.docs]'), 1);
      expect(TomlDocument.parse(toml).toMap(), containsPair('model', 'gpt-5'));

      final settings = jsonDecode(
        file('.gemini/settings.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(settings, containsPair('model', 'pro'));
      expect(settings, containsPair('theme', 'dark'));
      expect(
        settings['mcpServers'],
        containsPair('dart', isA<Map<String, dynamic>>()),
      );
    });

    test('records every file under the harness it configures', () async {
      await install();

      final entries = ManifestStore(home).load()!.entries;
      Harness? ownerOf(String relative) =>
          entries.singleWhere((e) => e.path == file(relative).path).owner;

      expect(ownerOf('.agents/skills/green-gate/SKILL.md'), isNull);
      expect(ownerOf('.gemini/settings.json'), Harness.gemini);
      expect(ownerOf('.codex/config.toml'), Harness.codex);
      expect(ownerOf('.pi/agent/AGENTS.md'), Harness.pi);
      expect(entries.map((e) => e.path), everyElement(startsWith(home.path)));
    });

    test('reversing leaves the user as they were, and install '
        'lands where it did', () async {
      const agents = '# Mine\n\nBe terse.\n';
      const config = '# My Codex setup\nmodel = "gpt-5" # explicit\n';
      final settings = DocumentFormat.json.encode({'model': 'pro'});
      seed('.gemini/AGENTS.md', agents);
      seed('.codex/config.toml', config);
      seed('.gemini/settings.json', settings);
      final before = snapshot();

      await install();
      final installed = snapshot();
      final store = ManifestStore(home);
      final reversed = const ManifestAuditor().reverse(store.load()!, fs);
      store.save(reversed.manifest);

      expect(store.file.existsSync(), isFalse);
      expect(
        reversed.entries.map((r) => r.outcome),
        everyElement(ReverseOutcome.removed),
      );
      expect(snapshot(), before);

      await install();
      expect(snapshot(), installed);
    });

    test('edits a TOML table the user already has in place', () async {
      seed(
        '.codex/config.toml',
        '[mcp_servers.dart]\n'
            '# pinned by me\n'
            'command = "dart"\n'
            'args = ["--verbose"] # mine\n',
      );

      await install();
      final first = snapshot();
      await install();

      expect(snapshot(), first);

      final toml = file('.codex/config.toml').readAsStringSync();
      expect(toml, contains('# pinned by me\n'));
      expect(toml, contains('# mine\n'));
      expect(count(toml, '[mcp_servers.dart]'), 1);
      expect(
        TomlDocument.parse(toml).toMap()['mcp_servers'],
        containsPair('dart', containsPair('args', ['--verbose', 'mcp-server'])),
      );
    });
  });
}
