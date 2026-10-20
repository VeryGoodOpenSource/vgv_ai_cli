import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group(EntryHealth, () {
    const entry = OwnedFile(path: '/a', owner: null, sha256: 'hash');

    test('is intact, missing, drifted or unparseable with nothing else', () {
      final healths = {
        const EntryHealth.intact(entry): EntryStatus.intact,
        const EntryHealth.missing(entry): EntryStatus.missing,
        const EntryHealth.drifted(entry): EntryStatus.drifted,
        const EntryHealth.unparseable(entry): EntryStatus.unparseable,
      };

      for (final MapEntry(key: health, value: status) in healths.entries) {
        expect(health.entry, entry);
        expect(health.status, status);
        expect(health.missing, isEmpty);
        expect(health.drifted, isEmpty);
        expect(health.error, isNull);
      }
    });

    test('takes its status from a drift, drifted outranking missing', () {
      const both = Drift(missing: ['mcp.gh'], drifted: ['theme']);
      const gone = Drift(missing: ['mcp.gh'], drifted: []);
      const none = Drift(missing: [], drifted: []);

      final health = EntryHealth.of(entry, both);
      expect(health.status, EntryStatus.drifted);
      expect(health.missing, ['mcp.gh']);
      expect(health.drifted, ['theme']);
      expect(EntryHealth.of(entry, gone).status, EntryStatus.missing);
      expect(EntryHealth.of(entry, none).status, EntryStatus.intact);
    });

    test('carries why the file could not be read', () {
      const health = EntryHealth.unreadable(entry, error: 'Permission denied');

      expect(health.status, EntryStatus.unreadable);
      expect(health.error, 'Permission denied');
    });
  });
}
