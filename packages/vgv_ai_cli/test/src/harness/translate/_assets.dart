import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';

/// Builders shared by the per-harness translator tests, so each test file
/// asserts on translation rather than on fixture construction.
SkillAsset skillAsset(
  FileSystem fs,
  String name, {
  String body = '# Body\n',
  String description = 'what it does',
  bool userInvocable = true,
}) => SkillAsset(
  name: name,
  description: description,
  body: body,
  userInvocable: userInvocable,
  allowedTools: const [],
  portableFrontmatter: {'name': name, 'description': description},
  directory: fs.directory('/plugins/wingspan/skills/$name')
    ..createSync(recursive: true),
);

AgentAsset agentAsset(
  String name, {
  String body = 'You review code.\n',
  String description = 'reviews code',
  List<String> skills = const [],
}) => AgentAsset(
  name: name,
  description: description,
  body: body,
  skills: skills,
);

PluginAssets pluginAssets({
  List<SkillAsset> skills = const [],
  List<AgentAsset> agents = const [],
}) => PluginAssets(skills: skills, agents: agents, mcpServers: const {});
