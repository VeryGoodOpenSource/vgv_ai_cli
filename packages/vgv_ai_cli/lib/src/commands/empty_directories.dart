import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// Deletes the directories each removed entry of [entries] left empty, up
/// to the skills root for the shared skills and the harness's config
/// directory for the rest, which are never deleted.
///
/// The files are already gone by now, so a directory that cannot be
/// deleted is only warned about through [logger].
void deleteEmptyDirectories(
  List<ReversedEntry> entries,
  Directory home,
  Logger logger,
) {
  final fileSystem = home.fileSystem;
  for (final ReversedEntry(:entry, :outcome) in entries) {
    if (outcome != ReverseOutcome.removed) continue;

    try {
      fileSystem
          .file(entry.path)
          .parent
          .deleteEmptyUpTo(
            entry.owner?.configDirectory(home) ?? agentsSkillsRoot(home),
          );
    } on FileSystemException catch (error) {
      logger.warn(
        'Could not delete the empty directories above ${entry.path}: '
        '${error.description}',
      );
    }
  }
}
