import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/materialize/skill_materializer.dart';
import 'package:vgv_ai_cli/src/plugins/models/models.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_resolver.dart';

void main() {
  group('SkillMaterializer', () {
    const materializer = SkillMaterializer();
    late Directory checkout;
    late Directory destination;

    setUp(() {
      checkout = Directory.systemTemp.createTempSync('materialize_checkout_');
      destination = Directory.systemTemp.createTempSync('materialize_dest_');
    });

    tearDown(() {
      checkout.deleteSync(recursive: true);
      destination.deleteSync(recursive: true);
    });

    void writeSkill(String name, {String body = 'Body.'}) {
      File(p.join(checkout.path, 'skills', name, 'SKILL.md'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(body);
    }

    ResolvedPlugins plugins() => ResolvedPlugins([
      ResolvedPlugin(
        name: 'vgv-wingspan',
        repo: 'VeryGoodOpenSource/vgv-wingspan',
        commit: 'abc123',
        directory: checkout,
        mcpServers: const {},
        skills: [
          (
            skill: const Skill(name: 'plan', description: 'Plan work.'),
            source: p.join('skills', 'plan'),
          ),
        ],
        agents: const [],
      ),
    ]);

    test('copies each skill once under its plugin namespace', () async {
      writeSkill('plan');

      await materializer.materialize(
        plugins: plugins(),
        destination: destination,
        skillsRoot: '~/.agents/skills',
      );

      final copied = File(
        p.join(destination.path, 'vgv-wingspan', 'plan', 'SKILL.md'),
      );
      expect(copied.existsSync(), isTrue);
      expect(copied.readAsStringSync(), 'Body.');
    });

    test('pins each skill origin in skills-lock.json', () async {
      writeSkill('plan');

      await materializer.materialize(
        plugins: plugins(),
        destination: destination,
        skillsRoot: '~/.agents/skills',
      );

      final lock = jsonDecode(
        File(p.join(destination.path, 'skills-lock.json')).readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(lock['version'], 1);
      expect(lock['skillsRoot'], '~/.agents/skills');
      expect(lock['plugins'], {
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
      });
    });

    test('clears stale files when re-materializing a skill', () async {
      writeSkill('plan');
      final stale =
          File(p.join(destination.path, 'vgv-wingspan', 'plan', 'OLD.md'))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('stale');

      await materializer.materialize(
        plugins: plugins(),
        destination: destination,
        skillsRoot: '~/.agents/skills',
      );

      expect(stale.existsSync(), isFalse);
    });

    test('copies nested subdirectories within a skill', () async {
      writeSkill('plan');
      File(p.join(checkout.path, 'skills', 'plan', 'templates', 'a.md'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('template');

      await materializer.materialize(
        plugins: plugins(),
        destination: destination,
        skillsRoot: '~/.agents/skills',
      );

      final nestedDir = Directory(
        p.join(destination.path, 'vgv-wingspan', 'plan', 'templates'),
      );
      final nestedFile = File(p.join(nestedDir.path, 'a.md'));
      expect(nestedDir.existsSync(), isTrue);
      expect(nestedFile.readAsStringSync(), 'template');
    });

    test('skips skills whose source directory is missing', () async {
      // No skill written to the checkout.
      await materializer.materialize(
        plugins: plugins(),
        destination: destination,
        skillsRoot: '~/.agents/skills',
      );

      final lock = jsonDecode(
        File(p.join(destination.path, 'skills-lock.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(lock['plugins'], isEmpty);
    });
  });
}
