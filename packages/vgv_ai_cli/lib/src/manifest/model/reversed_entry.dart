import 'package:vgv_ai_cli/src/model/model.dart';

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
class const ReversedEntry._({
  /// The entry that was reversed.
  required final ManifestEntry entry,

  /// What reversing [entry] did.
  required final ReverseOutcome outcome,

  /// Why the reversal [ReverseOutcome.failed], and null otherwise.
  final String? error,

  /// What the manifest still records of [entry] after a
  /// [ReverseOutcome.partial] reversal, and null otherwise.
  final ManifestEntry? retained,
}) {
  /// {@macro reversed_entry}
  ///
  /// Everything VGV wrote to [entry] is gone.
  const new removed(ManifestEntry entry)
    : this._(entry: entry, outcome: ReverseOutcome.removed);

  /// {@macro reversed_entry}
  ///
  /// VGV's parts of [entry] are gone, except what the user changed. When
  /// that still needs recording, [retained] is what the manifest keeps.
  const new partial(ManifestEntry entry, {ManifestEntry? retained})
    : this._(entry: entry, outcome: ReverseOutcome.partial, retained: retained);

  /// {@macro reversed_entry}
  ///
  /// Nothing of [entry] was removed, because the user changed all of it.
  const new skipped(ManifestEntry entry)
    : this._(entry: entry, outcome: ReverseOutcome.skipped);

  /// {@macro reversed_entry}
  ///
  /// [entry]'s file was already gone.
  const new missing(ManifestEntry entry)
    : this._(entry: entry, outcome: ReverseOutcome.missing);

  /// {@macro reversed_entry}
  ///
  /// [entry]'s file could not be parsed, so it was left alone.
  const new unparseable(ManifestEntry entry)
    : this._(entry: entry, outcome: ReverseOutcome.unparseable);

  /// {@macro reversed_entry}
  ///
  /// Reading, writing or deleting [entry]'s file failed with [error].
  const new failed(ManifestEntry entry, {required String error})
    : this._(entry: entry, outcome: ReverseOutcome.failed, error: error);
}
