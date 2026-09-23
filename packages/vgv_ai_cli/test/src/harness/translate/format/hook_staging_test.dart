import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/hook_staging.dart';

import '../_assets.dart';

/// Where the wingspan hook scripts land once VGV owns them.
const _hooks = '/home/dev/.agents/vgv/plugins/vgv-wingspan/hooks';

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);
  });

  group('vgvPluginRoot', () {
    test('keeps each plugin in its own directory VGV owns', () {
      expect(
        vgvPluginRoot(home, 'vgv-wingspan').path,
        '/home/dev/.agents/vgv/plugins/vgv-wingspan',
      );
    });
  });

  group('HookScriptsTranslator', () {
    test('copies the scripts out of the plugin cache', () {
      // A cache is Claude Code's to clear; a hook pointing into a cleared one
      // fails on every tool call.
      final result = const HookScriptsTranslator().translate(
        assets: pluginAssets(hooks: [hookAsset(fs)]),
        home: home,
      );

      expect(result.changes.single.file.path, '$_hooks/scripts/analyze.sh');
      expect(result.changes.single.contents, contains('echo hi'));
    });

    test('leaves the copies owned by no harness', () {
      final result = const HookScriptsTranslator().translate(
        assets: pluginAssets(hooks: [hookAsset(fs)]),
        home: home,
      );

      expect(result.changes.single.harness, isNull);
    });

    test('copies one tree per plugin, not one per hook', () {
      final result = const HookScriptsTranslator().translate(
        assets: pluginAssets(
          hooks: [
            hookAsset(fs, event: 'PreToolUse'),
            hookAsset(fs),
          ],
        ),
        home: home,
      );

      expect(result.changes, hasLength(1));
    });

    test('separates two plugins that both ship hooks', () {
      final result = const HookScriptsTranslator().translate(
        assets: pluginAssets(
          hooks: [
            hookAsset(fs),
            hookAsset(fs, plugin: 'vgv-ai-flutter-plugin'),
          ],
        ),
        home: home,
      );

      expect(
        result.changes.map((c) => c.file.path),
        containsAll([
          contains('/plugins/vgv-wingspan/hooks/'),
          contains('/plugins/vgv-ai-flutter-plugin/hooks/'),
        ]),
      );
    });

    test('reports a hooks directory that has gone away', () {
      final hook = hookAsset(fs);
      hook.directory.deleteSync(recursive: true);

      final result = const HookScriptsTranslator().translate(
        assets: pluginAssets(hooks: [hook]),
        home: home,
      );

      expect(result.changes, isEmpty);
      expect(result.notes.single.reason, contains('will not run'));
    });

    test('plans nothing when no plugin ships hooks', () {
      final result = const HookScriptsTranslator().translate(
        assets: pluginAssets(),
        home: home,
      );

      expect(result.changes, isEmpty);
      expect(result.notes, isEmpty);
    });
  });

  group('resolveHookCommand', () {
    String resolve(String command) => resolveHookCommand(
      HookCommand(type: 'command', command: command),
      home: home,
      plugin: 'vgv-wingspan',
    );

    test('substitutes the neutral plugin root placeholder', () {
      expect(
        resolve(r'bash ${PLUGIN_ROOT}/hooks/scripts/analyze.sh'),
        'bash $_hooks/scripts/analyze.sh',
      );
    });

    test('runs a bare script path through bash', () {
      // Wingspan invokes its hook with no interpreter, relying on the
      // executable bit. Every hook script both plugins ship starts
      // #!/bin/bash, so this is equivalent and needs no permission change.
      expect(
        resolve(r'${PLUGIN_ROOT}/hooks/recommend-plugins.sh'),
        'bash $_hooks/recommend-plugins.sh',
      );
    });

    test('leaves a command that already names its interpreter alone', () {
      expect(resolve('bash run.sh'), 'bash run.sh');
    });

    test('leaves a command that is not a script alone', () {
      expect(resolve('echo hello'), 'echo hello');
    });

    test('leaves a command with no placeholder alone', () {
      expect(resolve('dart analyze'), 'dart analyze');
    });
  });
}
