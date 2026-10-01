import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/install_command.dart';
import 'package:vgv_ai_cli/src/harness/harness_detector.dart';
import 'package:vgv_ai_cli/src/harness/translate/translate.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/version.dart';

class _MockLogger extends Mock implements Logger;

class _MockProgress extends Mock implements Progress;

class _MockDetector extends Mock implements HarnessDetector;

class _MockPubUpdater extends Mock implements PubUpdater;

class _FakeSource extends PluginSource {
  const new(this.resolution);

  final PluginResolution resolution;

  @override
  Future<PluginResolution> resolve(PluginRef ref) async => resolution;
}

class _FakeParser implements PluginParser {
  const new(this.assets);

  final PluginAssets assets;

  @override
  PluginAssets parse(Directory root) => assets;
}

class _ThrowingParser implements PluginParser {
  const new();

  @override
  PluginAssets parse(Directory root) =>
      throw const PluginParseException('/plugin/agents/a.md', 'bad name');
}

/// A [Translator] whose plan is supplied per test, and which records
/// what it was asked to translate.
class _FakeTranslator extends Fake implements Translator {
  TranslationPlan plan = const TranslationPlan();

  Set<Harness>? selected;
  PluginAssets? assets;
  Directory? home;

  @override
  Future<TranslationPlan> translate({
    required PluginAssets assets,
    required Directory home,
    required Set<Harness> selected,
  }) async {
    this.assets = assets;
    this.home = home;
    this.selected = selected;
    return plan;
  }
}

PluginAssets _assets(FileSystem fs) => PluginAssets(
  skills: [
    SkillAsset(
      name: 'green-gate',
      description: 'Enforces the green gate.',
      body: 'body',
      userInvocable: true,
      allowedTools: const ['Bash'],
      portableFrontmatter: const {'name': 'green-gate'},
      directory: fs.directory('/plugin/skills/green-gate')
        ..createSync(recursive: true),
    ),
  ],
  agents: const [
    AgentAsset(
      name: 'reviewer',
      description: 'Reviews code.',
      body: 'body',
      skills: [],
    ),
  ],
  mcpServers: const [],
);

void main() {
  setUpAll(() => registerFallbackValue(Harness.claude));

  group('install', () {
    late Logger logger;
    late Progress progress;
    late HarnessDetector detector;
    late FileSystem fs;
    late Directory home;
    late _FakeTranslator translator;
    late PubUpdater pubUpdater;

    setUp(() {
      logger = _MockLogger();
      progress = _MockProgress();
      detector = _MockDetector();
      fs = MemoryFileSystem.test();
      home = fs.directory('/home/dev')..createSync(recursive: true);
      translator = _FakeTranslator();
      pubUpdater = _MockPubUpdater();

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => packageVersion);
    });

    Future<int> runThroughRunner(InstallCommand command, List<String> args) =>
        VgvAiCliCommandRunner(
          logger: logger,
          pubUpdater: pubUpdater,
          installCommand: command,
        ).run(['install', ...args]);

    Future<int> runInstall(
      List<String> args, {
      PluginSource? source,
      PluginParser? parser,
      Translator? using,
    }) => runThroughRunner(
      InstallCommand(
        logger: logger,
        home: home,
        detector: detector,
        pluginSource:
            source ?? _FakeSource(ResolvedPlugin(fs.directory('/plugin'))),
        parser: parser ?? _FakeParser(_assets(fs)),
        translator: using ?? translator,
      ),
      args,
    );

    File homeFile(String relativePath) =>
        fs.file(fs.path.join(home.path, relativePath));

    PlannedChange ownChange(
      Harness? harness,
      String relativePath,
      String contents,
    ) => PlannedChange.text(
      file: homeFile(relativePath),
      contents: contents,
      harness: harness,
    );

    void detectAll(Iterable<Harness> installed) {
      when(() => detector.detect(any())).thenAnswer(
        (invocation) async =>
            installed.contains(invocation.positionalArguments.single)
            ? const HarnessDetection.detected(version: '1.0.0')
            : const HarnessDetection.missing(),
      );
    }

    group('selection', () {
      test(
        '--only bypasses detection and selects the named harnesses',
        () async {
          final exitCode = await runInstall([
            '--only',
            'claude',
            '--only',
            'gemini',
          ]);

          expect(exitCode, ExitCode.success.code);
          expect(translator.selected, {Harness.claude, Harness.gemini});
          verifyNever(() => detector.detect(any()));
        },
      );

      test('--only cannot be combined with a harness flag', () async {
        final exitCode = await runInstall([
          '--only',
          'claude',
          '--no-gemini',
          '--codex',
        ]);

        expect(exitCode, ExitCode.usage.code);
        expect(translator.selected, isNull);
        verify(
          () => logger.err(
            '--only cannot be combined with --[no-]gemini, --[no-]codex.',
          ),
        ).called(1);
      });

      test('defaults to enabled and detected harnesses', () async {
        detectAll([Harness.claude]);

        final exitCode = await runInstall([]);

        expect(exitCode, ExitCode.success.code);
        expect(translator.selected, {Harness.claude});
        verify(() => logger.info(any(that: contains('Gemini (not installed)'))))
            .called(1);
      });

      test('--no-<harness> opts a detected harness out', () async {
        detectAll(Harness.values);

        final exitCode = await runInstall(['--no-claude']);

        expect(exitCode, ExitCode.success.code);
        expect(translator.selected, isNot(contains(Harness.claude)));
        verify(() => logger.detail('Skipping Claude Code: opted out'))
            .called(1);
        verifyNever(() => detector.detect(Harness.claude));
      });

      test('an unknown --only harness is a usage error', () async {
        final exitCode = await runInstall(['--only', 'bogus']);

        expect(exitCode, ExitCode.usage.code);
        expect(translator.selected, isNull);
        verify(
          () => logger.err(any(that: contains('"bogus" is not an allowed'))),
        ).called(1);
      });

      test('an empty selection is a usage error', () async {
        detectAll(const []);

        final exitCode = await runInstall([]);

        expect(exitCode, ExitCode.usage.code);
        expect(translator.selected, isNull);
        verify(() => logger.err(any(that: contains('No harness selected'))))
            .called(1);
      });
    });

    group('resolution', () {
      test(
        'aborts with unavailable when a plugin cannot be resolved',
        () async {
          final exitCode = await runInstall(
            ['--only', 'claude'],
            source: const _FakeSource(
              UnavailablePlugin(['no cache', 'no git']),
            ),
          );

          expect(exitCode, ExitCode.unavailable.code);
          expect(translator.selected, isNull);
          verify(() => progress.fail(any(that: contains('Could not resolve'))))
              .called(1);
          verify(() => logger.err('  - no cache')).called(1);
          verify(() => logger.err('  - no git')).called(1);
        },
      );

      test('aborts with unavailable when a plugin cannot be parsed', () async {
        final exitCode = await runInstall([
          '--only',
          'claude',
        ], parser: const _ThrowingParser());

        expect(exitCode, ExitCode.unavailable.code);
        expect(translator.selected, isNull);
        verify(() => progress.fail(any(that: contains('Could not parse'))))
            .called(1);
        verify(
          () => logger.err('  - Could not parse /plugin/agents/a.md: bad name'),
        ).called(1);
      });

      test('merges every plugin and translates the result', () async {
        await runInstall(['--only', 'codex']);

        // The fake parser answers every pinned plugin with the same assets,
        // and the merge keeps the first of each name.
        verify(() => progress.complete('Resolved 1 skills and 1 agents'))
            .called(1);
        expect(translator.assets!.skills.single.name, 'green-gate');
        expect(translator.home, home);
      });
    });

    group('report', () {
      test('warns with every note, labelled by its owner', () async {
        translator.plan = const TranslationPlan(
          shared: TranslationResult(
            changes: [],
            notes: [TranslationNote(subject: 'a', reason: 'shared reason')],
          ),
          harnesses: {
            Harness.pi: TranslationResult(
              changes: [],
              notes: [TranslationNote(subject: 'b', reason: 'pi reason')],
            ),
          },
        );

        await runInstall(['--only', 'pi']);

        verify(() => logger.warn('Shared: a: shared reason')).called(1);
        verify(() => logger.warn('Pi: b: pi reason')).called(1);
      });

      test('writes every change and counts them per owner', () async {
        translator.plan = TranslationPlan(
          shared: TranslationResult(
            changes: [ownChange(null, '.agents/skills/a/SKILL.md', 'a')],
          ),
          harnesses: {
            Harness.codex: TranslationResult(
              changes: [
                ownChange(Harness.codex, '.codex/agents/a.toml', 'a'),
                ownChange(Harness.codex, '.codex/agents/b.toml', 'b'),
              ],
            ),
          },
        );

        final exitCode = await runInstall(['--only', 'codex']);

        expect(exitCode, ExitCode.success.code);
        expect(homeFile('.codex/agents/b.toml').readAsStringSync(), 'b');
        verify(() => logger.info('  Shared: 1 file(s)')).called(1);
        verify(() => logger.info('  Codex: 2 file(s)')).called(1);
        verify(
          () => logger.detail('Wrote ${homeFile('.codex/agents/b.toml').path}'),
        ).called(1);
        verify(
          () => logger.info(
            '\nRestart your coding agents to pick up the changes.',
          ),
        ).called(1);
      });

      test('--check writes nothing', () async {
        translator.plan = TranslationPlan(
          harnesses: {
            Harness.claude: TranslationResult(
              changes: [ownChange(Harness.claude, '.claude/a.md', 'a')],
            ),
          },
        );

        final exitCode = await runInstall(['--only', 'claude', '--check']);

        expect(exitCode, ExitCode.success.code);
        expect(homeFile('.claude/a.md').existsSync(), isFalse);
        verify(
          () => logger.info('Would write ${homeFile('.claude/a.md').path}'),
        ).called(1);
        verify(() => logger.info('  Claude Code: 1 file(s)')).called(1);
        verify(() => logger.info(any(that: contains('nothing was written'))))
            .called(1);
      });

      test('exits with an I/O error when a file cannot be written', () async {
        fs.directory(homeFile('.claude/a.md').path).createSync(recursive: true);
        translator.plan = TranslationPlan(
          harnesses: {
            Harness.claude: TranslationResult(
              changes: [ownChange(Harness.claude, '.claude/a.md', 'a')],
            ),
          },
        );

        final exitCode = await runInstall(['--only', 'claude']);

        expect(exitCode, ExitCode.ioError.code);
        verifyNever(() => logger.info('Everything is already up to date.'));
        verify(
          () => logger.err(
            any(
              that: startsWith(
                'Could not update ${homeFile('.claude/a.md').path}: ',
              ),
            ),
          ),
        ).called(1);
      });

      test('warns about a config it cannot parse, without --force', () async {
        homeFile('.gemini/settings.json')
          ..createSync(recursive: true)
          ..writeAsStringSync('{ // mine\n}');
        translator.plan = TranslationPlan(
          harnesses: {
            Harness.gemini: TranslationResult(
              changes: [
                PlannedChange.text(
                  file: homeFile('.gemini/settings.json'),
                  contents: '{"a": 1}',
                  harness: Harness.gemini,
                  mode: ChangeMode.mergeJson,
                ),
              ],
            ),
          },
        );

        final exitCode = await runInstall(['--only', 'gemini']);

        expect(exitCode, ExitCode.success.code);
        verify(
          () => logger.warn(
            any(that: contains('could not be parsed. If it has comments')),
          ),
        ).called(1);
        verifyNever(() => logger.info(any(that: contains('--force'))));
      });

      test('keeps a file of the user where VGV owns one', () async {
        homeFile('.codex/prompts/plan.md')
          ..createSync(recursive: true)
          ..writeAsStringSync('mine');
        translator.plan = TranslationPlan(
          harnesses: {
            Harness.codex: TranslationResult(
              changes: [
                ownChange(Harness.codex, '.codex/prompts/plan.md', 'vgv'),
              ],
            ),
          },
        );

        await runInstall(['--only', 'codex']);

        expect(homeFile('.codex/prompts/plan.md').readAsStringSync(), 'mine');
        verify(
          () => logger.warn(
            'Kept your values in ${homeFile('.codex/prompts/plan.md').path}',
          ),
        ).called(1);
      });

      test('reports when everything is already up to date', () async {
        homeFile('.claude/a.md')
          ..createSync(recursive: true)
          ..writeAsStringSync('same');
        translator.plan = TranslationPlan(
          harnesses: {
            Harness.claude: TranslationResult(
              changes: [ownChange(Harness.claude, '.claude/a.md', 'same')],
            ),
          },
        );

        await runInstall(['--only', 'claude']);

        verify(() => logger.info('Everything is already up to date.'))
            .called(1);
        verifyNever(() => logger.warn(any()));
      });
    });

    group('with the real translator', () {
      File settings() => homeFile('.claude/settings.json');

      String pluginKey() => '${vgvPlugins.first.name}@$vgvMarketplaceName';

      void userDisabledThePlugin() {
        settings()
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'enabledPlugins': {pluginKey(): false},
            }),
          );
      }

      Map<String, dynamic> enabledPlugins() =>
          (jsonDecode(settings().readAsStringSync())
                  as Map<String, dynamic>)['enabledPlugins']
              as Map<String, dynamic>;

      test('points Claude Code at the marketplace', () async {
        final exitCode = await runInstall([
          '--only',
          'claude',
        ], using: const Translator());

        expect(exitCode, ExitCode.success.code);
        expect(enabledPlugins()[pluginKey()], isTrue);
        verify(() => logger.info('  Claude Code: 1 file(s)')).called(1);
      });

      test("keeps a value the user set and says how to take VGV's", () async {
        userDisabledThePlugin();

        await runInstall(['--only', 'claude'], using: const Translator());

        expect(enabledPlugins()[pluginKey()], isFalse);
        verify(() => logger.warn('Kept your values in ${settings().path}'))
            .called(1);
        verify(() => logger.info(any(that: contains('--force')))).called(1);
      });

      test("--force takes VGV's value", () async {
        userDisabledThePlugin();

        await runInstall([
          '--only',
          'claude',
          '--force',
        ], using: const Translator());

        expect(enabledPlugins()[pluginKey()], isTrue);
        verifyNever(() => logger.warn(any()));
      });
    });

    test('describes itself', () {
      final command = InstallCommand(logger: logger);

      expect(command.name, InstallCommand.commandName);
      expect(command.description, contains('Configure'));
    });

    group('default collaborators', () {
      test("the home is the current user's", () {
        final environment = Platform.environment;

        expect(
          InstallCommand(logger: logger).home?.path,
          environment['HOME'] ?? environment['USERPROFILE'],
        );
      });

      test('the home falls back to USERPROFILE', () {
        expect(
          InstallCommand.userHome(const {'USERPROFILE': r'C:\Users\dev'})?.path,
          r'C:\Users\dev',
        );
      });

      test('a missing home is a config error', () async {
        final exitCode = await runThroughRunner(
          InstallCommand(logger: logger, environment: const {}),
          ['--only', 'claude'],
        );

        expect(exitCode, ExitCode.config.code);
        expect(translator.selected, isNull);
        verify(
          () => logger.err(any(that: contains('Could not find your home'))),
        ).called(1);
      });

      test('plugins resolve from the Claude Code cache under home', () async {
        final exitCode = await runThroughRunner(
          InstallCommand(logger: logger, home: home),
          ['--only', 'claude'],
        );

        expect(exitCode, ExitCode.unavailable.code);
        verify(
          () => logger.err(
            any(that: contains(fs.path.join(home.path, '.claude'))),
          ),
        ).called(1);
      });
    });
  });
}
