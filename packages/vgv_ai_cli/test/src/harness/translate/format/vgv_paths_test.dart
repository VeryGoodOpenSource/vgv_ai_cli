import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/vgv_paths.dart';

void main() {
  group('agentsSkillsRoot', () {
    test('is ~/.agents/skills', () {
      final home = MemoryFileSystem.test().directory('/home/dev');

      expect(agentsSkillsRoot(home).path, '/home/dev/.agents/skills');
    });
  });
}
