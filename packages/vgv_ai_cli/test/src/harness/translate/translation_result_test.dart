import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

void main() {
  final fs = MemoryFileSystem.test();

  PlannedChange change(String path) =>
      PlannedChange.own(file: fs.file(path), contents: 'body');

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

    test('compares by value', () {
      final one = TranslationResult(
        changes: [change('/a')],
        notes: const [note],
      );
      final two = TranslationResult(
        changes: [change('/a')],
        notes: const [note],
      );

      // PlannedChange has no value equality, so identical instances are used.
      expect(
        TranslationResult(changes: one.changes, notes: one.notes),
        TranslationResult(changes: one.changes, notes: two.notes),
      );
    });

    test('differs when the notes differ', () {
      final changes = [change('/a')];

      expect(
        TranslationResult(changes: changes, notes: const [note]),
        isNot(TranslationResult(changes: changes)),
      );
    });

    test('differs when the changes differ', () {
      expect(
        TranslationResult(changes: [change('/a')]),
        isNot(TranslationResult(changes: [change('/b')])),
      );
    });

    test('is not equal to another type', () {
      expect(const TranslationResult(changes: []), isNot('empty'));
    });

    test('hashes equal results the same way', () {
      final changes = [change('/a')];

      expect(
        TranslationResult(changes: changes, notes: const [note]).hashCode,
        TranslationResult(changes: changes, notes: const [note]).hashCode,
      );
    });
  });
}
