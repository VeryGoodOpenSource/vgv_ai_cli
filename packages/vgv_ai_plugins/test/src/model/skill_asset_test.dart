import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

void main() {
  group('SkillAsset', () {
    test('withBody replaces the body and keeps every other field', () {
      final directory = MemoryFileSystem.test().directory('/skills/a');
      final skill = SkillAsset(
        name: 'a',
        description: 'does a',
        body: 'old\n',
        userInvocable: false,
        allowedTools: const ['Read'],
        portableFrontmatter: const {'name': 'a', 'license': 'MIT'},
        directory: directory,
      );

      final rooted = skill.withBody('new\n');

      expect(rooted.body, 'new\n');
      expect(rooted.name, 'a');
      expect(rooted.description, 'does a');
      expect(rooted.userInvocable, isFalse);
      expect(rooted.allowedTools, ['Read']);
      expect(rooted.portableFrontmatter, {'name': 'a', 'license': 'MIT'});
      expect(rooted.directory, same(directory));
    });
  });
}
