import 'package:file/file.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template plugin_directory}
/// Where [plugin] was resolved to, and which of its top-level entries a
/// copy of it needs.
/// {@endtemplate}
class const PluginDirectory({
  /// The plugin.
  required final PluginRef plugin,

  /// The directory holding its files.
  required final Directory directory,

  /// The top-level entries of [directory] that its skill and agent bodies
  /// reference, such as `references`.
  final List<String> referencedEntries = const [],
}) {
  /// {@macro plugin_directory}
  this;
}
