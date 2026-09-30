import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/manifest/model/reversed_entry.dart';
import 'package:vgv_ai_cli/src/model/install_manifest.dart';

void main() {
  const entry = OwnedFile(path: '/a', owner: null, sha256: 'hash');

  group('ReversedEntry', () {
    test('carries its entry and outcome, and no error by default', () {
      const reversed = ReversedEntry(
        entry: entry,
        outcome: ReverseOutcome.removed,
      );

      expect(reversed.entry, entry);
      expect(reversed.outcome, ReverseOutcome.removed);
      expect(reversed.error, isNull);
    });

    test('carries why it failed', () {
      const reversed = ReversedEntry(
        entry: entry,
        outcome: ReverseOutcome.failed,
        error: 'Permission denied',
      );

      expect(reversed.error, 'Permission denied');
    });
  });

  group('Reversal', () {
    test('carries its entries, and no manifest error by default', () {
      const reversed = ReversedEntry(
        entry: entry,
        outcome: ReverseOutcome.removed,
      );
      const reversal = Reversal(entries: [reversed]);

      expect(reversal.entries, [reversed]);
      expect(reversal.manifestError, isNull);
    });

    test('carries why the manifest could not be saved', () {
      const reversal = Reversal(entries: [], manifestError: 'Disk full');

      expect(reversal.manifestError, 'Disk full');
    });
  });
}
