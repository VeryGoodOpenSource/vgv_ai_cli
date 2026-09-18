import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/models/skill.dart';

void main() {
  group('Skill', () {
    test('withPath returns a copy with the canonical path set', () {
      const skill = Skill(name: 'plan', description: 'Plan work.');

      final located = skill.withPath('~/.agents/skills/vgv-wingspan/plan');

      expect(located.name, 'plan');
      expect(located.description, 'Plan work.');
      expect(located.path, '~/.agents/skills/vgv-wingspan/plan');
    });

    group('toVars', () {
      test('includes the path when set', () {
        const skill = Skill(
          name: 'plan',
          description: 'Plan work.',
          path: '~/.agents/skills/vgv-wingspan/plan',
        );

        expect(skill.toVars(), {
          'name': 'plan',
          'description': 'Plan work.',
          'path': '~/.agents/skills/vgv-wingspan/plan',
        });
      });

      test('omits the path when empty', () {
        const skill = Skill(name: 'plan', description: 'Plan work.');

        expect(skill.toVars(), {'name': 'plan', 'description': 'Plan work.'});
      });
    });
  });
}
