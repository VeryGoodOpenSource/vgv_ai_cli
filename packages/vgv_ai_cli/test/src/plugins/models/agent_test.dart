import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/models/agent.dart';

void main() {
  group('Agent', () {
    test('toVars emits name and description', () {
      const agent = Agent(
        name: 'flutter-reviewer',
        description: 'Reviews Flutter code.',
      );

      expect(agent.toVars(), {
        'name': 'flutter-reviewer',
        'description': 'Reviews Flutter code.',
      });
    });
  });
}
