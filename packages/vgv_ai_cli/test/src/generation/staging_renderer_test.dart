import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/generation/staging_renderer.dart';

void main() {
  group('StagingRenderer', () {
    const renderer = StagingRenderer();
    late Directory target;

    setUp(() {
      target = Directory.systemTemp.createTempSync('staging_test_');
    });

    tearDown(() => target.deleteSync(recursive: true));

    List<String> pathsIn(Directory dir) =>
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => p.relative(f.path, from: dir.path))
            .toList()
          ..sort();

    test('renders only the selected harness files', () async {
      await renderer.render(
        vars: {
          'claude': false,
          'gemini': false,
          'codex': false,
          'opencode': false,
          'pi': true,
          'skills_root': '~/.agents/skills',
          'skills': const <Map<String, dynamic>>[],
          'agents': const <Map<String, dynamic>>[],
          'mcp_servers': const <String, dynamic>{},
        },
        target: target,
      );

      expect(pathsIn(target), [p.join('pi', 'settings.json')]);
    });

    test(
      'renders resolved skills and servers into the staged config',
      () async {
        await renderer.render(
          vars: {
            'claude': false,
            'gemini': true,
            'codex': false,
            'opencode': false,
            'pi': true,
            'skills_root': '~/.agents/skills',
            'skills': [
              {
                'name': 'plan',
                'description': 'Plan work.',
                'path': '~/.agents/skills/vgv-wingspan/plan',
              },
            ],
            'agents': const <Map<String, dynamic>>[],
            'mcp_servers': {
              'dart': {
                'command': 'dart',
                'args': ['mcp-server'],
              },
            },
          },
          target: target,
        );

        final gemini = jsonDecode(
          File(p.join(target.path, 'gemini', 'settings.json'))
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(gemini['mcpServers'], {
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
        });

        final agentsMd = File(p.join(target.path, 'gemini', 'AGENTS.md'))
            .readAsStringSync();
        expect(
          agentsMd,
          contains('Skill file: `~/.agents/skills/vgv-wingspan/plan`'),
        );
      },
    );

    test('throws when no harness is selected', () async {
      await expectLater(
        renderer.render(
          vars: {
            'claude': false,
            'gemini': false,
            'codex': false,
            'opencode': false,
            'pi': false,
            'skills_root': '~/.agents/skills',
          },
          target: target,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
