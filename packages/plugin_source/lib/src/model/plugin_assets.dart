import 'package:plugin_source/src/model/agent_asset.dart';
import 'package:plugin_source/src/model/hook_asset.dart';
import 'package:plugin_source/src/model/mcp_server.dart';
import 'package:plugin_source/src/model/skill_asset.dart';

/// {@template plugin_assets}
/// Everything one or more plugins contribute, in a harness-neutral shape.
/// {@endtemplate}
class const PluginAssets({
  required final List<SkillAsset> skills,
  required final List<AgentAsset> agents,
  required final Map<String, MCPServer> mcpServers,
  final List<HookAsset> hooks = const [],
}) {
  /// Combines what several plugins contribute into one [PluginAssets].
  factory merge(Iterable<PluginAssets> assets) {
    final skills = [for (final a in assets) ...a.skills]
      ..sort((a, b) => a.name.compareTo(b.name));
    final agents = [for (final a in assets) ...a.agents]
      ..sort((a, b) => a.name.compareTo(b.name));

    final mcpServers = <String, MCPServer>{};
    for (final entry in assets) {
      for (final MapEntry(:key, :value) in entry.mcpServers.entries) {
        mcpServers.putIfAbsent(key, () => value);
      }
    }

    return PluginAssets(
      skills: skills,
      agents: agents,
      mcpServers: mcpServers,
      hooks: [for (final a in assets) ...a.hooks],
    );
  }

  /// The skills a user can invoke as a command.
  List<SkillAsset> get invocableSkills => [
    for (final skill in skills)
      if (skill.userInvocable) skill,
  ];
}
