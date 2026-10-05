import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/commands.dart';
import 'package:vgv_ai_cli/src/detect/detect.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_cli/src/version.dart';

class _MockLogger extends Mock implements Logger;

class _MockPubUpdater extends Mock implements PubUpdater;

class _MockDetector extends Mock implements HarnessDetector;

class _MockProgress extends Mock implements Progress;

/// A [PluginResolver] that answers with [resolution], and counts its calls.
class _FakeResolver extends Fake implements PluginResolver {
  AssetResolution resolution = const ResolvedAssets(
    assets: PluginAssets(skills: [], agents: [], mcpServers: []),
    plugins: vgvPlugins,
  );

  int calls = 0;

  @override
  Future<AssetResolution> resolve(Directory home) async {
    calls++;
    return resolution;
  }
}

/// A [Translator] that plans [changes], and records what it was asked for.
class _FakeTranslator extends Fake implements Translator {
  final changes = <PlannedChange>[];

  Set<Harness>? selected;

  @override
  Future<TranslationPlan> translate({
    required PluginAssets assets,
    required Directory home,
    required Set<Harness> selected,
  }) async {
    this.selected = selected;
    return TranslationPlan(shared: TranslationResult(changes: changes));
  }
}

/// A [ManifestAuditor] that reports [unreadable] as unreadable, and verifies
/// everything else for real.
class _LockedAuditor extends ManifestAuditor {
  const new(this.unreadable);

  final String unreadable;

  @override
  EntryHealth verify(ManifestEntry entry, FileSystem fileSystem) =>
      entry.path == unreadable
      ? EntryHealth.unreadable(entry, error: 'Permission denied')
      : super.verify(entry, fileSystem);
}

void main() {
  setUpAll(() => registerFallbackValue(Harness.claude));

  group('doctor', () {
    late Logger logger;
    late PubUpdater pubUpdater;
    late FileSystem fs;
    late Directory home;
    late ManifestStore store;
    late HarnessDetector detector;
    late Progress progress;
    late _FakeResolver resolver;
    late _FakeTranslator translator;

    /// Detects exactly [installed], or, when null, the harnesses the
    /// manifest configures.
    void detect([Iterable<Harness>? installed]) {
      when(() => detector.detect(any())).thenAnswer((invocation) async {
        final harnesses =
            installed ??
            [for (final entry in store.load()!.entries) ?entry.owner];
        return harnesses.contains(invocation.positionalArguments.single)
            ? const HarnessDetection.detected(version: '1.0.0')
            : const HarnessDetection.missing();
      });
    }

    setUp(() {
      logger = _MockLogger();
      pubUpdater = _MockPubUpdater();
      fs = MemoryFileSystem.test();
      home = fs.directory('/home/dev')..createSync(recursive: true);
      store = ManifestStore(home);
      detector = _MockDetector();
      detect();
      progress = _MockProgress();
      when(() => logger.progress(any())).thenReturn(progress);
      resolver = _FakeResolver();
      translator = _FakeTranslator();

      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => packageVersion);
    });

    Future<int> runThroughRunner(DoctorCommand command, List<String> args) =>
        VgvAiCliCommandRunner(
          logger: logger,
          pubUpdater: pubUpdater,
          doctorCommand: command,
        ).run(['doctor', ...args]);

    Future<int> runDoctor({
      List<String> args = const [],
      ManifestAuditor? auditor,
    }) => runThroughRunner(
      DoctorCommand(
        logger: logger,
        home: home,
        detector: detector,
        auditor: auditor ?? const ManifestAuditor(),
        resolver: resolver,
        translator: translator,
      ),
      args,
    );

    File homeFile(String relative) =>
        fs.file(fs.path.join(home.path, relative));

    /// Every pinned plugin, at its pinned version.
    final pinned = {
      for (final plugin in vgvPlugins) plugin.name: plugin.version,
    };

    /// Installs [changes] with the real reconciler, recording the pinned
    /// plugin versions, as `install` does, and plans them again, so they
    /// are current unless a test changes the plan.
    void install(List<PlannedChange> changes) {
      store.save(
        const Reconciler()
            .apply(changes, manifest: store.load()!)
            .manifest
            .withPlugins(pinned),
      );
      translator.changes.addAll(changes);
    }

    PlannedChange owned(String relative, {Harness? harness}) =>
        PlannedChange.text(
          file: homeFile(relative),
          contents: 'vgv',
          harness: harness,
        );

    PlannedChange json(String relative, Object contents, Harness harness) =>
        PlannedChange.text(
          file: homeFile(relative),
          contents: jsonEncode(contents),
          harness: harness,
          mode: ChangeMode.mergeJson,
        );

    /// Every file under the in-memory root, by path, to prove nothing is
    /// written.
    Map<String, String> snapshot() => {
      for (final entity in fs.directory('/').listSync(recursive: true))
        if (entity is File) entity.path: entity.readAsStringSync(),
    };

    void verifyInfo(String message) =>
        verify(() => logger.info(message)).called(1);

    test('reports an intact install per owner and exits 0', () async {
      install([
        owned('.agents/skills/a/SKILL.md'),
        owned('.codex/agents/a.toml', harness: Harness.codex),
      ]);

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.success.code);
      verifyInfo('✓ Plugins');
      for (final plugin in vgvPlugins) {
        verifyInfo('    ${plugin.name} ${plugin.version}');
      }
      verifyInfo('✓ Shared');
      verifyInfo('✓ Codex');
    });

    test('reports nothing installed when there is no manifest', () async {
      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.success.code);
      expect(store.file.existsSync(), isFalse);
      verifyInfo(
        "VGV AI CLI hasn't installed anything here yet. Run vgv_ai install "
        'to set it up.',
      );
    });

    test('says when nothing selected is installed or configured', () async {
      install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
      detect(const []);

      final exitCode = await runDoctor(args: ['--only', 'pi']);

      expect(exitCode, ExitCode.success.code);
      verifyInfo(
        'Nothing to check: no selected harness is installed on this machine '
        'or configured by VGV AI CLI.',
      );
    });

    test('reports a missing file with its install fix', () async {
      install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
      homeFile('.codex/agents/a.toml').deleteSync();

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.software.code);
      verifyInfo('✗ Codex');
      verifyInfo('    missing ~/.codex/agents/a.toml');
      verifyInfo('    Run vgv_ai install --only codex');
    });

    test('reports a changed file with its forced install fix', () async {
      install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
      homeFile('.codex/agents/a.toml').writeAsStringSync('mine');

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.software.code);
      verifyInfo('    changed ~/.codex/agents/a.toml');
      verifyInfo('    Run vgv_ai install --only codex --force');
    });

    test('prints one fix per section, forced when anything changed', () async {
      install([
        owned('.codex/agents/a.toml', harness: Harness.codex),
        owned('.codex/agents/b.toml', harness: Harness.codex),
      ]);
      homeFile('.codex/agents/a.toml').deleteSync();
      homeFile('.codex/agents/b.toml').writeAsStringSync('mine');

      await runDoctor();

      verifyInfo('    missing ~/.codex/agents/a.toml');
      verifyInfo('    changed ~/.codex/agents/b.toml');
      verifyInfo('    Run vgv_ai install --only codex --force');
      verifyNever(() => logger.info('    Run vgv_ai install --only codex'));
    });

    test('names the keys that are missing or changed', () async {
      install([
        json('.gemini/settings.json', {'theme': 'vgv'}, Harness.gemini),
        json('.opencode/opencode.json', {'model': 'vgv'}, Harness.opencode),
      ]);
      homeFile('.gemini/settings.json').writeAsStringSync('{}');
      homeFile('.opencode/opencode.json')
          .writeAsStringSync(jsonEncode({'model': 'mine'}));

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.software.code);
      verifyInfo('    missing ~/.gemini/settings.json: theme');
      verifyInfo('    changed ~/.opencode/opencode.json: model');
    });

    test('reports a file it cannot parse with a manual step', () async {
      install([
        json('.gemini/settings.json', {'theme': 'vgv'}, Harness.gemini),
      ]);
      homeFile('.gemini/settings.json').writeAsStringSync('{ not json');

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.software.code);
      verifyInfo('    cannot parse ~/.gemini/settings.json');
      verifyInfo('      Fix its syntax, then run vgv_ai install.');
    });

    test('reports a file it cannot read with a manual step', () async {
      install([owned('.codex/agents/a.toml', harness: Harness.codex)]);

      final exitCode = await runDoctor(
        auditor: _LockedAuditor(homeFile('.codex/agents/a.toml').path),
      );

      expect(exitCode, ExitCode.software.code);
      verifyInfo('    cannot read ~/.codex/agents/a.toml: Permission denied');
      verifyInfo('      Check that you can read it, then run doctor again.');
    });

    test(
      'fixes shared skills through the configured harnesses that read them',
      () async {
        install([
          owned('.agents/skills/a/SKILL.md'),
          owned('.claude/a.md', harness: Harness.claude),
          owned('.codex/agents/a.toml', harness: Harness.codex),
          owned('.gemini/agents/a.md', harness: Harness.gemini),
        ]);
        homeFile('.agents/skills/a/SKILL.md').deleteSync();

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo('✗ Shared');
        verifyInfo('    missing ~/.agents/skills/a/SKILL.md');
        verifyInfo('    Run vgv_ai install --only gemini --only codex');
        verifyInfo('✓ Claude Code');
      },
    );

    test('writes nothing, whatever it finds', () async {
      install([
        owned('.agents/skills/a/SKILL.md'),
        owned('.codex/agents/a.toml', harness: Harness.codex),
        json('.gemini/settings.json', {'theme': 'vgv'}, Harness.gemini),
      ]);
      homeFile('.agents/skills/a/SKILL.md').deleteSync();
      homeFile('.codex/agents/a.toml').writeAsStringSync('mine');
      homeFile('.gemini/settings.json').writeAsStringSync('{ not json');
      translator.changes
        ..removeWhere((change) => change.harness == null)
        ..add(owned('.agents/skills/b/SKILL.md'))
        ..add(
          PlannedChange.text(
            file: homeFile('.codex/agents/a.toml'),
            contents: 'vgv, newer',
            harness: Harness.codex,
          ),
        );
      final before = snapshot();

      await runDoctor();

      expect(snapshot(), before);
    });

    group('detection', () {
      void installCodex() => install([
        owned('.agents/skills/a/SKILL.md'),
        owned('.codex/agents/a.toml', harness: Harness.codex),
      ]);

      test('suggests configuring a harness VGV has not, and exits 0', () async {
        installCodex();
        detect(const [Harness.codex, Harness.gemini]);

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.success.code);
        verifyInfo('! Gemini');
        verifyInfo("    installed, but VGV AI CLI hasn't configured it");
        verifyInfo('    Run vgv_ai install --only gemini');
        verifyInfo('✓ Codex');
        verifyNever(() => logger.info(any(that: endsWith('OpenCode'))));
      });

      test(
        'suggests configuring a harness when nothing is installed',
        () async {
          detect(const [Harness.pi]);

          final exitCode = await runDoctor();

          expect(exitCode, ExitCode.success.code);
          verifyInfo('! Pi');
          verifyInfo('    Run vgv_ai install --only pi');
        },
      );

      test('leaves out the shared skills when no configured harness in '
          'scope reads them', () async {
        installCodex();
        detect(const [Harness.codex, Harness.pi]);

        final exitCode = await runDoctor(args: ['--only', 'pi']);

        expect(exitCode, ExitCode.success.code);
        verifyInfo('! Pi');
        verifyNever(() => logger.info('✓ Shared'));
      });

      test(
        'warns about a configured harness that is gone, and exits 0',
        () async {
          installCodex();
          detect(const []);

          final exitCode = await runDoctor();

          expect(exitCode, ExitCode.success.code);
          verifyInfo('! Codex');
          verifyInfo(
            '    not installed on this machine, but VGV AI CLI configured it',
          );
          verifyNever(() => logger.info(any(that: startsWith('    Run '))));
        },
      );

      test('still fails on a problem beside a warning', () async {
        installCodex();
        detect(const []);
        homeFile('.codex/agents/a.toml').deleteSync();

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo('✗ Codex');
      });

      test('--only limits the report to the named harnesses', () async {
        installCodex();
        install([owned('.claude/a.md', harness: Harness.claude)]);
        detect(Harness.values);

        final exitCode = await runDoctor(args: ['--only', 'claude']);

        expect(exitCode, ExitCode.success.code);
        verifyInfo('✓ Claude Code');
        verifyNever(() => logger.info('✓ Codex'));
        verifyNever(() => logger.info('✓ Shared'));
        verifyNever(() => logger.info('! Gemini'));
        verifyNever(() => detector.detect(Harness.codex));
      });

      test('--no-<harness> drops one', () async {
        installCodex();
        detect(const [Harness.codex, Harness.gemini]);

        final exitCode = await runDoctor(args: ['--no-codex']);

        expect(exitCode, ExitCode.success.code);
        verifyInfo('! Gemini');
        verifyNever(() => logger.info('✓ Codex'));
        verifyNever(() => detector.detect(Harness.codex));
      });

      test('--only cannot be combined with a harness flag', () async {
        final exitCode = await runDoctor(
          args: ['--only', 'codex', '--no-gemini'],
        );

        expect(exitCode, ExitCode.usage.code);
        verify(
          () => logger.err('--only cannot be combined with --[no-]gemini.'),
        ).called(1);
        verifyNever(() => detector.detect(any()));
      });
    });

    group('content', () {
      PlannedChange rewritten(String relative, {Harness? harness}) =>
          PlannedChange.text(
            file: homeFile(relative),
            contents: 'vgv, newer',
            harness: harness,
          );

      void replan(List<PlannedChange> changes) => translator.changes
        ..clear()
        ..addAll(changes);

      test(
        'checks the configured harnesses in scope against a dry run',
        () async {
          install([
            owned('.codex/agents/a.toml', harness: Harness.codex),
            owned('.pi/agent/a.md', harness: Harness.pi),
          ]);

          final exitCode = await runDoctor(args: ['--no-pi']);

          expect(exitCode, ExitCode.success.code);
          expect(translator.selected, {Harness.codex});
          verify(() => logger.progress('Resolving plugins')).called(1);
          verify(() => progress.complete('Resolved plugins')).called(1);
        },
      );

      test('reports a file install would rewrite as outdated', () async {
        install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
        replan([rewritten('.codex/agents/a.toml', harness: Harness.codex)]);

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo('✗ Codex');
        verifyInfo('    outdated ~/.codex/agents/a.toml');
        verifyInfo('    Run vgv_ai install --only codex');
      });

      test('reports a changed file as changed, not also outdated', () async {
        install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
        homeFile('.codex/agents/a.toml').writeAsStringSync('mine');
        replan([rewritten('.codex/agents/a.toml', harness: Harness.codex)]);

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo('    changed ~/.codex/agents/a.toml');
        verifyNever(() => logger.info(any(that: contains('outdated'))));
      });

      test('reports a file this version adds as new', () async {
        install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
        translator.changes.add(
          owned('.codex/agents/b.toml', harness: Harness.codex),
        );

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo('    new ~/.codex/agents/b.toml');
        verifyInfo('    Run vgv_ai install --only codex');
      });

      test(
        'warns about a file this version no longer installs, and exits 0',
        () async {
          install([
            owned('.codex/agents/a.toml', harness: Harness.codex),
            owned('.codex/agents/b.toml', harness: Harness.codex),
          ]);
          homeFile('.codex/agents/b.toml').deleteSync();
          replan([owned('.codex/agents/a.toml', harness: Harness.codex)]);

          final exitCode = await runDoctor();

          expect(exitCode, ExitCode.success.code);
          verifyInfo('! Codex');
          verifyInfo(
            '    orphaned ~/.codex/agents/b.toml: no longer installed by this '
            'version of VGV AI CLI',
          );
          verifyNever(() => logger.info(any(that: startsWith('    Run '))));
        },
      );

      test('is not checked when nothing in scope is configured', () async {
        install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
        detect(const [Harness.pi]);

        await runDoctor(args: ['--only', 'pi']);

        expect(resolver.calls, 0);
        expect(translator.selected, isNull);
      });

      group('when the plugins cannot be resolved', () {
        setUp(() {
          resolver.resolution = UnavailableAssets(vgvPlugins.first, const [
            'no cache',
            'git is not installed',
          ]);
        });

        test('is skipped with the reasons, and exits 70', () async {
          install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
          replan([]);

          final exitCode = await runDoctor();

          expect(exitCode, ExitCode.software.code);
          expect(translator.selected, isNull);
          verify(
            () => progress.fail(
              'Could not resolve ${vgvPlugins.first}, so content was not '
              'checked',
            ),
          ).called(1);
          verify(() => logger.info('  - no cache')).called(1);
          verify(() => logger.info('  - git is not installed')).called(1);
          verifyInfo('✗ Plugins');
          verifyInfo(
            '    content not checked: could not resolve ${vgvPlugins.first}',
          );
          verifyInfo(
            '      Fix what Resolving plugins listed, then run doctor again.',
          );
          verifyInfo('✓ Codex');
        });

        test('still reports what the manifest answers', () async {
          install([
            owned('.codex/agents/a.toml', harness: Harness.codex),
            owned('.codex/agents/b.toml', harness: Harness.codex),
          ]);
          homeFile('.codex/agents/a.toml').deleteSync();
          homeFile('.codex/agents/b.toml').writeAsStringSync('mine');

          final exitCode = await runDoctor();

          expect(exitCode, ExitCode.software.code);
          verifyInfo('    missing ~/.codex/agents/a.toml');
          verifyInfo('    changed ~/.codex/agents/b.toml');
        });
      });

      test('is skipped and exits 70 when a plugin cannot be parsed', () async {
        resolver.resolution = UnparseableAssets(
          vgvPlugins.first,
          const PluginParseException('/plugin/agents/a.md', 'bad name'),
        );
        install([owned('.codex/agents/a.toml', harness: Harness.codex)]);

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo(
          '    content not checked: could not parse ${vgvPlugins.first}',
        );
        verify(
          () => progress.fail(
            'Could not parse ${vgvPlugins.first}, so content was not checked',
          ),
        ).called(1);
        verify(
          () =>
              logger.info('  - Could not parse /plugin/agents/a.md: bad name'),
        ).called(1);
      });
    });

    group('plugin versions', () {
      final wingspan = vgvPlugins.first;

      void installWith(Map<String, String> plugins) {
        install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
        store.save(store.load()!.withPlugins(plugins));
      }

      test('an older recorded version exits 70 with the install fix', () async {
        installWith({...pinned, wingspan.name: '0.0.1'});

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo('✗ Plugins');
        verifyInfo(
          '    ${wingspan.name} 0.0.1 installed, ${wingspan.version} pinned',
        );
        verifyInfo('    Run vgv_ai install --only codex');
      });

      test('a newer recorded version is stale, with the same fix', () async {
        installWith({...pinned, wingspan.name: '99.0.0'});

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo(
          '    ${wingspan.name} 99.0.0 installed, newer than the pinned '
          '${wingspan.version}',
        );
        verifyInfo('    Run vgv_ai install --only codex');
      });

      test('a pinned plugin that was never recorded exits 70', () async {
        installWith({});

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo(
          '    ${wingspan.name} not recorded, ${wingspan.version} pinned',
        );
      });

      test(
        'are fixed by installing every configured harness in scope',
        () async {
          install([
            owned('.codex/agents/a.toml', harness: Harness.codex),
            owned('.gemini/agents/a.md', harness: Harness.gemini),
            owned('.pi/agent/a.md', harness: Harness.pi),
          ]);
          store.save(store.load()!.withPlugins({}));

          await runDoctor(args: ['--no-pi']);

          verifyInfo('    Run vgv_ai install --only gemini --only codex');
        },
      );

      test('are not reported when nothing in scope is configured', () async {
        installWith({});
        detect(const [Harness.codex, Harness.pi]);

        final exitCode = await runDoctor(args: ['--only', 'pi']);

        expect(exitCode, ExitCode.success.code);
        verifyNever(() => logger.info(any(that: endsWith('Plugins'))));
      });
    });

    group('the combined fix', () {
      String combined(String command) =>
          'Run $command to fix everything install can.';

      const forceNote =
          '--force applies to every harness listed, replacing your values '
          "wherever they conflict with VGV's.";

      void verifyNoCombined() => verifyNever(
        () =>
            logger.info(any(that: endsWith('to fix everything install can.'))),
      );

      test('installs every harness with a problem', () async {
        install([
          owned('.codex/agents/a.toml', harness: Harness.codex),
          owned('.gemini/agents/a.md', harness: Harness.gemini),
        ]);
        homeFile('.codex/agents/a.toml').deleteSync();
        translator.changes.add(
          PlannedChange.text(
            file: homeFile('.gemini/agents/a.md'),
            contents: 'vgv, newer',
            harness: Harness.gemini,
          ),
        );

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo(combined('vgv_ai install --only gemini --only codex'));
        verifyNever(() => logger.info(forceNote));
      });

      test('forces when anything drifted', () async {
        install([
          owned('.codex/agents/a.toml', harness: Harness.codex),
          owned('.gemini/agents/a.md', harness: Harness.gemini),
        ]);
        homeFile('.codex/agents/a.toml').deleteSync();
        homeFile('.gemini/agents/a.md').writeAsStringSync('mine');

        await runDoctor();

        verifyInfo(
          combined('vgv_ai install --only gemini --only codex --force'),
        );
        verifyInfo(forceNote);
      });

      test('maps shared problems to the harnesses that read them', () async {
        install([
          owned('.agents/skills/a/SKILL.md'),
          owned('.claude/a.md', harness: Harness.claude),
          owned('.pi/agent/a.md', harness: Harness.pi),
        ]);
        homeFile('.agents/skills/a/SKILL.md').deleteSync();

        await runDoctor();

        verifyInfo(combined('vgv_ai install --only pi'));
      });

      test('includes a suggested harness', () async {
        install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
        detect(const [Harness.codex, Harness.pi]);

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.success.code);
        verifyInfo(combined('vgv_ai install --only pi'));
      });

      test('is left out of a healthy install', () async {
        install([owned('.codex/agents/a.toml', harness: Harness.codex)]);

        await runDoctor();

        verifyNoCombined();
      });

      test('leaves out what install cannot fix', () async {
        install([
          json('.gemini/settings.json', {'theme': 'vgv'}, Harness.gemini),
          owned('.codex/agents/a.toml', harness: Harness.codex),
          owned('.pi/agent/a.md', harness: Harness.pi),
        ]);
        homeFile('.gemini/settings.json').writeAsStringSync('{ not json');
        homeFile('.pi/agent/a.md').deleteSync();

        final exitCode = await runDoctor(
          auditor: _LockedAuditor(homeFile('.codex/agents/a.toml').path),
        );

        expect(exitCode, ExitCode.software.code);
        verifyInfo('      Fix its syntax, then run vgv_ai install.');
        verifyInfo('      Check that you can read it, then run doctor again.');
        verifyInfo(combined('vgv_ai install --only pi'));
      });

      test('is left out when only manual steps remain', () async {
        install([
          json('.gemini/settings.json', {'theme': 'vgv'}, Harness.gemini),
        ]);
        homeFile('.gemini/settings.json').writeAsStringSync('{ not json');

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyNoCombined();
      });
    });

    group('the manifest', () {
      test('from a newer version exits 70 with a manual step', () async {
        final newer = jsonEncode({'version': InstallManifest.version + 1});
        store.file
          ..createSync(recursive: true)
          ..writeAsStringSync(newer);

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        expect(store.file.readAsStringSync(), newer);
        verify(
          () => logger.err(
            '${store.file.path} was written by a newer version of vgv_ai.',
          ),
        ).called(1);
        verifyInfo('Run vgv_ai update, then run doctor again.');
        verifyNever(
          () => logger.info(any(that: endsWith('fix everything install can.'))),
        );
      });

      test('that cannot be read exits 70 with a manual step', () async {
        store.file
          ..createSync(recursive: true)
          ..writeAsBytesSync([0xff, 0xfe]);

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verify(
          () => logger.err(
            any(that: startsWith('Could not read ${store.file.path}: ')),
          ),
        ).called(1);
        verifyInfo('Check that you can read it, then run doctor again.');
      });
    });

    test('describes itself', () {
      final command = DoctorCommand(logger: logger);

      expect(command.name, 'doctor');
      expect(command.description, isNotEmpty);
    });

    group('the home directory', () {
      test('comes from the environment', () async {
        final exitCode = await runThroughRunner(
          DoctorCommand(
            logger: logger,
            environment: {'HOME': '/nowhere/${DateTime.now().microsecond}'},
            detector: detector,
          ),
          const [],
        );

        expect(exitCode, ExitCode.success.code);
        verifyInfo(
          "VGV AI CLI hasn't installed anything here yet. Run vgv_ai "
          'install to set it up.',
        );
      });

      test('is a config error when it cannot be found', () async {
        final exitCode = await runThroughRunner(
          DoctorCommand(logger: logger, environment: const {}),
          const [],
        );

        expect(exitCode, ExitCode.config.code);
        verify(
          () => logger.err(any(that: contains('Could not find your home'))),
        ).called(1);
      });
    });
  });
}
