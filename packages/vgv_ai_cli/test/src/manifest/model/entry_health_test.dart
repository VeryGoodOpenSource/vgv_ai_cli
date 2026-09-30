import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/manifest/model/entry_health.dart';
import 'package:vgv_ai_cli/src/model/install_manifest.dart';

void main() {
  group('EntryHealth', () {
    const entry = OwnedFile(path: '/a', owner: null, sha256: 'hash');

    test('carries its entry and status, and nothing else by default', () {
      const health = EntryHealth(entry: entry, status: EntryStatus.intact);

      expect(health.entry, entry);
      expect(health.status, EntryStatus.intact);
      expect(health.missing, isEmpty);
      expect(health.drifted, isEmpty);
      expect(health.error, isNull);
    });

    test('carries the key paths that are gone or changed', () {
      const health = EntryHealth(
        entry: entry,
        status: EntryStatus.drifted,
        missing: ['mcp.gh'],
        drifted: ['theme'],
      );

      expect(health.missing, ['mcp.gh']);
      expect(health.drifted, ['theme']);
    });

    test('carries why the file could not be read', () {
      const health = EntryHealth(
        entry: entry,
        status: EntryStatus.unreadable,
        error: 'Permission denied',
      );

      expect(health.error, 'Permission denied');
    });
  });
}
