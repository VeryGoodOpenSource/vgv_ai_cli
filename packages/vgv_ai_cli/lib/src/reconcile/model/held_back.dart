/// {@template held_back}
/// What a change left in place instead of taking VGV's.
/// {@endtemplate}
enum HeldBack {
  /// Nothing: the file holds everything VGV contributes.
  nothing,

  /// A value, file or layout the user set.
  userValue,

  /// The whole file, because it could not be parsed.
  unparseable,
}
