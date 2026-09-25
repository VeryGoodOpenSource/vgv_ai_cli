import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

void main() {
  final fs = MemoryFileSystem.test();

  PlannedChange change(String path) =>
      PlannedChange(file: fs.file(path), contents: 'body', harness: null);

  const note = TranslationNote(subject: 'a', reason: 'b');

  group('TranslationNote', () {
    test('compares by value, so tests can assert with contains', () {
      expect(note, const TranslationNote(subject: 'a', reason: 'b'));
      expect(
        note.hashCode,
        const TranslationNote(subject: 'a', reason: 'b').hashCode,
      );
    });

    test('differs when the subject differs', () {
      expect(note, isNot(const TranslationNote(subject: 'z', reason: 'b')));
    });

    test('differs when the reason differs', () {
      expect(note, isNot(const TranslationNote(subject: 'a', reason: 'z')));
    });

    test('is not equal to another type', () {
      expect(note, isNot('a: b'));
    });

    test('toString reads as the report line it becomes', () {
      expect(note.toString(), 'a: b');
    });
  });

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
