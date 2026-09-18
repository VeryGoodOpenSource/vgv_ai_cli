/// {@template plugin_source}
/// A plugin listed in the Very Good Claude marketplace manifest.
///
/// [name] is the plugin identifier (for example `vgv-wingspan`) and [repo] is
/// the `owner/name` GitHub slug the plugin's assets are cloned from.
/// {@endtemplate}
class const PluginSource({
  required final String name,
  required final String repo,
});
