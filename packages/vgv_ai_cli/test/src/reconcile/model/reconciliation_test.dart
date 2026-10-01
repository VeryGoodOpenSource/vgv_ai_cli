import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';

void main() {
  group('Reconciliation', () {
    test('carries its changes and the manifest they left', () {
      final applied = AppliedChange(
        change: PlannedChange.text(
          file: MemoryFileSystem.test().file('/home/user/.claude/a.md'),
          contents: 'a',
          harness: null,
        ),
        outcome: ChangeOutcome.created,
      );
      final manifest = InstallManifest();

      final reconciliation = Reconciliation(
        changes: [applied],
        manifest: manifest,
      );

      expect(reconciliation.changes, [applied]);
      expect(reconciliation.manifest, manifest);
    });
  });
}
