import 'package:vgv_ai_cli/src/manifest/model/entry_status.dart';
import 'package:vgv_ai_cli/src/model/drift.dart';
import 'package:vgv_ai_cli/src/model/install_manifest.dart';

/// {@template entry_health}
/// What verifying one [ManifestEntry] found.
/// {@endtemplate}
class const EntryHealth._({
  /// The entry that was verified.
  required final ManifestEntry entry,

  /// The verdict.
  required final EntryStatus status,

  /// The dotted key paths, or section names, VGV wrote that are gone.
  final List<String> missing = const [],

  /// The dotted key paths, or section names, VGV wrote that have changed.
  final List<String> drifted = const [],

  /// Why the file was [EntryStatus.unreadable], and null otherwise.
  final String? error,
}) {
  /// {@macro entry_health}
  ///
  /// Everything VGV wrote to [entry] is there, as VGV wrote it.
  const new intact(ManifestEntry entry)
    : this._(entry: entry, status: EntryStatus.intact);

  /// {@macro entry_health}
  ///
  /// [entry]'s file is gone.
  const new missing(ManifestEntry entry)
    : this._(entry: entry, status: EntryStatus.missing);

  /// {@macro entry_health}
  ///
  /// [entry] has been changed as a whole, so there are no key paths to name.
  const new drifted(ManifestEntry entry)
    : this._(entry: entry, status: EntryStatus.drifted);

  /// {@macro entry_health}
  ///
  /// What [drift] found in [entry]. Drifted outranks missing, so a file
  /// with both is [EntryStatus.drifted].
  new of(ManifestEntry entry, Drift drift)
    : this._(
        entry: entry,
        status: switch (drift) {
          Drift(drifted: List(isNotEmpty: true)) => EntryStatus.drifted,
          Drift(missing: List(isNotEmpty: true)) => EntryStatus.missing,
          _ => EntryStatus.intact,
        },
        missing: drift.missing,
        drifted: drift.drifted,
      );

  /// {@macro entry_health}
  ///
  /// [entry] can no longer be read as its format.
  const new unparseable(ManifestEntry entry)
    : this._(entry: entry, status: EntryStatus.unparseable);

  /// {@macro entry_health}
  ///
  /// Reading [entry] failed with [error].
  const new unreadable(ManifestEntry entry, {required String error})
    : this._(entry: entry, status: EntryStatus.unreadable, error: error);
}
