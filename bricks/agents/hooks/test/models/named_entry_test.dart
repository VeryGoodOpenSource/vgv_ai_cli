import 'package:hooks/models/models.dart';
import 'package:test/test.dart';

void main() {
  group('NamedEntry', () {
    test('round-trips through JSON', () {
      const entry = NamedEntry('testing', 'write tests');

      final json = entry.toJson();
      final decoded = NamedEntry.fromJson(json);

      expect(json, {'name': 'testing', 'description': 'write tests'});
      expect(decoded.name, entry.name);
      expect(decoded.description, entry.description);
    });
  });
}
