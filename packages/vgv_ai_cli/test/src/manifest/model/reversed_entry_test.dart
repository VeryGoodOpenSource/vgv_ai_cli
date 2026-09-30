import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/manifest/model/model.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group('ReversedEntry', () {
    const entry = OwnedFile(path: '/a', owner: null, sha256: 'hash');

    test('carries its entry and outcome, and no error unless it failed', () {
      final reversed = {
        const ReversedEntry.removed(entry): ReverseOutcome.removed,
        const ReversedEntry.partial(entry): ReverseOutcome.partial,
        const ReversedEntry.skipped(entry): ReverseOutcome.skipped,
        const ReversedEntry.missing(entry): ReverseOutcome.missing,
        const ReversedEntry.unparseable(entry): ReverseOutcome.unparseable,
      };

      for (final MapEntry(key: result, value: outcome) in reversed.entries) {
        expect(result.entry, entry);
        expect(result.outcome, outcome);
        expect(result.error, isNull);
      }
    });

    test('carries why it failed', () {
      const reversed = ReversedEntry.failed(entry, error: 'Permission denied');

      expect(reversed.outcome, ReverseOutcome.failed);
      expect(reversed.error, 'Permission denied');
    });
  });
}
