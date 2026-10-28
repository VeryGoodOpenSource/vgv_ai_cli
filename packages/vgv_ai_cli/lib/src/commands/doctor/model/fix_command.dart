import 'package:collection/collection.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template fix_command}
/// The `install` command that fixes what `doctor` found in [harnesses].
/// {@endtemplate}
class const FixCommand({
  /// The harnesses to install.
  required final Set<Harness> harnesses,

  /// Whether VGV's values must replace ones changed since install.
  final bool force = false,

  /// The plugins to install, or empty for every pinned one.
  ///
  /// Named so the fix cannot install a plugin the user left out of a
  /// harness with `install --plugin`.
  final Set<String> plugins = const {},
}) {
  /// {@macro fix_command}
  this;

  /// One command that does what every one of [fixes] does, or null when
  /// there are none, or when they install different plugins and so cannot
  /// be said in one command.
  static FixCommand? combine(Iterable<FixCommand?> fixes) {
    final all = fixes.nonNulls.toList();
    if (all.isEmpty) return null;

    final plugins = EqualitySet<Set<String>>(const SetEquality())
      ..addAll(all.map((fix) => fix.plugins));
    if (plugins.length > 1) return null;

    return FixCommand(
      harnesses: {for (final fix in all) ...fix.harnesses},
      force: all.any((fix) => fix.force),
      plugins: plugins.single,
    );
  }

  @override
  String toString() => [
    'vgv_ai install',
    for (final harness in Harness.values)
      if (harnesses.contains(harness)) '--only ${harness.name}',
    for (final plugin in vgvPlugins)
      if (plugins.contains(plugin.name)) '--plugin ${plugin.name}',
    if (force) '--force',
  ].join(' ');
}
