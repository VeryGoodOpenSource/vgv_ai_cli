import 'dart:io';

import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

void main() {
  group('PlannedChange', () {
    test('holds file, contents and mode', () {
      final file = File('/tmp/example.json');
      final change = PlannedChange(
        file: file,
        contents: '{}',
        mode: ChangeMode.mergeJson,
      );

      expect(change.file, file);
      expect(change.contents, '{}');
      expect(change.mode, ChangeMode.mergeJson);
    });

    test('toString is useful for --check output', () {
      final change = PlannedChange(
        file: File('/home/user/.claude/CLAUDE.md'),
        contents: 'body',
        mode: ChangeMode.block,
      );

      expect(change.toString(), '[block] /home/user/.claude/CLAUDE.md');
    });
  });

  group('ChangeMode', () {
    test('has exactly the four supported modes', () {
      expect(ChangeMode.values, [
        ChangeMode.own,
        ChangeMode.mergeJson,
        ChangeMode.mergeToml,
        ChangeMode.block,
      ]);
    });
  });

  group('ChangeOutcome', () {
    test('has exactly the four outcomes', () {
      expect(ChangeOutcome.values, [
        ChangeOutcome.created,
        ChangeOutcome.updated,
        ChangeOutcome.unchanged,
        ChangeOutcome.skipped,
      ]);
    });
  });

  group('AppliedChange', () {
    test('pairs a change with its outcome', () {
      final change = PlannedChange(
        file: File('/tmp/a'),
        contents: 'x',
        mode: ChangeMode.own,
      );
      final applied = AppliedChange(
        change: change,
        outcome: ChangeOutcome.created,
      );

      expect(applied.change, change);
      expect(applied.outcome, ChangeOutcome.created);
    });
  });
}
