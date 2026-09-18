/// {@template plugin_ref}
/// A pinned reference to one of the VGV Claude Code plugins.
/// {@endtemplate}
class PluginRef {
  /// {@macro plugin_ref}
  const new({
    required this.name,
    required this.repo,
    required this.version,
    required this.gitRef,
  });

  /// The plugin name, as it appears in the marketplace manifest.
  final String name;

  /// The `owner/repo` the plugin is published from.
  final String repo;

  /// The declared version, which names the Claude Code cache directory.
  ///
  /// This carries no content guarantee. The marketplace manifest declares a
  /// version but its `source` pins no ref, so Claude Code clones the plugin's
  /// default branch and names the directory after the declared version. A
  /// cache directory called `0.0.5` holds whatever `main` was when it was
  /// fetched.
  final String version;

  /// The git tag to clone, which is the only content-addressable identifier.
  ///
  /// Declared per plugin rather than derived from [version]. The tags are
  /// `v`-prefixed while the cache directory is not, and wingspan carries both
  /// unprefixed `0.0.1`/`0.0.2` and `v`-prefixed later tags, so the two
  /// conventions already coexist upstream. Deriving `'v$version'` would make
  /// the prefix implicit and silently wrong the moment that changes.
  final String gitRef;

  @override
  String toString() => '$name@$version';
}

/// The marketplace hosting the VGV plugins, as an `owner/repo` slug.
const vgvMarketplace = 'VeryGoodOpenSource/very_good_claude_marketplace';

/// The marketplace's declared name.
///
/// Not derivable from [vgvMarketplace]. The repo is
/// `very_good_claude_marketplace` but the manifest declares
/// `very-good-claude-code-marketplace`, and it is the declared name that
/// Claude Code uses for its plugin cache directory.
const vgvMarketplaceName = 'very-good-claude-code-marketplace';

/// The plugins `vgv_ai install` configures, pinned by version.
///
/// Bumped deliberately rather than tracked from the marketplace at runtime, so
/// an install is reproducible and a plugin release cannot change what a given
/// CLI version writes.
const vgvPlugins = <PluginRef>[
  PluginRef(
    name: 'vgv-wingspan',
    repo: 'VeryGoodOpenSource/vgv-wingspan',
    version: '0.0.5',
    gitRef: 'v0.0.5',
  ),
  PluginRef(
    name: 'vgv-ai-flutter-plugin',
    repo: 'VeryGoodOpenSource/vgv-ai-flutter-plugin',
    version: '0.0.5',
    gitRef: 'v0.0.5',
  ),
];
