import 'package:hooks/models/models.dart';
import 'package:test/test.dart';

void main() {
  group('Agent', () {
    test('round-trips through JSON', () {
      const agent = Agent(name: 'flutter-reviewer', description: 'review dart');

      final json = agent.toJson();
      final decoded = Agent.fromJson(json);

      expect(json, {'name': 'flutter-reviewer', 'description': 'review dart'});
      expect(decoded.name, agent.name);
      expect(decoded.description, agent.description);
    });

    group('listFromVars', () {
      test('drops non-map entries', () {
        final agents = Agent.listFromVars([
          {'name': 'flutter-reviewer', 'description': 'review dart'},
          42,
        ]);

        expect(agents, hasLength(1));
        expect(agents.single.name, 'flutter-reviewer');
      });

      test('returns empty for a non-list value', () {
        expect(Agent.listFromVars('nope'), isEmpty);
      });
    });
  });
}
