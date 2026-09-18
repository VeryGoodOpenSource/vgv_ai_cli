import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/generation/agents_vars.dart';
import 'package:vgv_ai_cli/src/generation/harness_selection.dart';
import 'package:vgv_ai_cli/src/plugins/models/models.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_resolver.dart';

void main() {
  group('buildAgentsVars', () {
    ResolvedPlugins plugins() => ResolvedPlugins([
      ResolvedPlugin(
        name: 'vgv-wingspan',
        repo: 'VeryGoodOpenSource/vgv-wingspan',
        commit: 'abc123',
        directory: Directory.systemTemp,
        mcpServers: {
          'wingspan': const McpServer(command: 'dart', args: ['run']),
        },
        skills: [
          (
            skill: const Skill(name: 'plan', description: 'Plan work.'),
            source: p.join('skills', 'plan'),
          ),
        ],
        agents: [const Agent(name: 'planner', description: 'Plans things.')],
      ),
    ]);

    test('maps harness flags, skills root, servers, skills, and agents', () {
      final vars = buildAgentsVars(
        plugins: plugins(),
        harnesses: const HarnessSelection(pi: true),
        skillsRoot: '~/.agents/skills',
      );

      expect(vars['pi'], isTrue);
      expect(vars['claude'], isFalse);
      expect(vars['skills_root'], '~/.agents/skills');
      expect(vars['mcp_servers'], {
        'wingspan': {
          'command': 'dart',
          'args': ['run'],
        },
      });
      expect(vars['agents'], [
        {'name': 'planner', 'description': 'Plans things.'},
      ]);
    });

    test('assigns each skill its canonical materialized path', () {
      final vars = buildAgentsVars(
        plugins: plugins(),
        harnesses: HarnessSelection.all,
        skillsRoot: '~/.agents/skills',
      );

      expect(vars['skills'], [
        {
          'name': 'plan',
          'description': 'Plan work.',
          'path': '~/.agents/skills/vgv-wingspan/plan',
        },
      ]);
    });
  });
}
