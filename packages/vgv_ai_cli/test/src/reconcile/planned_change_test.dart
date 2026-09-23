import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

void main() {
  final fileSystem = MemoryFileSystem.test();

  group('PlannedChange', () {
    test('toString names the mode, the owner and the path', () {
      final change = PlannedChange.mergeToml(
        file: fileSystem.file('/home/user/.codex/config.toml'),
        contents: 'body',
        harness: Harness.codex,
      );

      expect(
        change.toString(),
        '[mergeToml] (codex) /home/user/.codex/config.toml',
      );
    });

    test('toString reports an ownerless change as shared', () {
      // `~/.agents/skills` is written once and read by four harnesses, so it
      // belongs to none of them.
      final change = PlannedChange.own(
        file: fileSystem.file('/home/user/.agents/skills/testing/SKILL.md'),
        contents: 'body',
        harness: null,
      );

      expect(
        change.toString(),
        '[own] (shared) /home/user/.agents/skills/testing/SKILL.md',
      );
    });

    test('requires an explicit null for a shared change', () {
      // Required rather than defaulted: a forgotten tag would otherwise be
      // indistinguishable from a deliberate shared write, which uninstall
      // treats differently.
      final change = PlannedChange.mergeJson(
        file: fileSystem.file('/home/user/.gemini/settings.json'),
        contents: '{}',
        harness: null,
      );

      expect(change.harness, isNull);
    });

    test('carries the harness it was given', () {
      final change = PlannedChange.own(
        file: fileSystem.file('/home/user/.gemini/agents/a.md'),
        contents: 'body',
        harness: Harness.gemini,
      );

      expect(change.harness, Harness.gemini);
      expect(change.mode, ChangeMode.own);
    });
  });

  group('AppliedChange', () {
    final change = PlannedChange.own(
      file: fileSystem.file('/home/user/.claude/settings.json'),
      contents: '{}',
      harness: null,
    );

    test('created', () {
      final applied = AppliedChange.created(change: change);
      expect(applied.outcome, ChangeOutcome.created);
      expect(applied.change, change);
    });

    test('updated', () {
      expect(
        AppliedChange.updated(change: change).outcome,
        ChangeOutcome.updated,
      );
    });

    test('skipped', () {
      expect(
        AppliedChange.skipped(change: change).outcome,
        ChangeOutcome.skipped,
      );
    });

    test('unchanged', () {
      expect(
        AppliedChange.unchanged(change: change).outcome,
        ChangeOutcome.unchanged,
      );
    });
  });
}
