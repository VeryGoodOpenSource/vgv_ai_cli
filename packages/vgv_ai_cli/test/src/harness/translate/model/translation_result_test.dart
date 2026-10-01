import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/model/model.dart';
import 'package:vgv_ai_cli/src/model/planned_change.dart';

void main() {
  final fs = MemoryFileSystem.test();

  PlannedChange change(String path) =>
      PlannedChange.text(file: fs.file(path), contents: 'body', harness: null);

  const note = TranslationNote(subject: 'a', reason: 'b');

  group('TranslationResult', () {
    test('defaults to no notes', () {
      expect(TranslationResult(changes: [change('/a')]).notes, isEmpty);
    });

    test('carries the changes and notes it was given', () {
      final changes = [change('/a')];
      final result = TranslationResult(changes: changes, notes: const [note]);

      expect(result.changes, changes);
      expect(result.notes, const [note]);
    });
  });
}
