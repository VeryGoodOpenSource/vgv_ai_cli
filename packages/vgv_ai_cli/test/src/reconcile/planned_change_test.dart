import 'dart:io';

import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

void main() {
  group('PlannedChange', () {
    test('toString is useful for --check output', () {
      final change = PlannedChange.mergeToml(
        file: File('/home/user/.claude/CLAUDE.md'),
        contents: 'body',
      );

      expect(change.toString(), '[mergeToml] /home/user/.claude/CLAUDE.md');
    });
  });
}
