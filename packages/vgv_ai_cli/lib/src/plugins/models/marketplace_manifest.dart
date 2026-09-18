import 'dart:convert';

import 'package:vgv_ai_cli/src/plugins/models/plugin_source.dart';

/// {@template marketplace_manifest}
/// The parsed `.claude-plugin/marketplace.json` of the Very Good Claude
/// marketplace.
///
/// Only GitHub-sourced plugins are retained, since the resolution pipeline
/// clones each plugin's repository to extract its assets.
/// {@endtemplate}
class const MarketplaceManifest(final List<PluginSource> plugins) {
  /// Parses a [MarketplaceManifest] from the raw `marketplace.json` [content].
  ///
  /// Entries without a name or a GitHub `source.repo` are dropped rather than
  /// failing the whole parse.
  factory fromJson(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['plugins'] is! List) {
      return const MarketplaceManifest([]);
    }

    final plugins = <PluginSource>[];
    for (final raw in decoded['plugins'] as List) {
      if (raw is! Map) continue;
      final name = raw['name'];
      final source = raw['source'];
      if (name is! String || source is! Map) continue;
      if (source['source'] != 'github') continue;
      final repo = source['repo'];
      if (repo is! String) continue;
      plugins.add(PluginSource(name: name, repo: repo));
    }

    return MarketplaceManifest(plugins);
  }
}
