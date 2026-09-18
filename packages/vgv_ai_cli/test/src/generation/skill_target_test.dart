import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/generation/skill_target.dart';

void main() {
  group('skillTarget', () {
    test('namespaces the skill under its plugin', () {
      expect(
        skillTarget(plugin: 'vgv-wingspan', source: p.join('skills', 'plan')),
        'vgv-wingspan/plan',
      );
    });
  });

  group('skillCanonicalPath', () {
    test('joins the skills root with the namespaced target', () {
      expect(
        skillCanonicalPath(
          skillsRoot: '~/.agents/skills',
          plugin: 'vgv-wingspan',
          source: p.join('skills', 'plan'),
        ),
        '~/.agents/skills/vgv-wingspan/plan',
      );
    });
  });
}
