import 'package:plugin_source/src/model/agent_asset.dart';
import 'package:plugin_source/src/model/hook_asset.dart';
import 'package:plugin_source/src/model/mcp_server.dart';
import 'package:plugin_source/src/model/skill_asset.dart';
import 'package:plugin_source/src/plugin_ref.dart';

/// {@template plugin_assets}
/// Everything one or more plugins contribute, in a harness-neutral shape.
/// {@endtemplate}
class const PluginAssets({
  /// The skills, sorted by name.
  required final List<SkillAsset> skills,

  /// The subagents, sorted by name.
  required final List<AgentAsset> agents,

  /// The MCP servers, sorted by name once merged.
  required final List<MCPServer> mcpServers,

  /// The hooks, in the order the plugins declare them.
  final List<HookAsset> hooks = const [],

  /// The plugins these come from, which the harness that installs them
  /// itself names in its settings.
  final List<PluginRef> plugins = const [],
}) {
  /// Combines what the [plugins] contribute into one [PluginAssets].
  ///
  /// Each skill, agent and MCP server is written to a path or key derived
  /// from its name, so the first declaration of a name wins and a later one
  /// is dropped rather than planned as a second write to the same place.
  factory merge(
    Iterable<PluginAssets> assets, {
    List<PluginRef> plugins = const [],
  }) => PluginAssets(
    skills: _firstByName([for (final a in assets) ...a.skills], (s) => s.name),
    agents: _firstByName([for (final a in assets) ...a.agents], (a) => a.name),
    mcpServers: _firstByName([
      for (final a in assets) ...a.mcpServers,
    ], (s) => s.name),
    hooks: [for (final a in assets) ...a.hooks],
    plugins: plugins,
  );

  /// The skills a user can invoke as a command.
  List<SkillAsset> get invocableSkills => [
    for (final skill in skills)
      if (skill.userInvocable) skill,
  ];
}

/// The first of [items] for each name, sorted by name.
List<T> _firstByName<T>(List<T> items, String Function(T) nameOf) {
  final byName = <String, T>{};
  for (final item in items) {
    byName.putIfAbsent(nameOf(item), () => item);
  }
  return byName.values.toList()..sort((a, b) => nameOf(a).compareTo(nameOf(b)));
}
