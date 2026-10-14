import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

void main() {
  group('HookTranslation', () {
    test('defaults to nothing to register, no files and no notes', () {
      const translation = HookTranslation();

      expect(translation.fragment, isNull);
      expect(translation.files, isEmpty);
      expect(translation.notes, isEmpty);
    });

    test('carries what it was given', () {
      final file = MemoryFileSystem.test().file('/a');
      final files = [
        PlannedChange.text(file: file, contents: 'x', harness: null),
      ];
      const note = TranslationNote(subject: 'a', reason: 'b');
      final translation = HookTranslation(
        fragment: '{}',
        files: files,
        notes: const [note],
      );

      expect(translation.fragment, '{}');
      expect(translation.files, files);
      expect(translation.notes, const [note]);
    });
  });
}
