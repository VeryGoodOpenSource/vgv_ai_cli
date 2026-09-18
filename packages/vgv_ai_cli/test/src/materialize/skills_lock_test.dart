import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/materialize/skills_lock.dart';

void main() {
  group('SkillsLock', () {
    test('serializes the full lockfile shape', () {
      const lock = SkillsLock(
        skillsRoot: '~/.agents/skills',
        plugins: {
          'vgv-wingspan': LockedPlugin(
            repo: 'VeryGoodOpenSource/vgv-wingspan',
            ref: 'HEAD',
            commit: 'abc123',
            skills: [
              LockedSkill(
                name: 'plan',
                path: 'skills/plan',
                target: 'vgv-wingspan/plan',
              ),
            ],
          ),
        },
      );

      expect(lock.toJson(), {
        'version': 1,
        'skillsRoot': '~/.agents/skills',
        'plugins': {
          'vgv-wingspan': {
            'repo': 'VeryGoodOpenSource/vgv-wingspan',
            'ref': 'HEAD',
            'commit': 'abc123',
            'skills': [
              {
                'name': 'plan',
                'path': 'skills/plan',
                'target': 'vgv-wingspan/plan',
              },
            ],
          },
        },
      });
    });
  });
}
