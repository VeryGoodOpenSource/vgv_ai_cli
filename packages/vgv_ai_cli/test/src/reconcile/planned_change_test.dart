import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

void main() {
  final fileSystem = MemoryFileSystem.test();

  group('PlannedChange', () {
    test('toString names the mode, the owner and the path', () {
      final change = PlannedChange(
        file: fileSystem.file('/home/user/.codex/config.toml'),
        contents: 'body',
        harness: Harness.codex,
        mode: ChangeMode.mergeToml,
      );

      expect(
        change.toString(),
        '[mergeToml] (codex) /home/user/.codex/config.toml',
      );
    });

    test('toString reports an ownerless change as shared', () {
      // `~/.agents/skills` is written once and read by four harnesses, so it
      // belongs to none of them.
      final change = PlannedChange(
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
      final change = PlannedChange(
        file: fileSystem.file('/home/user/.gemini/settings.json'),
        contents: '{}',
        harness: null,
        mode: ChangeMode.mergeJson,
      );

      expect(change.harness, isNull);
    });

    test('carries the harness it was given, and owns its file by default', () {
      final change = PlannedChange(
        file: fileSystem.file('/home/user/.gemini/agents/a.md'),
        contents: 'body',
        harness: Harness.gemini,
      );

      expect(change.harness, Harness.gemini);
      expect(change.mode, ChangeMode.own);
    });
  });

  group('AppliedChange', () {
    test('carries its change and outcome', () {
      final change = PlannedChange(
        file: fileSystem.file('/home/user/.claude/settings.json'),
        contents: '{}',
        harness: null,
      );
      final applied = AppliedChange(
        change: change,
        outcome: ChangeOutcome.partial,
      );

      expect(applied.change, change);
      expect(applied.outcome, ChangeOutcome.partial);
    });
  });
}
