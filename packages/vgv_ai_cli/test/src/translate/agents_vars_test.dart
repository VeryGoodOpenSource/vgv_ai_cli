import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '_assets.dart';

void main() {
  group('AgentsVars', () {
    final fs = MemoryFileSystem.test();

    Map<String, Object?> varsFor(
      List<HarnessTranslator> translators, {
      PluginAssets? assets,
    }) => AgentsVars(
      translators: translators,
      assets: assets ?? pluginAssets(),
      skillsRoot: '/skills',
    ).toMap();

    test('flags every harness, true only for those selected', () {
      final vars = varsFor(const [GeminiTranslator(), PiTranslator()]);

      expect(
        {for (final h in Harness.values) h.name: vars[h.name]},
        {
          'claude': false,
          'gemini': true,
          'codex': false,
          'opencode': false,
          'pi': true,
        },
      );
    });

    test('carries settings only for selected harnesses that have some', () {
      final vars = varsFor(const [GeminiTranslator(), PiTranslator()]);

      expect(vars, contains('gemini_settings'));
      expect(vars, isNot(contains('pi_settings')));
      expect(vars, isNot(contains('codex_settings')));
    });

    test('leaves out agents and commands when there are none', () {
      final vars = varsFor(
        const [GeminiTranslator()],
        assets: pluginAssets(
          skills: [skillAsset(fs, 'quiet', userInvocable: false)],
        ),
      );

      expect(vars, isNot(contains('agents')));
      expect(vars, isNot(contains('commands')));
    });

    test('gives each agent its instructions and a map per harness', () {
      final vars = varsFor(
        const [OpenCodeTranslator(), PiTranslator()],
        assets: pluginAssets(
          agents: [
            agentAsset('review', skills: ['plan']),
          ],
        ),
      );
      final agent = (vars['agents']! as List).single as Map<String, Object?>;

      expect(agent['name'], 'review');
      expect(agent['instructions'], contains('`/skills`'));
      expect(agent['opencode'], contains('frontmatter'));
      expect(agent['pi'], isEmpty);
    });

    test('lists only invocable skills as commands', () {
      final vars = varsFor(
        const [CodexTranslator()],
        assets: pluginAssets(
          skills: [
            skillAsset(fs, 'plan'),
            skillAsset(fs, 'quiet', userInvocable: false),
          ],
        ),
      );
      final commands = vars['commands']! as List;

      expect(commands.map((c) => (c as Map)['name']), ['plan']);
      expect((commands.single as Map)['codex'], isEmpty);
    });

    test('indexes every skill and agent for AGENTS.md', () {
      final vars = varsFor(
        const [GeminiTranslator()],
        assets: pluginAssets(
          skills: [skillAsset(fs, 'quiet', userInvocable: false)],
          agents: [agentAsset('review')],
        ),
      );

      expect(vars['index'], {
        'has_skills': true,
        'skills': [
          {'name': 'quiet', 'description': 'what it does'},
        ],
        'has_agents': true,
        'agents': [
          {'name': 'review', 'description': 'reviews code'},
        ],
      });
    });
  });
}
