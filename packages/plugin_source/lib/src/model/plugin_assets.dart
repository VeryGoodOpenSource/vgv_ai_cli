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
});
