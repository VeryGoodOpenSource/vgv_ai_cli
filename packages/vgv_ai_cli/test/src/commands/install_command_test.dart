import 'dart:convert';
import 'dart:io' show Platform, ProcessException, ProcessResult, stdin;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/commands.dart';
import 'package:vgv_ai_cli/src/detect/detect.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

import '../../helpers/test_runner.dart';

class _MockDetector extends Mock implements HarnessDetector;

/// A [ManifestAuditor] that fails to reverse every entry it is given.
class const _FailingAuditor() extends ManifestAuditor {
  @override
  Reversal reverse(
    InstallManifest manifest,
    FileSystem fileSystem, {
    Set<Harness?>? owners,
    bool force = false,
    bool dryRun = false,
  }) => Reversal(
    entries: [
      for (final entry in manifest.entries)
        ReversedEntry.failed(entry, error: 'Permission denied'),
    ],
    manifest: manifest,
  );
}

class const _FakeParser(final PluginAssets assets) implements PluginParser {
  @override
  PluginAssets parse(Directory root, {String? rootReference}) => assets;
}

class const _ThrowingParser() implements PluginParser {
  @override
  PluginAssets parse(Directory root, {String? rootReference}) =>
      throw const PluginParseException('/plugin/agents/a.md', 'bad name');
}

/// A [Translator] whose plan is supplied per test, and which records
/// what it was asked to translate.
class _FakeTranslator extends Fake implements Translator {
  TranslationPlan plan = const TranslationPlan();

  Set<Harness>? selected;
  PluginAssets? assets;
  Scope? scope;

  @override
  Future<TranslationPlan> translate({
    required PluginAssets assets,
    required Scope scope,
    required Set<Harness> selected,
    List<PluginDirectory> plugins = const [],
  }) async {
    this.assets = assets;
    this.scope = scope;
    this.selected = selected;
    return plan;
  }
}

void main() {
  group(InstallCommand, () {
    PluginAssets assets(FileSystem fs) => PluginAssets(
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

    setUpAll(() => registerFallbackValue(Harness.claude));

    late TestRunner runner;
    late Logger logger;
    late Progress progress;
    late HarnessDetector detector;
    late FileSystem fs;
    late Directory home;
    late Directory project;
    late _FakeTranslator translator;

    /// A directory that cannot be deleted, or null when every one can.
    String? undeletable;

    setUp(() {
      runner = TestRunner();
      logger = runner.logger;
      progress = runner.progress;
      detector = _MockDetector();
      undeletable = null;
      fs = MemoryFileSystem.test(
        opHandle: (path, operation) {
          if (path == undeletable && operation == FileSystemOp.delete) {
            throw FileSystemException('Cannot delete', path);
          }
        },
      );
      home = fs.directory('/home/dev')..createSync(recursive: true);
      project = fs.directory('/work/app')..createSync(recursive: true);
      translator = _FakeTranslator();
    });

    /// Asks the plugin picker, matching any arguments.
    List<PluginRef> pickPlugins() => logger.chooseAny<PluginRef>(
      any(),
      choices: any(named: 'choices'),
      defaultValues: any(named: 'defaultValues'),
      display: any(named: 'display'),
    );

    /// Clones every plugin by creating its target, since there is no
    /// Claude Code cache under [home].
    Future<ProcessResult> clone(
      String executable,
      List<String> arguments, {
      bool runInShell = false,
    }) async {
      fs.directory(arguments.last).createSync(recursive: true);
      return ProcessResult(0, 0, '', '');
    }

    Future<int> runThroughRunner(InstallCommand command, List<String> args) =>
        runner.run(['install', ...args], installCommand: command);

    Future<int> runInstall(
      List<String> args, {
      RunProcess? runProcess,
      PluginParser? parser,
      Translator? using,
      bool hasTerminal = false,
      List<PluginRef> pins = vgvPlugins,
      ManifestAuditor auditor = const ManifestAuditor(),
    }) => runThroughRunner(
      InstallCommand(
        logger: logger,
        home: home,
        detector: detector,
        resolver: PluginResolver(
          runProcess: runProcess ?? clone,
          parser: parser ?? _FakeParser(assets(fs)),
          plugins: pins,
        ),
        auditor: auditor,
        translator: using ?? translator,
        hasTerminal: hasTerminal,
        workingDirectory: project,
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

    group('--plugin', () {
      // The manifest is only written once something is, so every run here
      // writes one file.
      setUp(() {
        translator.plan = TranslationPlan(
          harnesses: {
            Harness.claude: TranslationResult(
              changes: [ownChange(Harness.claude, '.claude/a.md', 'a')],
            ),
          },
        );
      });

      test('installs just the plugins it names', () async {
        final exitCode = await runInstall([
          '--only',
          'claude',
          '--plugin',
          vgvPlugins.first.name,
        ]);

        expect(exitCode, ExitCode.success.code);
        expect(translator.assets?.plugins, [vgvPlugins.first]);
        expect(ManifestStore(home).load()!.plugins, {
          Harness.claude: {vgvPlugins.first.name: vgvPlugins.first.version},
        });
      });

      test('keeps the recorded version of a plugin it skips', () async {
        final skipped = vgvPlugins.last;
        await runInstall(['--only', 'claude']);
        final store = ManifestStore(home);
        store.save(
          store.load()!.withPlugins({
            Harness.claude: {
              for (final plugin in vgvPlugins) plugin.name: plugin.version,
              skipped.name: '0.0.1',
            },
          }),
        );

        await runInstall([
          '--only',
          'claude',
          '--plugin',
          vgvPlugins.first.name,
        ]);

        expect(store.load()!.plugins, {
          Harness.claude: {
            for (final plugin in vgvPlugins) plugin.name: plugin.version,
            skipped.name: '0.0.1',
          },
        });
      });

      group('in a terminal', () {
        /// What the picker was given as its [argument], such as `choices`.
        T asked<T>(String argument) {
          U match<U>(String name) => name == argument
              ? captureAny<U>(named: name)
              : any<U>(named: name);

          return verify(
                () => logger.chooseAny<PluginRef>(
                  any(),
                  choices: match('choices'),
                  defaultValues: match('defaultValues'),
                  display: match('display'),
                ),
              ).captured.single
              as T;
        }

        test('installs the plugins the user picks', () async {
          when(pickPlugins).thenReturn([vgvPlugins.first]);

          final exitCode = await runInstall([
            '--only',
            'claude',
          ], hasTerminal: true);

          expect(exitCode, ExitCode.success.code);
          expect(translator.assets?.plugins, [vgvPlugins.first]);
          expect(ManifestStore(home).load()!.plugins, {
            Harness.claude: {vgvPlugins.first.name: vgvPlugins.first.version},
          });
        });

        test('offers every pinned plugin', () async {
          when(pickPlugins).thenReturn(vgvPlugins);

          await runInstall(['--only', 'claude'], hasTerminal: true);

          expect(asked<List<PluginRef>>('choices'), vgvPlugins);
        });

        test('picks every pinned plugin on a first run', () async {
          when(pickPlugins).thenReturn(vgvPlugins);

          await runInstall(['--only', 'claude'], hasTerminal: true);

          expect(asked<List<PluginRef>>('defaultValues'), vgvPlugins);
        });

        test('shows each plugin by name', () async {
          when(pickPlugins).thenReturn(vgvPlugins);

          await runInstall(['--only', 'claude'], hasTerminal: true);

          expect(
            asked<String Function(PluginRef)>('display')(vgvPlugins.first),
            vgvPlugins.first.name,
          );
        });

        test('picks the plugins already installed on a rerun', () async {
          when(pickPlugins).thenReturn([vgvPlugins.last]);
          await runInstall(['--only', 'claude'], hasTerminal: true);
          clearInteractions(logger);

          await runInstall(['--only', 'claude'], hasTerminal: true);

          expect(asked<List<PluginRef>>('defaultValues'), [vgvPlugins.last]);
        });

        test('says a plugin left out on a rerun stays installed', () async {
          when(pickPlugins).thenReturn(vgvPlugins);
          await runInstall(['--only', 'claude'], hasTerminal: true);
          when(pickPlugins).thenReturn([vgvPlugins.last]);

          await runInstall(['--only', 'claude'], hasTerminal: true);

          verify(
            () => logger.info(
              any(
                that: allOf(
                  contains('Keeping ${vgvPlugins.first.name}'),
                  contains('uninstall'),
                ),
              ),
            ),
          ).called(1);
        });

        test('says nothing is kept on a first run', () async {
          when(pickPlugins).thenReturn([vgvPlugins.last]);

          await runInstall(['--only', 'claude'], hasTerminal: true);

          verifyNever(() => logger.info(any(that: startsWith('Keeping'))));
        });

        test('rejects picking no plugin', () async {
          when(pickPlugins).thenReturn(const []);

          final exitCode = await runInstall([
            '--only',
            'claude',
          ], hasTerminal: true);

          expect(exitCode, ExitCode.usage.code);
          expect(translator.assets, isNull);
          verify(() => logger.err(any(that: contains('No plugin selected'))))
              .called(1);
          verifyNever(() => logger.progress('Resolving plugins'));
        });

        test('does not ask when --plugin names the plugins', () async {
          await runInstall([
            '--only',
            'claude',
            '--plugin',
            vgvPlugins.first.name,
          ], hasTerminal: true);

          expect(translator.assets?.plugins, [vgvPlugins.first]);
          verifyNever(pickPlugins);
        });
      });

      test('installs every pinned plugin outside a terminal', () async {
        final exitCode = await runInstall(['--only', 'claude']);

        expect(exitCode, ExitCode.success.code);
        expect(translator.assets?.plugins, vgvPlugins);
        verifyNever(pickPlugins);
      });

      test('rejects a plugin it does not pin', () async {
        final exitCode = await runInstall([
          '--only',
          'claude',
          '--plugin',
          'vgv-unknown',
        ]);

        expect(exitCode, ExitCode.usage.code);
        expect(translator.assets, isNull);
      });
    });

    group('--refresh', () {
      setUp(() {
        translator.plan = TranslationPlan(
          harnesses: {
            Harness.claude: TranslationResult(
              changes: [ownChange(Harness.claude, '.claude/a.md', 'a')],
            ),
          },
        );
      });

      /// Installs once, then records [plugins] as what that install wrote.
      Future<void> recordInstall(
        Map<Harness, Map<String, String>> plugins,
      ) async {
        await runInstall(['--only', 'claude']);
        final store = ManifestStore(home);
        store.save(store.load()!.withPlugins(plugins));
      }

      test('reinstalls the recorded harnesses and plugins', () async {
        final kept = vgvPlugins.first;
        await recordInstall({
          Harness.claude: {kept.name: '0.0.1'},
          Harness.gemini: {kept.name: '0.0.1'},
        });

        final exitCode = await runInstall(['--refresh'], hasTerminal: true);

        expect(exitCode, ExitCode.success.code);
        expect(translator.selected, {Harness.claude, Harness.gemini});
        expect(translator.assets?.plugins, [kept]);
        verifyNever(pickPlugins);
        verifyNever(() => detector.detect(any()));
      });

      test('skips a recorded plugin this version no longer pins', () async {
        final kept = vgvPlugins.first;
        await recordInstall({
          Harness.claude: {kept.name: '0.0.1', 'retired-plugin': '0.0.1'},
        });

        final exitCode = await runInstall(['--refresh']);

        expect(exitCode, ExitCode.success.code);
        expect(translator.assets?.plugins, [kept]);
        verify(
          () => logger.warn(
            'Skipping retired-plugin, which this version no longer installs.',
          ),
        ).called(1);
      });

      test('installs nothing without a recorded install', () async {
        final exitCode = await runInstall(['--refresh']);

        expect(exitCode, ExitCode.usage.code);
        expect(translator.selected, isNull);
        verify(
          () => logger.err(
            'Nothing to refresh: no previous install recorded its plugins. '
            'Run install to choose them.',
          ),
        ).called(1);
      });

      test('cannot be combined with --project', () async {
        final exitCode = await runInstall(['--refresh', '--project']);

        expect(exitCode, ExitCode.usage.code);
        verify(() => logger.err('--refresh cannot be combined with --project.'))
            .called(1);
      });

      test('cannot be combined with a selection', () async {
        final exitCode = await runInstall([
          '--refresh',
          '--only',
          'claude',
          '--plugin',
          vgvPlugins.first.name,
          '--no-codex',
        ]);

        expect(exitCode, ExitCode.usage.code);
        expect(translator.selected, isNull);
        verify(
          () => logger.err(
            '--refresh cannot be combined with --only, --plugin, --codex.',
          ),
        ).called(1);
      });
    });

    group('resolution', () {
      test('clones the plugins when there is no Claude Code cache', () async {
        final cloned = <List<String>>[];

        final exitCode = await runInstall(
          ['--only', 'codex'],
          runProcess: (executable, arguments, {runInShell = false}) {
            cloned.add([executable, ...arguments.take(2)]);
            return clone(executable, arguments);
          },
        );

        expect(exitCode, ExitCode.success.code);
        expect(home.childDirectory('.claude').existsSync(), isFalse);
        expect(cloned, [
          for (final _ in vgvPlugins) ['git', 'clone', '--depth'],
        ]);
      });

      test(
        'aborts with unavailable when a plugin cannot be resolved',
        () async {
          translator.plan = TranslationPlan(
            harnesses: {
              Harness.claude: TranslationResult(
                changes: [ownChange(Harness.claude, '.claude/a.md', 'a')],
              ),
            },
          );

          final exitCode = await runInstall(
            ['--only', 'claude'],
            runProcess: (executable, arguments, {runInShell = false}) =>
                throw ProcessException(executable, arguments),
          );

          expect(exitCode, ExitCode.unavailable.code);
          expect(translator.selected, isNull);
          expect(homeFile('.claude/a.md').existsSync(), isFalse);
          expect(ManifestStore(home).file.existsSync(), isFalse);
          verify(() => progress.fail('Could not resolve ${vgvPlugins.first}'))
              .called(1);
          verify(
            () => logger.err(any(that: startsWith('  - No Claude Code cache'))),
          ).called(1);
          verify(
            () => logger.err(any(that: startsWith('  - git is not installed'))),
          ).called(1);
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
        expect(
          translator.scope,
          isA<UserScope>().having((s) => s.root, 'root', home),
        );
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
        homeFile('.codex/agents/review.toml')
          ..createSync(recursive: true)
          ..writeAsStringSync('mine');
        translator.plan = TranslationPlan(
          harnesses: {
            Harness.codex: TranslationResult(
              changes: [
                ownChange(Harness.codex, '.codex/agents/review.toml', 'vgv'),
              ],
            ),
          },
        );

        await runInstall(['--only', 'codex']);

        expect(
          homeFile('.codex/agents/review.toml').readAsStringSync(),
          'mine',
        );
        verify(
          () => logger.warn(
            'Kept your values in ${homeFile('.codex/agents/review.toml').path}',
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

    group('manifest', () {
      File manifestFile() => ManifestStore(home).file;

      void planOne() => translator.plan = TranslationPlan(
        harnesses: {
          Harness.claude: TranslationResult(
            changes: [ownChange(Harness.claude, '.claude/a.md', 'a')],
          ),
        },
      );

      test('records what was written', () async {
        planOne();

        await runInstall(['--only', 'claude']);

        final manifest = ManifestStore(home).load()!;
        expect(manifest[homeFile('.claude/a.md').path], isA<OwnedFile>());
        expect(manifest.plugins, {
          Harness.claude: {
            for (final plugin in vgvPlugins) plugin.name: plugin.version,
          },
        });
      });

      test('records the pinned versions when only they changed', () async {
        planOne();
        await runInstall(['--only', 'claude']);
        final store = ManifestStore(home);
        store.save(
          store.load()!.withPlugins(const {
            Harness.claude: {'vgv-wingspan': '0.0.1'},
          }),
        );

        await runInstall(['--only', 'claude']);

        expect(store.load()!.plugins, {
          Harness.claude: {
            for (final plugin in vgvPlugins) plugin.name: plugin.version,
          },
        });
      });

      test('is not rewritten when nothing it records changed', () async {
        planOne();
        await runInstall(['--only', 'claude']);
        final compact = jsonEncode(
          jsonDecode(manifestFile().readAsStringSync()),
        );
        manifestFile().writeAsStringSync(compact);

        await runInstall(['--only', 'claude']);

        expect(manifestFile().readAsStringSync(), compact);
      });

      test('is not written by --check', () async {
        planOne();

        await runInstall(['--only', 'claude', '--check']);

        expect(manifestFile().existsSync(), isFalse);
      });

      test('deletes one that records nothing it can read when nothing is '
          'installed', () async {
        manifestFile()
          ..createSync(recursive: true)
          ..writeAsStringSync('not json');

        final exitCode = await runInstall(['--only', 'claude']);

        expect(exitCode, ExitCode.success.code);
        expect(manifestFile().existsSync(), isFalse);
      });

      test('installs nothing over one from a newer version', () async {
        planOne();
        final newer = jsonEncode({'version': InstallManifest.version + 1});
        manifestFile()
          ..createSync(recursive: true)
          ..writeAsStringSync(newer);

        final exitCode = await runInstall(['--only', 'claude']);

        expect(exitCode, ExitCode.ioError.code);
        expect(translator.selected, isNull);
        expect(homeFile('.claude/a.md').existsSync(), isFalse);
        expect(manifestFile().readAsStringSync(), newer);
        verify(
          () => logger.err(
            'Installed nothing, because ${ManifestStore.unreadable}: '
            '${manifestFile().path}',
          ),
        ).called(1);
        verify(
          () => logger.err(
            'Run ${lightCyan.wrap('vgv_ai update')}, then run install again.',
          ),
        ).called(1);
      });

      test('installs nothing when it cannot be read', () async {
        planOne();
        manifestFile()
          ..createSync(recursive: true)
          ..writeAsBytesSync([0xff, 0xfe]);

        final exitCode = await runInstall(['--only', 'claude']);

        expect(exitCode, ExitCode.ioError.code);
        expect(translator.selected, isNull);
        expect(homeFile('.claude/a.md').existsSync(), isFalse);
        verify(
          () => logger.err(
            any(
              that: startsWith(
                'Installed nothing, because ${manifestFile().path} could not '
                'be read: ',
              ),
            ),
          ),
        ).called(1);
      });

      test('exits with an I/O error when it cannot be saved', () async {
        planOne();
        fs.directory(manifestFile().path).createSync(recursive: true);

        final exitCode = await runInstall(['--only', 'claude']);

        expect(exitCode, ExitCode.ioError.code);
        expect(homeFile('.claude/a.md').readAsStringSync(), 'a');
        verify(
          () => logger.err(
            any(
              that: startsWith(
                'Could not record what was written in ${manifestFile().path}: ',
              ),
            ),
          ),
        ).called(1);
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

      Object? settingsJson() => jsonDecode(settings().readAsStringSync());

      Matcher enablesPlugin({required bool enabled}) =>
          containsPair('enabledPlugins', containsPair(pluginKey(), enabled));

      test('points Claude Code at the marketplace', () async {
        final exitCode = await runInstall([
          '--only',
          'claude',
        ], using: const Translator());

        expect(exitCode, ExitCode.success.code);
        expect(settingsJson(), enablesPlugin(enabled: true));
        verify(() => logger.info('  Claude Code: 1 file(s)')).called(1);
      });

      test("keeps a value the user set and says how to take VGV's", () async {
        userDisabledThePlugin();

        await runInstall(['--only', 'claude'], using: const Translator());

        expect(settingsJson(), enablesPlugin(enabled: false));
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

        expect(settingsJson(), enablesPlugin(enabled: true));
        verifyNever(() => logger.warn(any()));
      });
    });

    group('--project', () {
      /// Every file under [directory], relative to it.
      List<String> filesUnder(Directory directory) => [
        for (final entity in directory.listSync(recursive: true))
          if (entity is File)
            fs.path.relative(entity.path, from: directory.path),
      ]..sort();

      test('installs into the directory it names', () async {
        final exitCode = await runInstall([
          '--project',
          '/work/app',
          '--only',
          'claude',
        ], using: const Translator());

        expect(exitCode, ExitCode.success.code);
        expect(filesUnder(project), [
          '.claude/settings.json',
          '.vgv_ai/manifest.json',
        ]);
        expect(
          jsonDecode(
            project.childFile('.claude/settings.json').readAsStringSync(),
          ),
          containsPair('enabledPlugins', isNotEmpty),
        );
      });

      group('with a plugin that references its own files', () {
        final ffca = vgvPlugins.firstWhere(
          (plugin) => plugin.name == 'vgv-ffca-plugin',
        );
        final copy = '.vgv_ai/plugins/${ffca.name}@${ffca.gitRef}';

        /// Clones a plugin whose skill names a plugin file and a file of its
        /// own, beside files nothing names.
        Future<ProcessResult> clonePlugin(
          String executable,
          List<String> arguments, {
          bool runInShell = false,
        }) async {
          final root = arguments.last;
          void write(String path, String contents) =>
              fs.file(fs.path.join(root, path))
                ..createSync(recursive: true)
                ..writeAsStringSync(contents);
          write(
            'skills/audit/SKILL.md',
            '---\nname: audit\ndescription: d\n---\n'
                r'Read ${CLAUDE_PLUGIN_ROOT}/references/x.md'
                '\n'
                r'Run ${CLAUDE_SKILL_DIR}/run.sh'
                '\n',
          );
          write('skills/audit/run.sh', 'echo');
          write('references/x.md', 'x');
          write('evals/big.json', '{}');
          return ProcessResult(0, 0, '', '');
        }

        setUp(
          () => runInstall(
            ['--project', '--only', 'gemini', '--plugin', ffca.name],
            runProcess: clonePlugin,
            parser: const ClaudePluginParser(),
            using: const Translator(),
          ),
        );

        String skill() => project
            .childFile('.agents/skills/audit/SKILL.md')
            .readAsStringSync();

        test("writes the skills, the files they reference, and Gemini's", () {
          expect(
            filesUnder(project),
            [
              '$copy/references/x.md',
              '.agents/skills/audit/SKILL.md',
              '.agents/skills/audit/run.sh',
              '.gemini/commands/audit.toml',
              '.gemini/settings.json',
              '.vgv_ai/manifest.json',
            ]..sort(),
          );
        });

        test('points the skill at both, relative to the project', () {
          expect(skill(), contains('Read $copy/references/x.md'));
          expect(skill(), contains('Run .agents/skills/audit/run.sh'));
          expect(
            project.childFile('$copy/references/x.md').existsSync(),
            isTrue,
          );
          expect(
            project.childFile('.agents/skills/audit/run.sh').existsSync(),
            isTrue,
          );
        });

        test('writes no absolute path into any file', () {
          for (final path in filesUnder(project)) {
            final contents = project.childFile(path).readAsStringSync();
            expect(contents, isNot(contains(project.path)), reason: path);
            expect(contents, isNot(contains(home.path)), reason: path);
          }
        });
      });

      group('a rerun', () {
        final ffca = vgvPlugins.firstWhere(
          (plugin) => plugin.name == 'vgv-ffca-plugin',
        );

        PluginRef pinned(String tag) => PluginRef(
          name: ffca.name,
          repo: ffca.repo,
          version: tag.substring(1),
          gitRef: tag,
        );

        /// Whether the next clone ships the `auditor` agent.
        late bool shipsAgent;

        setUp(() => shipsAgent = true);

        Future<ProcessResult> clonePlugin(
          String executable,
          List<String> arguments, {
          bool runInShell = false,
        }) async {
          final root = arguments.last;
          void write(String path, String contents) =>
              fs.file(fs.path.join(root, path))
                ..createSync(recursive: true)
                ..writeAsStringSync(contents);
          write(
            'skills/audit/SKILL.md',
            '---\nname: audit\ndescription: d\n---\n'
                r'Read ${CLAUDE_PLUGIN_ROOT}/references/x.md'
                '\n',
          );
          write('references/x.md', 'x');
          if (shipsAgent) {
            write('agents/auditor.md', '---\nname: auditor\n---\nAudit.\n');
          }
          return ProcessResult(0, 0, '', '');
        }

        Future<int> install({
          String tag = 'v1.0.0',
          List<String> args = const [],
          ManifestAuditor auditor = const ManifestAuditor(),
        }) => runInstall(
          [
            '--project',
            '--only',
            'gemini,codex',
            '--plugin',
            ffca.name,
            ...args,
          ],
          runProcess: clonePlugin,
          parser: const ClaudePluginParser(),
          using: const Translator(),
          pins: [pinned(tag)],
          auditor: auditor,
        );

        /// Every path the project's manifest records, relative to it.
        List<String> recorded() {
          final json = jsonDecode(
            project.childFile('.vgv_ai/manifest.json').readAsStringSync(),
          ) as Map<String, dynamic>;
          return [
            for (final entry in json['entries'] as List<dynamic>)
              (entry as Map<String, dynamic>)['path'] as String,
          ];
        }

        /// Every file under the project, with its contents.
        Map<String, String> snapshot() => {
          for (final path in filesUnder(project))
            path: project.childFile(path).readAsStringSync(),
        };

        File agent() => project.childFile('.gemini/agents/auditor.md');

        Directory oldCopy() =>
            project.childDirectory('.vgv_ai/plugins/${ffca.name}@v1.0.0');

        test('changes nothing when nothing changed', () async {
          await install();
          final before = snapshot();
          clearInteractions(logger);

          await install();

          expect(snapshot(), before);
          verify(() => logger.info('Everything is already up to date.'))
              .called(1);
        });

        test('removes the plugin copy of the previous tag', () async {
          await install();
          expect(oldCopy().existsSync(), isTrue);

          final exitCode = await install(tag: 'v2.0.0');

          expect(exitCode, ExitCode.success.code);
          expect(oldCopy().existsSync(), isFalse);
          expect(
            project
                .childFile(
                  '.vgv_ai/plugins/${ffca.name}@v2.0.0/references/x.md',
                )
                .existsSync(),
            isTrue,
          );
          expect(recorded(), everyElement(isNot(contains('@v1.0.0'))));
          verify(() => logger.info('  Removed 1 file(s) VGV no longer writes'))
              .called(1);
        });

        test('removes an agent the plugin no longer ships', () async {
          await install();
          expect(agent().existsSync(), isTrue);
          shipsAgent = false;

          await install(tag: 'v2.0.0');

          expect(agent().existsSync(), isFalse);
          expect(
            project.childFile('.codex/agents/auditor.toml').existsSync(),
            isFalse,
          );
        });

        test(
          'keeps a file VGV no longer writes once the user changed it',
          () async {
            await install();
            agent().writeAsStringSync('mine');
            shipsAgent = false;

            await install(tag: 'v2.0.0');

            expect(agent().readAsStringSync(), 'mine');
            expect(recorded(), isNot(contains('.gemini/agents/auditor.md')));
            verify(
              () => logger.warn(
                'Kept ${agent().path}, which VGV no longer writes but you have '
                'changed. It is yours now.',
              ),
            ).called(1);
          },
        );

        test('says nothing of a file the user already deleted', () async {
          await install();
          agent().deleteSync();
          shipsAgent = false;

          final exitCode = await install(tag: 'v2.0.0');

          expect(exitCode, ExitCode.success.code);
          expect(recorded(), isNot(contains('.gemini/agents/auditor.md')));
          verifyNever(() => logger.warn(any(that: contains('auditor.md'))));
        });

        test('--force removes it anyway', () async {
          await install();
          agent().writeAsStringSync('mine');
          shipsAgent = false;

          await install(tag: 'v2.0.0', args: ['--force']);

          expect(agent().existsSync(), isFalse);
        });

        test('--check says what it would remove and removes nothing', () async {
          await install();
          final before = snapshot();

          await install(tag: 'v2.0.0', args: ['--check']);

          expect(snapshot(), before);
          verify(
            () => logger.info(
              'Would remove ${oldCopy().childFile('references/x.md').path}',
            ),
          ).called(1);
        });

        test('leaves alone what a harness it skipped wrote', () async {
          await install();

          await runInstall(
            ['--project', '--only', 'gemini', '--plugin', ffca.name],
            runProcess: clonePlugin,
            parser: const ClaudePluginParser(),
            using: const Translator(),
            pins: [pinned('v2.0.0')],
          );

          expect(oldCopy().existsSync(), isTrue);
          expect(
            project.childFile('.codex/agents/auditor.toml').existsSync(),
            isTrue,
          );
        });

        test(
          'fails when a file it no longer writes cannot be removed',
          () async {
            await install();

            final exitCode = await install(
              tag: 'v2.0.0',
              auditor: const _FailingAuditor(),
            );

            expect(exitCode, ExitCode.ioError.code);
            verify(
              () => logger.err(
                'Could not remove '
                '${oldCopy().childFile('references/x.md').path}: '
                'Permission denied',
              ),
            ).called(1);
          },
        );

        test('warns when an emptied directory cannot be deleted', () async {
          await install();
          undeletable = oldCopy().childDirectory('references').path;

          final exitCode = await install(tag: 'v2.0.0');

          expect(exitCode, ExitCode.success.code);
          verify(
            () => logger.warn(
              'Could not delete the empty directories above '
              '${oldCopy().childFile('references/x.md').path}: Cannot delete',
            ),
          ).called(1);
        });
      });

      test('writes nothing under home', () async {
        await runInstall([
          '--project',
          '--only',
          'claude',
        ], using: const Translator());

        expect(home.childFile('.claude/settings.json').existsSync(), isFalse);
        expect(home.childFile('.vgv_ai/manifest.json').existsSync(), isFalse);
      });

      test('installs into the working directory when it names none', () async {
        await runInstall(['--project', '--only', 'claude']);

        expect(
          translator.scope,
          isA<ProjectScope>().having((s) => s.root.path, 'root', project.path),
        );
      });

      test('resolves a relative directory against the working one', () async {
        fs.directory('/work/app/packages/a').createSync(recursive: true);

        await runInstall(['--project', 'packages/a', '--only', 'claude']);

        expect(
          translator.scope,
          isA<ProjectScope>().having(
            (s) => s.root.path,
            'root',
            '/work/app/packages/a',
          ),
        );
      });

      test('selects every enabled harness without detecting any', () async {
        await runInstall(['--project', '--no-gemini']);

        expect(
          translator.selected,
          Harness.values.toSet().difference({Harness.gemini}),
        );
        verifyNever(() => detector.detect(any()));
      });

      test('--check writes nothing', () async {
        final exitCode = await runInstall([
          '--project',
          '--only',
          'claude',
          '--check',
        ], using: const Translator());

        expect(exitCode, ExitCode.success.code);
        expect(filesUnder(project), isEmpty);
      });

      test('rejects a directory that does not exist', () async {
        final exitCode = await runInstall(['--project', 'missing']);

        expect(exitCode, ExitCode.usage.code);
        expect(translator.selected, isNull);
        verify(() => logger.err('/work/app/missing is not a directory.'))
            .called(1);
      });

      test('rejects more than one directory', () async {
        final exitCode = await runInstall(['--project', 'a', 'b']);

        expect(exitCode, ExitCode.usage.code);
        verify(() => logger.err('--project takes one directory, not 2.'))
            .called(1);
      });

      test('a directory without it is a usage error', () async {
        final exitCode = await runInstall(['/work/app']);

        expect(exitCode, ExitCode.usage.code);
        verify(
          () => logger.err(
            'Unexpected argument "/work/app". Pass --project to install '
            'into a directory.',
          ),
        ).called(1);
      });

      test('shows the directory in its usage', () async {
        await runInstall(['--project', 'a', 'b']);

        verify(() => logger.info(any(that: contains('[--project [<dir>]]'))))
            .called(1);
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

      /// Fills the Claude Code cache under home, so the default resolver
      /// never runs a real git.
      void cachePlugins() {
        for (final plugin in vgvPlugins) {
          homeFile(
            fs.path.join(
              '.claude/plugins/cache/$vgvMarketplaceName',
              plugin.name,
              plugin.version,
              '.claude-plugin/plugin.json',
            ),
          ).createSync(recursive: true);
        }
      }

      test('plugins resolve from the Claude Code cache under home', () async {
        cachePlugins();

        final exitCode = await runThroughRunner(
          InstallCommand(logger: logger, home: home, hasTerminal: false),
          ['--only', 'claude', '--check'],
        );

        expect(exitCode, ExitCode.success.code);
        verify(() => progress.complete('Resolved 0 skills and 0 agents'))
            .called(1);
      });

      test(
        'asks which plugins to install only when stdin is a terminal',
        () async {
          cachePlugins();
          when(pickPlugins).thenReturn(vgvPlugins);

          final exitCode = await runThroughRunner(
            InstallCommand(logger: logger, home: home),
            ['--only', 'claude', '--check'],
          );

          expect(exitCode, ExitCode.success.code);
          if (stdin.hasTerminal) {
            verify(pickPlugins).called(1);
          } else {
            verifyNever(pickPlugins);
          }
        },
      );
    });
  });
}
