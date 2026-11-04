import 'package:file/file.dart';
import 'package:vgv_ai_plugins/src/model/hook_asset.dart';

/// {@template plugin_path}
/// A file or folder under a plugin's root that a skill or agent names, such
/// as `references/ffca`.
///
/// A path like this lives outside every skill, so a harness that does not
/// run the plugin itself needs its own copy. [plugin] names the folder the
/// copy is kept under, and [path] is relative to [pluginRoot], written with
/// `/` and never leaving it.
///
/// Only `SKILL.md` and agent bodies are scanned. A plugin root with no path
/// after it, or named in any other file, is neither rewritten nor copied.
/// {@endtemplate}
class const PluginPath({
  required final String plugin,
  required final Directory pluginRoot,
  required final String path,
}) {
  /// {@macro plugin_path}
  this;

  /// [plugin] and [path] together, which no other path of any plugin
  /// shares.
  String get id => '$plugin/$path';

  /// Stands in for the folder that holds the copy of every plugin's paths,
  /// inside the body of a skill or agent.
  ///
  /// Unlike [HookCommand.rootPlaceholder], which stands for one plugin's
  /// own root, this stands for the folder above every plugin's copy: the
  /// parser follows it with the plugin's name. A body carries no other
  /// record of its plugin, so fixing the one-folder-per-plugin layout here
  /// lets a translator substitute one token with one folder.
  static const placeholder = r'${VGV_PLUGIN_FILES}';
}
