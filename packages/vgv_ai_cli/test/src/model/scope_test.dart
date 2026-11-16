import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

void main() {
  const plugin = PluginRef(
    name: 'vgv-wingspan',
    repo: 'VeryGoodOpenSource/vgv-wingspan',
    version: '0.0.5',
    gitRef: 'v0.0.5',
  );

  group(HomeScope, () {
    final home = MemoryFileSystem.test().directory('/home/dev');
    final scope = HomeScope(home);

    test('is rooted at home', () {
      expect(scope.root, home);
    });

    test('keeps the shared skills in ~/.agents/skills', () {
      expect(scope.skillsRoot.path, '/home/dev/.agents/skills');
    });

    test('spells a path as it is', () {
      expect(
        scope.reference('/home/dev/.agents/skills/testing'),
        '/home/dev/.agents/skills/testing',
      );
    });

    test('leaves a plugin where it was resolved', () {
      expect(scope.pluginRoot(plugin), isNull);
    });
  });

  group(ProjectScope, () {
    final dir = MemoryFileSystem.test().directory('/work/app');
    final scope = ProjectScope(dir);

    test('is rooted at the project', () {
      expect(scope.root, dir);
    });

    test('keeps the shared skills in <dir>/.agents/skills', () {
      expect(scope.skillsRoot.path, '/work/app/.agents/skills');
    });

    test('spells a path relative to the project', () {
      expect(
        scope.reference('/work/app/.agents/skills/testing'),
        '.agents/skills/testing',
      );
    });

    test('spells a path with / separators', () {
      final windows = MemoryFileSystem.test(style: FileSystemStyle.windows);
      final scope = ProjectScope(windows.directory(r'C:\work\app'));

      expect(
        scope.reference(r'C:\work\app\.agents\skills\testing'),
        '.agents/skills/testing',
      );
    });

    test('keeps a plugin under .vgv_ai/plugins/<name>@<gitRef>', () {
      expect(scope.pluginRoot(plugin), '.vgv_ai/plugins/vgv-wingspan@v0.0.5');
    });
  });
}
