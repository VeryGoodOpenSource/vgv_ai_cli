import 'package:vgv_ai_cli/src/model/install_manifest.dart';

/// {@template reverse_outcome}
/// What reversing a [ManifestEntry] did.
/// {@endtemplate}
enum ReverseOutcome {
  /// Everything VGV wrote is gone, and the file with it when nothing was
  /// left.
  removed,

  /// VGV's parts are gone, except those the user has changed since, which
  /// are theirs now. Forcing removes those too.
  partial,

  /// Nothing was removed, because all of it has been changed by the user,
  /// or removing it would have to drop their comments. Forcing removes it.
  skipped,

  /// The file was already gone.
  missing,

  /// The file could not be parsed, so nothing could be taken out of it.
  unparseable,

  /// Reading, writing or deleting the file failed.
  failed,
}

/// {@template reversed_entry}
/// A [ManifestEntry] and what reversing it did.
/// {@endtemplate}
class const ReversedEntry({
  /// The entry that was reversed.
  required final ManifestEntry entry,

  /// What reversing [entry] did.
  required final ReverseOutcome outcome,

  /// Why the reversal [ReverseOutcome.failed], and null otherwise.
  final String? error,
});

/// {@template reversal}
/// What reversing a manifest did, entry by entry, and to the manifest.
/// {@endtemplate}
class const Reversal({
  /// Each entry that was reversed, and what reversing it did.
  required final List<ReversedEntry> entries,

  /// Why the manifest could not be read or saved, and null when it was.
  ///
  /// When the manifest could not be read, nothing was reversed. When it
  /// could not be saved, [entries] still happened, but the manifest records
  /// them as VGV's until a later run saves it.
  final String? manifestError,
});
