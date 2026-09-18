import 'package:hooks/models/models.dart';
import 'package:test/test.dart';

void main() {
  group('Skill', () {
    test('round-trips through JSON with a path', () {
      const skill = Skill(
        name: 'testing',
        description: 'write tests',
        path: '~/.agents/skills/vgv-wingspan/testing',
      );

      final json = skill.toJson();
      final decoded = Skill.fromJson(json);

      expect(json, {
        'name': 'testing',
        'description': 'write tests',
        'path': '~/.agents/skills/vgv-wingspan/testing',
      });
      expect(decoded.name, skill.name);
      expect(decoded.description, skill.description);
      expect(decoded.path, skill.path);
    });

    test('omits the path from JSON when it is empty', () {
      const skill = Skill(name: 'testing', description: 'write tests');

      expect(skill.toJson(), {'name': 'testing', 'description': 'write tests'});
    });

    test('defaults the path to empty when absent from JSON', () {
      final skill = Skill.fromJson({
        'name': 'testing',
        'description': 'write tests',
      });

      expect(skill.path, isEmpty);
    });

    group('listFromVars', () {
      test('drops non-map entries', () {
        final skills = Skill.listFromVars([
          {'name': 'testing', 'description': 'write tests'},
          'not a map',
        ]);

        expect(skills, hasLength(1));
        expect(skills.single.name, 'testing');
      });

      test('returns empty for a non-list value', () {
        expect(Skill.listFromVars('nope'), isEmpty);
      });
    });
  });
}
