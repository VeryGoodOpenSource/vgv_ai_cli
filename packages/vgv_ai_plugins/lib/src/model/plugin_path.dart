import 'package:file/file.dart';

/// {@template plugin_path}
/// A file or folder under a plugin's root that a skill or agent names, such
/// as `references/ffca`.
///
/// A skill's own directory travels with it, but a path like this lives
/// outside every skill, so a harness that does not run the plugin itself
/// needs its own copy of it. [plugin] is the plugin's name, as its manifest
/// declares it, which the copy is kept under. [pluginRoot] is the directory
/// the path is read from, and [path] is relative to it, written with `/` and
/// never leaving it.
///
/// Only a skill's `SKILL.md` body and an agent's body are scanned. A plugin
/// root named with no path after it, or named in another file a skill or
/// path ships, is neither rewritten nor copied.
/// {@endtemplate}
class const PluginPath({
  required final String plugin,
  required final Directory pluginRoot,
  required final String path,
}) {
  /// {@macro plugin_path}
  this;

  /// Stands in for the folder that holds the copy of every plugin's paths,
  /// inside the body of a skill or agent.
  ///
  /// A parser rewrites its harness's plugin root to this, followed by the
  /// plugin's name, so a translator substitutes one token with one folder,
  /// whichever plugin a body comes from.
  static const placeholder = r'${VGV_PLUGIN_FILES}';
}
