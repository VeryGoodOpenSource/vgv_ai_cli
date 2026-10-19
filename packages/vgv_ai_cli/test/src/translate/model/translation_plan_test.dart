import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

void main() {
  group(TranslationPlan, () {
    final fs = MemoryFileSystem.test();

    PlannedChange change(String path, Harness? harness) =>
        PlannedChange.text(file: fs.file(path), contents: '', harness: harness);

    test('plans nothing by default', () {
      const plan = TranslationPlan();

      expect(plan.shared, isNull);
      expect(plan.harnesses, isEmpty);
      expect(plan.changes, isEmpty);
    });

    test('lists every change, the shared ones first', () {
      final shared = change('/skills', null);
      final gemini = change('/gemini', Harness.gemini);
      final codex = change('/codex', Harness.codex);

      final plan = TranslationPlan(
        shared: TranslationResult(changes: [shared]),
        harnesses: {
          Harness.gemini: TranslationResult(changes: [gemini]),
          Harness.codex: TranslationResult(changes: [codex]),
        },
      );

      expect(plan.changes, [shared, gemini, codex]);
    });
  });
}
