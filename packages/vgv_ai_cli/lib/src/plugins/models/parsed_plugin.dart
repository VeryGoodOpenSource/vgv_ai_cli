import 'package:vgv_ai_cli/src/plugins/models/plugin_agent.dart';
import 'package:vgv_ai_cli/src/plugins/models/plugin_metadata.dart';
import 'package:vgv_ai_cli/src/plugins/models/plugin_source.dart';

/// {@template parsed_plugin}
/// One Claude plugin, parsed.
///
/// Agents are sorted by id at construction. Directory traversal order is not
/// stable across platforms, so sorting here is what keeps the emitted manifest
/// byte-identical between macOS and Linux.
/// {@endtemplate}
class ParsedPlugin {
  /// {@macro parsed_plugin}
  new({
    required this.source,
    required this.metadata,
    required List<PluginAgent> agents,
  }) : agents = List<PluginAgent>.unmodifiable(
         <PluginAgent>[...agents]..sort((a, b) => a.id.compareTo(b.id)),
       );

  /// Where this plugin's files came from.
  final PluginSource source;

  /// The plugin's `plugin.json` contents.
  final PluginMetadata metadata;

  /// The plugin's agents, sorted by id.
  final List<PluginAgent> agents;

  /// This plugin as a JSON map.
  Map<String, dynamic> toJson() => {
    'source': source.toJson(),
    'metadata': metadata.toJson(),
    'agents': agents.map((a) => a.toJson()).toList(),
  };
}
