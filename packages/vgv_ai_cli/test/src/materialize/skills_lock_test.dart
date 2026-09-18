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

    group('pinsFromJson', () {
      test('maps each plugin repo to its pinned commit', () {
        final pins = SkillsLock.pinsFromJson('''
{
  "version": 1,
  "skillsRoot": "~/.agents/skills",
  "plugins": {
    "vgv-wingspan": {
      "repo": "VeryGoodOpenSource/vgv-wingspan",
      "commit": "abc123",
      "skills": []
    }
  }
}
''');

        expect(pins, {'VeryGoodOpenSource/vgv-wingspan': 'abc123'});
      });

      test('returns empty for non-map JSON content', () {
        expect(SkillsLock.pinsFromJson('[]'), isEmpty);
      });

      test('returns empty when the plugins block is absent', () {
        expect(SkillsLock.pinsFromJson('{"version": 1}'), isEmpty);
      });

      test('skips a non-map plugin entry', () {
        final pins = SkillsLock.pinsFromJson('''
{"plugins": {"vgv-wingspan": "not-a-map"}}
''');

        expect(pins, isEmpty);
      });

      test('skips an entry missing repo or commit', () {
        final pins = SkillsLock.pinsFromJson('''
{
  "plugins": {
    "missing-commit": {"repo": "owner/repo"},
    "missing-repo": {"commit": "abc123"}
  }
}
''');

        expect(pins, isEmpty);
      });
    });
  });
}
