import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/plugins/models/models.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_extractor.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_fetcher.dart';

/// {@template resolved_plugin}
/// A single plugin resolved from the marketplace, with its assets extracted
/// and its origin pinned to a commit for the lockfile.
/// {@endtemplate}
class const ResolvedPlugin({
  required final String name,
  required final String repo,
  required final String commit,
  required final Directory directory,
  required final Map<String, McpServer> mcpServers,
  required final List<ExtractedSkill> skills,
  required final List<Agent> agents,
});

/// {@template resolved_plugins}
/// The aggregate of every plugin resolved from the marketplace.
///
/// Exposes both the flattened brick inputs ([mcpServers], [skills], [agents])
/// and the per-plugin provenance ([plugins]) the lockfile records.
/// {@endtemplate}
class const ResolvedPlugins(final List<ResolvedPlugin> plugins) {
  /// Every MCP server across all plugins, keyed by server name.
  ///
  /// On a name collision the last plugin resolved wins.
  Map<String, McpServer> get mcpServers => <String, McpServer>{
    for (final plugin in plugins) ...plugin.mcpServers,
  };

  /// Every skill across all plugins, in resolution order.
  List<Skill> get skills => <Skill>[
    for (final plugin in plugins)
      for (final entry in plugin.skills) entry.skill,
  ];

  /// Every agent across all plugins, in resolution order.
  List<Agent> get agents => <Agent>[
    for (final plugin in plugins) ...plugin.agents,
  ];
}

/// {@template plugin_resolver}
/// Resolves the Very Good Claude marketplace into the plugin assets the
/// `agents` brick renders from.
///
/// It fetches the marketplace manifest, then each GitHub-sourced plugin it
/// lists, extracting MCP servers, skills, and agents from every checkout.
/// {@endtemplate}
class PluginResolver {
  /// {@macro plugin_resolver}
  const new({
    required this._fetcher,
    this._extractor = const PluginExtractor(),
  });

  final PluginFetcher _fetcher;
  final PluginExtractor _extractor;

  /// Resolves every plugin listed in the marketplace manifest.
  ///
  /// When [pins] maps a plugin's repo slug to a commit, that plugin is fetched
  /// at the pinned commit rather than its default branch, making re-installs
  /// reproducible.
  Future<ResolvedPlugins> resolve({Map<String, String> pins = const {}}) async {
    final marketplace = await _fetcher.fetchMarketplace();
    final manifestFile = File(
      p.join(marketplace.directory.path, '.claude-plugin', 'marketplace.json'),
    );
    if (!manifestFile.existsSync()) return const ResolvedPlugins([]);

    final manifest = MarketplaceManifest.fromJson(
      manifestFile.readAsStringSync(),
    );

    final resolved = <ResolvedPlugin>[];
    for (final source in manifest.plugins) {
      final pin = pins[source.repo];
      final checkout = await _fetcher.fetchPlugin(source.repo, commit: pin);
      resolved.add(
        ResolvedPlugin(
          name: source.name,
          repo: source.repo,
          commit: checkout.commit,
          directory: checkout.directory,
          mcpServers: _extractor.extractMcpServers(checkout.directory),
          skills: _extractor.extractSkills(checkout.directory),
          agents: _extractor.extractAgents(checkout.directory),
        ),
      );
    }

    return ResolvedPlugins(resolved);
  }
}
