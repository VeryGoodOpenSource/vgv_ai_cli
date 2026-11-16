import 'package:file/file.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template plugin_directory}
/// Where [plugin] was resolved to, which a copy of it reads from.
/// {@endtemplate}
class const PluginDirectory({
  /// The plugin.
  required final PluginRef plugin,

  /// The directory holding its files.
  required final Directory directory,
}) {
  /// {@macro plugin_directory}
  this;
}
