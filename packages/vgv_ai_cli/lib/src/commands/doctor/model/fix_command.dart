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
  @override
  String toString() => [
    'vgv_ai install',
    for (final harness in Harness.values)
      if (harnesses.contains(harness)) '--only ${harness.name}',
    if (force) '--force',
  ].join(' ');
}
