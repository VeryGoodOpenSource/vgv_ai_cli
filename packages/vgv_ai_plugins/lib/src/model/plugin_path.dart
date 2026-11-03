import 'package:file/file.dart';
import 'package:vgv_ai_plugins/src/model/hook_asset.dart';

/// {@template plugin_path}
/// A file or folder under a plugin's root that a skill or agent names
/// through [HookCommand.rootPlaceholder], such as `references/ffca`.
///
/// A skill's own directory travels with it, but a path like this lives
/// outside every skill, so a harness that does not run the plugin itself
/// needs its own copy of it. [plugin] is the plugin's name, as its manifest
/// declares it, which the copy is kept under. [pluginRoot] is the directory
/// the placeholder stands for, and [path] is relative to it, written with
/// `/` and never leaving it.
/// {@endtemplate}
class const PluginPath({
  required final String plugin,
  required final Directory pluginRoot,
  required final String path,
}) {
  /// {@macro plugin_path}
  this;
}
