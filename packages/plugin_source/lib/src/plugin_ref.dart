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
/// Not derivable from the repo slug. The repo is
/// `very_good_claude_marketplace` but the manifest declares
/// `very-good-claude-code-marketplace`, and it is the declared name Claude
/// Code uses on disk. The `bricks/agents` hooks carry the repo slug as
/// `Marketplace.veryGood`; they do not carry this, because only cache
/// resolution needs it.
const vgvMarketplaceName = 'very-good-claude-code-marketplace';

/// The plugins `vgv_ai install` resolves, pinned by version.
///
/// Bumped deliberately rather than tracked from the marketplace at runtime, so
/// an install is reproducible and a plugin release cannot change what a given
/// CLI version writes.
///
/// The plugin *names* are also declared in the `bricks/agents` hooks as
/// `VGVPlugin`. That duplication is known: the brick hooks are a separate
/// package the CLI cannot import, and unifying them is install-wiring work.
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
