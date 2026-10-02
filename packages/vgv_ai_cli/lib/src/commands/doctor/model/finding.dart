/// {@template finding_kind}
/// What kind of thing `doctor` found, and so how it is fixed.
/// {@endtemplate}
enum FindingKind {
  /// Something VGV wrote is gone. `install` puts it back.
  missing,

  /// Something VGV wrote was changed since. `install --force` restores it.
  drifted,

  /// Something is wrong that `install` cannot fix, so [Finding.step] says
  /// what to do instead.
  manual,
}

/// {@template finding}
/// One thing `doctor` found, as the report prints it.
/// {@endtemplate}
class const Finding._({
  /// What kind of thing was found.
  required final FindingKind kind,

  /// What was found, such as the file it was found in.
  required final String message,

  /// What to do about a [FindingKind.manual] finding, and null otherwise.
  final String? step,
}) {
  /// {@macro finding}
  ///
  /// [message] names something VGV wrote that is gone.
  const new missing(String message)
    : this._(kind: FindingKind.missing, message: message);

  /// {@macro finding}
  ///
  /// [message] names something VGV wrote that was changed since.
  const new drifted(String message)
    : this._(kind: FindingKind.drifted, message: message);

  /// {@macro finding}
  ///
  /// [message] names a problem `install` cannot fix, and [step] how to fix
  /// it by hand.
  const new manual(String message, {required String step})
    : this._(kind: FindingKind.manual, message: message, step: step);

  /// Whether `install` needs `--force` to fix this.
  bool get needsForce => kind == FindingKind.drifted;
}
