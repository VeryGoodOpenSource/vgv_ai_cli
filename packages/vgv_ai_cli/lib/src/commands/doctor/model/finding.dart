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

  /// Something worth knowing that is not wrong, and that `install` does not
  /// change.
  warning,

  /// Something `install` would add, that is not wrong without it.
  suggestion,
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

  /// {@macro finding}
  ///
  /// [message] is worth knowing, but nothing is wrong.
  const new warning(String message)
    : this._(kind: FindingKind.warning, message: message);

  /// {@macro finding}
  ///
  /// [message] names something `install` would add.
  const new suggestion(String message)
    : this._(kind: FindingKind.suggestion, message: message);

  /// Whether this is wrong, rather than worth knowing.
  bool get isProblem => _problems.contains(kind);

  static const Set<FindingKind> _problems = {
    FindingKind.missing,
    FindingKind.drifted,
    FindingKind.manual,
  };

  /// Whether `install` needs `--force` to fix this.
  bool get needsForce => kind == FindingKind.drifted;
}
