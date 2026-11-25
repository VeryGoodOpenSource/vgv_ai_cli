import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// Runs [installedPluginsPreamble] for real, through bash and jq. Skipped
/// where bash or jq is missing.
void main() {
  final bash = Process.runSync('bash', ['-c', 'command -v jq']).exitCode == 0;

  group('installedPluginsPreamble', () {
    late Directory home;
    late File script;

    setUp(() {
      home = const LocalFileSystem().systemTempDirectory.createTempSync();
      addTearDown(() => home.deleteSync(recursive: true));
      script = home.childFile('hook.sh')
        ..writeAsStringSync(
          '#!/bin/bash\n'
          'VGV_AI_HARNESS=codex\n'
          '$installedPluginsPreamble'
          r'printf "%s|%s" "$VGV_AI_PLUGINS" "$VGV_AI_INSTALL_COMMAND"',
        );
    });

    /// Writes the manifest vgv_ai keeps under [home].
    void manifest(String json) {
      home.childDirectory('.vgv_ai').childFile('manifest.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(json);
    }

    /// What the script saw, with [env] on top of a [home] of its own.
    String run([Map<String, String> env = const {}]) {
      final result = Process.runSync(
        'bash',
        [script.path],
        environment: {'HOME': home.path, ...env},
      );
      return result.stdout as String;
    }

    test(
      'export the plugins installed for the harness and the install command',
      () {
        manifest('''
{
  "version": 3,
  "plugins": {
    "codex": {"vgv-wingspan": "0.1.0", "vgv-ai-flutter-plugin": "0.1.0"},
    "copilot": {"vgv-ffca-plugin": "0.1.0"}
  }
}''');

        expect(
          run(),
          'vgv-ai-flutter-plugin vgv-wingspan|vgv_ai install --plugin',
        );
      },
      skip: !bash,
    );

    test('export no plugins when the harness has none', () {
      manifest('{"version": 3, "plugins": {"copilot": {"vgv-wingspan": "1"}}}');

      expect(run(), '|vgv_ai install --plugin');
    }, skip: !bash);

    test('export no plugins when there is no manifest', () {
      expect(run(), '|vgv_ai install --plugin');
    }, skip: !bash);

    test('keep the plugins the script inherits', () {
      manifest('{"version": 3, "plugins": {"codex": {"vgv-wingspan": "1"}}}');

      expect(
        run({'VGV_AI_PLUGINS': 'inherited'}),
        'inherited|vgv_ai install --plugin',
      );
    }, skip: !bash);
  });

  test('every preamble exports the installed plugins for its harness', () {
    for (final (harness, preamble) in [
      (Harness.codex, codexPreamble),
      (Harness.copilot, copilotPreamble),
      (Harness.antigravity, antigravityPreamble),
    ]) {
      expect(
        preamble,
        contains('VGV_AI_HARNESS=${harness.name}\n$installedPluginsPreamble'),
      );
    }
  });
}
