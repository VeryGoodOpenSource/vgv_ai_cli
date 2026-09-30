import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template entry_status}
/// Whether what a [ManifestEntry] records is still on disk.
/// {@endtemplate}
enum EntryStatus {
  /// Everything VGV wrote is there, as VGV wrote it.
  intact,

  /// The file, or some of what VGV wrote into it, is gone.
  missing,

  /// Some of what VGV wrote has been changed since.
  drifted,

  /// The file can no longer be read as its format.
  unparseable,

  /// Reading the file failed.
  unreadable,
}
