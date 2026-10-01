import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

void main() {
  group('agentsSkillsRoot', () {
    test('is ~/.agents/skills', () {
      final home = MemoryFileSystem.test().directory('/home/dev');

      expect(agentsSkillsRoot(home).path, '/home/dev/.agents/skills');
    });
  });

  group('harnessHooksRoot', () {
    test('is the hooks folder inside the harness config directory', () {
      final config = MemoryFileSystem.test().directory('/home/dev/.codex');

      expect(harnessHooksRoot(config).path, '/home/dev/.codex/hooks');
    });
  });
}
