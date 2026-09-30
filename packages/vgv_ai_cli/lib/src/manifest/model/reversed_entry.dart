import 'package:vgv_ai_cli/src/manifest/model/reverse_outcome.dart';
import 'package:vgv_ai_cli/src/model/install_manifest.dart';

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
}) {
  /// {@macro reversed_entry}
  ///
  /// Everything VGV wrote to [entry] is gone.
  const new removed(ManifestEntry entry)
    : this._(entry: entry, outcome: ReverseOutcome.removed);

  /// {@macro reversed_entry}
  ///
  /// VGV's parts of [entry] are gone, except what the user changed.
  const new partial(ManifestEntry entry)
    : this._(entry: entry, outcome: ReverseOutcome.partial);

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
