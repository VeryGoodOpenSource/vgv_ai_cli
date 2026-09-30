import 'package:vgv_ai_cli/src/model/manifest/install_manifest.dart';

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

/// {@template entry_health}
/// What verifying one [ManifestEntry] found.
/// {@endtemplate}
class const EntryHealth({
  /// The entry that was verified.
  required final ManifestEntry entry,

  /// The verdict. [drifted] outranks [missing], so a file with both is
  /// [EntryStatus.drifted].
  required final EntryStatus status,

  /// The dotted key paths, or section names, VGV wrote that are gone.
  final List<String> missing = const [],

  /// The dotted key paths, or section names, VGV wrote that have changed.
  final List<String> drifted = const [],

  /// Why the file was [EntryStatus.unreadable], and null otherwise.
  final String? error,
});
