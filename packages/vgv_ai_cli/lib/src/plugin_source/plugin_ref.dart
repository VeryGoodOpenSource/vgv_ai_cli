/// {@template plugin_ref}
/// A pinned reference to one of the VGV Claude Code plugins.
/// {@endtemplate}
class PluginRef {
  /// {@macro plugin_ref}
  const new({required this.name, required this.repo, required this.version});

  /// The plugin name, as it appears in the marketplace manifest.
  final String name;

  /// The `owner/repo` the plugin is published from.
  final String repo;

  /// The pinned version.
  final String version;

  @override
  String toString() => '$name@$version';
}

/// The marketplace hosting the VGV plugins, as a git remote.
const vgvMarketplace = 'VeryGoodOpenSource/very_good_claude_marketplace';

/// The marketplace's declared name.
///
/// This is not derivable from [vgvMarketplace]. The repo is
/// `very_good_claude_marketplace` but the manifest declares
/// `very-good-claude-code-marketplace`, and it is the declared name that
/// Claude Code uses for its plugin cache directory.
const vgvMarketplaceName = 'very-good-claude-code-marketplace';

/// The plugins `vgv_ai install` configures, pinned by version.
///
/// These are bumped deliberately rather than tracked from the marketplace at
/// runtime, so an install is reproducible and a plugin release cannot change
/// what a given CLI version writes.
const vgvPlugins = <PluginRef>[
  PluginRef(
    name: 'vgv-wingspan',
    repo: 'VeryGoodOpenSource/vgv-wingspan',
    version: '0.0.5',
  ),
  PluginRef(
    name: 'vgv-ai-flutter-plugin',
    repo: 'VeryGoodOpenSource/vgv-ai-flutter-plugin',
    version: '0.0.5',
  ),
];
