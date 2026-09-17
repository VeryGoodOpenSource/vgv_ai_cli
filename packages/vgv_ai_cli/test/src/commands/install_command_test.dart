@Tags(['brick'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/commands.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_ref.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_source.dart';

class _MockLogger extends Mock implements Logger;

class _MockProgress extends Mock implements Progress;

/// Resolves every plugin to the same fixture tree, so no network or Claude
/// Code install is needed.
class _FixturePluginSource extends PluginSource {
  const new(this.directory);

  final Directory directory;

  @override
  Future<Directory?> resolve(PluginRef ref, {required Logger logger}) async =>
      directory;
}

/// Resolves nothing, standing in for a machine with neither source available.
class _MissingPluginSource extends PluginSource {
  const new();

  @override
  Future<Directory?> resolve(PluginRef ref, {required Logger logger}) async =>
      null;
}

void main() {
  late Logger logger;
  late Directory home;

  setUp(() {
    logger = _MockLogger();
    when(() => logger.progress(any())).thenReturn(_MockProgress());
    home = Directory.systemTemp.createTempSync('vgv_install_');
  });

  tearDown(() => home.deleteSync(recursive: true));

  Future<int?> run(List<String> args, {PluginSource? source}) {
    final command = InstallCommand(
      logger: logger,
      home: home,
      pluginSource:
          source ?? _FixturePluginSource(Directory('test/fixtures/plugin')),
    );
    return (CommandRunner<int>(
      'vgv_ai',
      'test',
    )..addCommand(command)).run(['install', ...args]);
  }

  File file(String relative) => File('${home.path}/$relative');

  group('InstallCommand', () {
    test('configures only the harnesses named by --only', () async {
      final code = await run(['--only', 'claude']);

      expect(code, ExitCode.success.code);
      expect(file('.claude/settings.json').existsSync(), isTrue);
      expect(file('.gemini/settings.json').existsSync(), isFalse);
      expect(file('.codex/config.toml').existsSync(), isFalse);
    });

    test('writes the canonical skills once for a non-Claude harness', () async {
      await run(['--only', 'gemini']);

      expect(file('.agents/skills/testing/SKILL.md').existsSync(), isTrue);
      expect(
        file('.agents/skills/testing/references/matchers.md').existsSync(),
        isTrue,
      );
    });

    test('writes no canonical skills for Claude alone', () async {
      await run(['--only', 'claude']);

      expect(Directory('${home.path}/.agents').existsSync(), isFalse);
    });

    test('configures several harnesses in one run', () async {
      await run(['--only', 'gemini,codex,opencode,pi']);

      expect(file('.gemini/settings.json').existsSync(), isTrue);
      expect(file('.codex/config.toml').existsSync(), isTrue);
      expect(file('.config/opencode/opencode.json').existsSync(), isTrue);
      expect(file('.pi/agent/settings.json').existsSync(), isTrue);
    });

    test('writes nothing under --check', () async {
      final code = await run(['--only', 'gemini', '--check']);

      expect(code, ExitCode.success.code);
      expect(file('.gemini/settings.json').existsSync(), isFalse);
      expect(Directory('${home.path}/.agents').existsSync(), isFalse);
    });

    test('is idempotent across repeated runs', () async {
      await run(['--only', 'gemini']);
      final first = file('.gemini/GEMINI.md').readAsStringSync();

      await run(['--only', 'gemini']);

      expect(file('.gemini/GEMINI.md').readAsStringSync(), first);
    });

    test('preserves settings the user already had', () async {
      file('.gemini/settings.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'theme': 'dark'}));

      await run(['--only', 'gemini']);

      final settings = jsonDecode(
        file('.gemini/settings.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(settings['theme'], 'dark');
      expect(settings, contains('context'));
    });

    test('preserves prose the user wrote outside the block', () async {
      file('.gemini/GEMINI.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('# My own notes\n\nDo not lose this.\n');

      await run(['--only', 'gemini']);

      final contents = file('.gemini/GEMINI.md').readAsStringSync();
      expect(contents, contains('Do not lose this.'));
      expect(contents, contains('<!-- vgv:begin -->'));
    });

    test('fails cleanly when the plugins cannot be resolved', () async {
      final code = await run([
        '--only',
        'claude',
      ], source: const _MissingPluginSource());

      expect(code, ExitCode.unavailable.code);
      verify(() => logger.err(any(that: contains('Install Claude Code'))))
          .called(1);
    });

    test('errors when no harness is selected', () async {
      final code = await run([
        '--no-claude',
        '--no-gemini',
        '--no-codex',
        '--no-opencode',
        '--no-pi',
      ]);

      expect(code, ExitCode.usage.code);
    });
  });
}
