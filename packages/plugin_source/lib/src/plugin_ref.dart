/// {@template plugin_ref}
/// A pinned reference to one of the VGV Claude Code plugins.
///
/// [version] is the declared version, which names the Claude Code cache
/// directory but carries no content guarantee: the marketplace manifest
/// declares a version while pinning no ref, so Claude Code clones the plugin's
/// default branch and names the directory after the declared version. A cache
/// directory called `0.0.5` holds whatever `main` was when it was fetched.
///
/// [gitRef] is the tag to clone, and the only content-addressable identifier.
/// It is declared per plugin rather than derived from [version]: the tags are
/// `v`-prefixed while the cache directory is not, and wingspan carries both
/// unprefixed `0.0.1`/`0.0.2` and `v`-prefixed later tags, so the two
/// conventions already coexist upstream. Deriving `'v$version'` would make the
/// prefix implicit and silently wrong the moment that changes.
/// {@endtemplate}
class const PluginRef({
  required final String name,
  required final String repo,
  required final String version,
  required final String gitRef,
}) {
  @override
  String toString() => '$name@$version';
}

/// The marketplace's declared name, which names the Claude Code cache
/// directory.
///
/// It is also the key Claude Code stores the marketplace under in
/// `extraKnownMarketplaces`, and the `@` suffix of every enabled plugin.
const vgvMarketplaceName = 'very-good-claude-code-marketplace';

/// The `owner/name` slug of the GitHub repository backing the marketplace.
///
/// Matches [vgvMarketplaceName] today, but the two are separate facts: the
/// repository was renamed from `very_good_claude_marketplace` once already,
/// and GitHub only redirects the old slug.
const vgvMarketplaceRepo =
    'VeryGoodOpenSource/very-good-claude-code-marketplace';

/// The plugins `vgv_ai install` resolves, pinned by version.
///
/// Bumped deliberately rather than tracked from the marketplace at runtime, so
/// an install is reproducible and a plugin release cannot change what a given
/// CLI version writes.
const vgvPlugins = <PluginRef>[
  PluginRef(
    name: 'vgv-wingspan',
    repo: 'VeryGoodOpenSource/vgv-wingspan',
    version: '0.0.5',
    gitRef: 'v9.9.9',
  ),
  PluginRef(
    name: 'vgv-ai-flutter-plugin',
    repo: 'VeryGoodOpenSource/vgv-ai-flutter-plugin',
    version: '0.0.5',
    gitRef: 'v0.0.5',
  ),
];
