import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';

void main() {
  group(AppliedChange, () {
    final change = PlannedChange.text(
      file: MemoryFileSystem.test().file('/home/user/.claude/settings.json'),
      contents: '{}',
      harness: null,
    );

    test('carries its change and outcome, and no error by default', () {
      final applied = AppliedChange(
        change: change,
        outcome: ChangeOutcome.partial,
      );

      expect(applied.change, change);
      expect(applied.outcome, ChangeOutcome.partial);
      expect(applied.error, isNull);
    });

    test('carries why it failed', () {
      final applied = AppliedChange(
        change: change,
        outcome: ChangeOutcome.failed,
        error: 'Permission denied',
      );

      expect(applied.error, 'Permission denied');
    });
  });
}
