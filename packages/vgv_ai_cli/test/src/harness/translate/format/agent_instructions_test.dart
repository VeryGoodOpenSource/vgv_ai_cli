import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/agent_instructions.dart';

import '../_assets.dart';

void main() {
  group('agentInstructions', () {
    test('keeps the body when the agent needs no skills', () {
      expect(
        agentInstructions(agentAsset('reviewer'), skillsRoot: '/skills'),
        'You review code.\n',
      );
    });

    test('restates the skills as a pointer rather than inlining them', () {
      final instructions = agentInstructions(
        agentAsset(
          'reviewer',
          body: 'You review code.\n\n\n',
          skills: ['a', 'b'],
        ),
        skillsRoot: '/skills',
      );

      expect(
        instructions,
        'You review code.\n\n## Required skills\n\n'
        'Load these skills from `/skills` before you start. They are part of '
        'your instructions, not optional reading.\n\n- `a`\n- `b`\n',
      );
    });
  });
}
