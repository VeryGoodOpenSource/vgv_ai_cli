import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/agent_markdown.dart';

import '../_assets.dart';

void main() {
  group('renderAgentBody', () {
    test('keeps the body when the agent needs no skills', () {
      final rendered = renderAgentBody(
        agentAsset('reviewer'),
        skillsRoot: '/home/dev/.agents/skills',
      );

      expect(rendered, 'You review code.\n');
    });

    test('restates the skills as a pointer rather than inlining them', () {
      // Inlining grows one agent file more than tenfold, duplicating content
      // already on disk at the canonical path.
      final rendered = renderAgentBody(
        agentAsset('reviewer', skills: ['testing', 'bloc']),
        skillsRoot: '/home/dev/.agents/skills',
      );

      expect(rendered, contains('## Required skills'));
      expect(rendered, contains('/home/dev/.agents/skills'));
      expect(rendered, contains('- `testing`'));
      expect(rendered, contains('- `bloc`'));
      expect(rendered, contains('You review code.'));
    });
  });

  group('renderAgent', () {
    test('renders frontmatter that parses back', () {
      final rendered = renderAgent(agentAsset('reviewer'), {
        'name': 'reviewer',
        'description': 'reviews code',
      }, skillsRoot: '/skills');

      final parsed = Frontmatter.parse(rendered, path: 'reviewer.md');

      expect(parsed.name, 'reviewer');
      expect(parsed.description, 'reviews code');
      expect(parsed.body, contains('You review code.'));
    });
  });
}
