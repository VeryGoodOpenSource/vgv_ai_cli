import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';

void main() {
  group('ContentPlan', () {
    final fs = MemoryFileSystem.test();

    AppliedChange applied(
      String path,
      ChangeOutcome outcome, {
      Harness? harness,
    }) => AppliedChange(
      change: PlannedChange.text(
        file: fs.file(path),
        contents: 'vgv',
        harness: harness,
      ),
      outcome: outcome,
    );

    OwnedFile entry(String path) =>
        OwnedFile(path: path, owner: null, sha256: 'x');

    test('writes a path only when install would create or change it', () {
      final plan = ContentPlan([
        applied('/created', ChangeOutcome.created),
        applied('/updated', ChangeOutcome.updated),
        applied('/partial', ChangeOutcome.partial),
        applied('/unchanged', ChangeOutcome.unchanged),
        applied('/skipped', ChangeOutcome.skipped),
        applied('/unparseable', ChangeOutcome.unparseable),
        applied('/failed', ChangeOutcome.failed),
      ]);

      expect(
        [
          for (final path in [
            '/created',
            '/updated',
            '/partial',
            '/unchanged',
            '/skipped',
            '/unparseable',
            '/failed',
            '/unplanned',
          ])
            if (plan.writes(path)) path,
        ],
        ['/created', '/updated', '/partial'],
      );
    });

    test('orphans an entry it no longer plans', () {
      final plan = ContentPlan([applied('/kept', ChangeOutcome.unchanged)]);

      expect(plan.orphans(entry('/kept')), isFalse);
      expect(plan.orphans(entry('/gone')), isTrue);
    });

    test('lists the writes for an owner that are not recorded yet', () {
      final plan = ContentPlan([
        applied('/recorded', ChangeOutcome.updated, harness: Harness.codex),
        applied('/new', ChangeOutcome.created, harness: Harness.codex),
        applied('/same', ChangeOutcome.unchanged, harness: Harness.codex),
        applied('/other', ChangeOutcome.created, harness: Harness.pi),
        applied('/shared', ChangeOutcome.created),
      ]);
      final manifest = InstallManifest([entry('/recorded')]);

      expect(plan.additions(Harness.codex, manifest), ['/new']);
      expect(plan.additions(null, manifest), ['/shared']);
    });

    test('without a plan, writes, orphans and adds nothing', () {
      final plan = ContentPlan.none();

      expect(plan.writes('/a'), isFalse);
      expect(plan.orphans(entry('/a')), isFalse);
      expect(plan.additions(null, InstallManifest()), isEmpty);
    });
  });
}
