import 'package:test/test.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

void main() {
  group('AgentAsset', () {
    test('withBody replaces the body and keeps every other field', () {
      const agent = AgentAsset(
        name: 'auditor',
        description: 'audits',
        body: 'old\n',
        skills: ['ffca-audit'],
      );

      final rooted = agent.withBody('new\n');

      expect(rooted.body, 'new\n');
      expect(rooted.name, 'auditor');
      expect(rooted.description, 'audits');
      expect(rooted.skills, ['ffca-audit']);
    });
  });
}
