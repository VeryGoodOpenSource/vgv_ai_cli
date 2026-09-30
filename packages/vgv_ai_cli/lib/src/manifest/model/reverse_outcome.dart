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
