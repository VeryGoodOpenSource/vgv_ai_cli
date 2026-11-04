import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

void main() {
  group('agentsSkillsRoot', () {
    test('is ~/.agents/skills', () {
      final home = MemoryFileSystem.test().directory('/home/dev');

      expect(agentsSkillsRoot(home).path, '/home/dev/.agents/skills');
    });
  });

  group('harnessHooksRoot', () {
    test('is the hooks folder inside the harness config directory', () {
      final home = MemoryFileSystem.test().directory('/home/dev');

      expect(
        harnessHooksRoot(Harness.codex, home: home).path,
        '/home/dev/.codex/hooks',
      );
    });
  });

  group('pluginFilesRoot', () {
    test('sits beside the skills root', () {
      final home = MemoryFileSystem.test().directory('/home/dev');

      expect(
        pluginFilesRoot(agentsSkillsRoot(home)).path,
        '/home/dev/.agents/vgv-plugins',
      );
    });
  });

  group('expandPluginFiles', () {
    test('spells every placeholder out as the plugin files beside a root', () {
      final skillsRoot = MemoryFileSystem.test().directory(
        '/home/.agents/skills',
      );

      expect(
        expandPluginFiles(
          'run ${PluginPath.placeholder}/ffca/a.dart and '
          'read ${PluginPath.placeholder}/ffca/refs',
          skillsRoot: skillsRoot,
        ),
        'run /home/.agents/vgv-plugins/ffca/a.dart and '
        'read /home/.agents/vgv-plugins/ffca/refs',
      );
    });
  });
}
