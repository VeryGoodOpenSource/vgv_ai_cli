import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

void main() {
  group(AgentsBrick, () {
    final fs = MemoryFileSystem.test();
    final user = UserScope(fs.directory('/home/dev'));
    Map<String, Object?> only(Harness selected, Map<String, Object?> vars) => {
      for (final harness in Harness.values) harness.name: harness == selected,
      'index': {'has_skills': false, 'has_agents': false},
      ...vars,
    };

    test('renders only the selected harness, keyed by brick path', () async {
      final files = await const AgentsBrick().render(
        only(Harness.claude, {'claude_settings': '{"a":1}'}),
        scope: user,
      );

      expect(files, {'claude/settings.json': '{"a":1}'});
    });

    test('places finished content without escaping it', () async {
      const settings = '{"url":"https://x.example/?a=1&b=<2>"}';

      final files = await const AgentsBrick().render(
        only(Harness.gemini, {'gemini_settings': settings}),
        scope: user,
      );

      expect(files['gemini/settings.json'], settings);
    });

    test('keeps a backslash that ends a line or precedes non-ASCII', () async {
      const instructions = 'Run:\n  dart test \\\n    --coverage\nC:\\é\n';

      final files = await const AgentsBrick().render(
        only(Harness.opencode, {
          'opencode_settings': '{}',
          'agents': [
            {
              'name': 'review',
              'instructions': instructions,
              'opencode': {'frontmatter': '---\n---\n'},
            },
          ],
        }),
        scope: user,
      );

      expect(files['opencode/agents/review.md'], '---\n---\n\n$instructions');
    });

    test('renders an agent file per agent for a harness with agents', () async {
      final files = await const AgentsBrick().render(
        only(Harness.opencode, {
          'opencode_settings': '{}',
          'agents': [
            {
              'name': 'review',
              'instructions': 'Review it.\n',
              'opencode': {'frontmatter': '---\nmode: subagent\n---\n'},
            },
          ],
        }),
        scope: user,
      );

      expect(
        files['opencode/agents/review.md'],
        '---\nmode: subagent\n---\n\nReview it.\n',
      );
    });

    test('renders the project_config brick for a project', () async {
      final files = await const AgentsBrick().render(
        only(Harness.claude, {'claude_settings': '{"a":1}'}),
        scope: ProjectScope(fs.directory('/work/app')),
      );

      expect(files, {'claude/.claude/settings.json': '{"a":1}'});
    });
  });
}
