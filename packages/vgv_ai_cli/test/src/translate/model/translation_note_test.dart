import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

void main() {
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
}
