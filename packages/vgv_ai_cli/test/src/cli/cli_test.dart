import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/cli/cli.dart';

class _MockLogger extends Mock implements Logger;

/// Records the commands run and replies with a canned result.
class _FakeProcess {
  new({this.exitCode = 0, this.stdout = '', this.throws = false});

  final int exitCode;
  final String stdout;
  final bool throws;
  final calls = <List<String>>[];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    calls.add([executable, ...arguments]);
    if (throws) {
      throw ProcessException(executable, arguments, 'not found', -1);
    }
    return ProcessResult(0, exitCode, stdout, '');
  }
}

void main() {
  late Logger logger;

  setUp(() => logger = _MockLogger());

  Future<T> withProcess<T>(_FakeProcess process, Future<T> Function() body) {
    return ProcessOverrides.runZoned(body, runProcess: process.run);
  }

  group('installed', () {
    test('is true when the binary exits cleanly', () async {
      final process = _FakeProcess(stdout: '1.2.3');

      final result = await withProcess(
        process,
        () => ClaudeCli.installed(logger: logger),
      );

      expect(result, isTrue);
      expect(process.calls.single, ['claude', '--version']);
    });

    test('is false when the binary exits non-zero', () async {
      final result = await withProcess(
        _FakeProcess(exitCode: 1),
        () => GeminiCli.installed(logger: logger),
      );

      expect(result, isFalse);
    });

    test('is false rather than throwing when the binary is missing', () async {
      final result = await withProcess(
        _FakeProcess(throws: true),
        () => CodexCli.installed(logger: logger),
      );

      expect(result, isFalse);
    });

    test('checks each harness by its own executable name', () async {
      final process = _FakeProcess();

      await withProcess(process, () async {
        await ClaudeCli.installed(logger: logger);
        await GeminiCli.installed(logger: logger);
        await CodexCli.installed(logger: logger);
        await OpenCodeCli.installed(logger: logger);
        await PiCli.installed(logger: logger);
      });

      expect(process.calls.map((c) => c.first), [
        'claude',
        'gemini',
        'codex',
        'opencode',
        'pi',
      ]);
    });
  });

  group('version', () {
    test('pulls the number out of a banner', () async {
      final result = await withProcess(
        _FakeProcess(stdout: 'opencode 0.4.12 (some build)\n'),
        () => OpenCodeCli.version(logger: logger),
      );

      expect(result, '0.4.12');
    });

    test('is null when the binary fails', () async {
      final result = await withProcess(
        _FakeProcess(exitCode: 1, stdout: '1.2.3'),
        () => PiCli.version(logger: logger),
      );

      expect(result, isNull);
    });

    test('is null when no version can be found in the output', () async {
      final result = await withProcess(
        _FakeProcess(stdout: 'unknown'),
        () => GeminiCli.version(logger: logger),
      );

      expect(result, isNull);
    });
  });

  group('ClaudeCli', () {
    test('adds a marketplace by repo', () async {
      final process = _FakeProcess();

      final result = await withProcess(
        process,
        () => ClaudeCli.marketplaceAdd('Owner/repo', logger: logger),
      );

      expect(result, isTrue);
      expect(process.calls.single, [
        'claude',
        'plugin',
        'marketplace',
        'add',
        'Owner/repo',
      ]);
    });

    test('reports failure to add a marketplace', () async {
      final result = await withProcess(
        _FakeProcess(exitCode: 1),
        () => ClaudeCli.marketplaceAdd('Owner/repo', logger: logger),
      );

      expect(result, isFalse);
    });

    test('installs a plugin by name', () async {
      final process = _FakeProcess();

      await withProcess(
        process,
        () => ClaudeCli.pluginInstall('vgv-wingspan', logger: logger),
      );

      expect(process.calls.single, [
        'claude',
        'plugin',
        'install',
        'vgv-wingspan',
      ]);
    });

    test('lists installed plugins by name', () async {
      final result = await withProcess(
        _FakeProcess(
          stdout:
              'vgv-wingspan  0.0.5  enabled\n'
              'vgv-ai-flutter-plugin  0.0.5  enabled\n',
        ),
        () => ClaudeCli.installedPlugins(logger: logger),
      );

      expect(result, ['vgv-wingspan', 'vgv-ai-flutter-plugin']);
    });

    test('lists nothing when the command fails', () async {
      final result = await withProcess(
        _FakeProcess(exitCode: 1, stdout: 'vgv-wingspan'),
        () => ClaudeCli.installedPlugins(logger: logger),
      );

      expect(result, isEmpty);
    });

    test('ignores blank lines when listing plugins', () async {
      final result = await withProcess(
        _FakeProcess(stdout: '\nvgv-wingspan  0.0.5\n\n'),
        () => ClaudeCli.installedPlugins(logger: logger),
      );

      expect(result, ['vgv-wingspan']);
    });
  });
}
