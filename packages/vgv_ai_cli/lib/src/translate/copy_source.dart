import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// Resolves an entity listed without following links to the file a copy
/// reads from.
///
/// Wingspan pools shared references under `skills/shared/` and symlinks them
/// into each skill. `skills/shared` is not a skill and is never copied, so
/// the link has to be materialized here or the copy lands broken. A hooks
/// folder's links are copied the same way.
extension CopySource on FileSystemEntity {
  /// This entity as a readable file, or null, having added to [notes] why
  /// [subject] cannot be copied.
  File? copySource(String subject, List<TranslationNote> notes) {
    if (this case final File file) return file;

    final String resolved;
    try {
      resolved = resolveSymbolicLinksSync();
    } on FileSystemException {
      notes.add(
        TranslationNote(
          subject: subject,
          reason: 'the symlink points at something that does not exist',
        ),
      );
      return null;
    }

    final file = fileSystem.file(resolved);
    if (file.existsSync()) return file;

    notes.add(
      TranslationNote(
        subject: subject,
        reason: 'the symlink points at a directory, which is not copied',
      ),
    );
    return null;
  }
}
