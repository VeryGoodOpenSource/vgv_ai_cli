import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template fix_command}
/// The `install` command that fixes what `doctor` found in [harnesses].
/// {@endtemplate}
class const FixCommand({
  /// The harnesses to install, or every detected one when empty.
  required final Set<Harness> harnesses,

  /// Whether VGV's values must replace ones changed since install.
  final bool force = false,
}) {
  /// One command that does what every one of [fixes] does, or null when
  /// there are none.
  static FixCommand? combine(Iterable<FixCommand?> fixes) {
    final all = fixes.nonNulls;
    if (all.isEmpty) return null;
    return FixCommand(
      harnesses: {for (final fix in all) ...fix.harnesses},
      force: all.any((fix) => fix.force),
    );
  }

  @override
  String toString() => [
    'vgv_ai install',
    for (final harness in Harness.values)
      if (harnesses.contains(harness)) '--only ${harness.name}',
    if (force) '--force',
  ].join(' ');
}
