import 'package:vgv_ai_cli/src/plugin_source/model/agent_asset.dart';
import 'package:vgv_ai_cli/src/plugin_source/model/hook.dart';
import 'package:vgv_ai_cli/src/plugin_source/model/mcp_server.dart';
import 'package:vgv_ai_cli/src/plugin_source/model/skill_asset.dart';

/// {@template plugin_assets}
/// Everything one or more plugins contribute, in a harness-neutral shape.
/// {@endtemplate}
class const PluginAssets({
  required final List<SkillAsset> skills,
  required final List<AgentAsset> agents,
  required final Map<String, McpServer> mcpServers,
  final List<HookAsset> hooks = const [],
}) {
  /// An empty set of assets.
  static const empty = PluginAssets(
    skills: [],
    agents: [],
    mcpServers: <String, McpServer>{},
  );

  /// Combines [other] into these assets.
  ///
  /// Later plugins win on a name clash, matching the order they are listed in.
  /// There are no clashes between the two VGV plugins today.
  /// Hooks are the exception: they concatenate rather than resolve by name.
  /// Two plugins both registering `PreToolUse` both want to run, so dropping
  /// one would silently disable it.
  PluginAssets merge(PluginAssets other) => PluginAssets(
    skills: _mergeByName(skills, other.skills, (skill) => skill.name),
    agents: _mergeByName(agents, other.agents, (agent) => agent.name),
    mcpServers: {...mcpServers, ...other.mcpServers},
    hooks: [...hooks, ...other.hooks],
  );

  /// Later entries win a name clash, and the result stays sorted by name so
  /// merging cannot lose the ordering the parser establishes.
  static List<T> _mergeByName<T>(
    List<T> a,
    List<T> b,
    String Function(T) name,
  ) {
    final byName = <String, T>{for (final item in a) name(item): item};
    for (final item in b) {
      byName[name(item)] = item;
    }
    final merged = byName.values.toList()
      ..sort((x, y) => name(x).compareTo(name(y)));
    return merged;
  }
}
