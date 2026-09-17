import 'package:hooks/models/models.dart';
import 'package:mason/mason.dart';

/// Harnesses the brick understands, in reporting order.
const harnesses = <Harness>[
  Harness.claude(),
  Harness.gemini(),
  Harness.codex(),
  Harness.opencode(),
  Harness.pi(),
];

/// Plugins enabled on the Claude Code side.
const vgvPlugins = <VgvPlugin>[VgvPlugin.wingspan(), VgvPlugin.aiFlutter()];

/// Prepares the vars the `agents` templates render against.
///
/// The settings fragments are built here rather than in mustache. A template
/// loop cannot know which iteration is last, so it cannot place separators
/// correctly, and any JSON or TOML it produced would have to be re-indented
/// anyway. The templates keep what they are good at: choosing which settings
/// fragment exists per harness.
Future<void> run(HookContext context) async {
  final vars = Map<String, dynamic>.from(context.vars);

  final selected = harnesses.where((h) => vars[h.flag] == true).toList();
  if (selected.isEmpty) {
    final flags = harnesses.map((h) => h.flag).join(', ');
    context.logger.err('No harness selected. Enable at least one of: $flags.');
    throw Exception('no harness selected');
  }

  final agents = _agents(vars['agents']);
  final skills = _skills(vars['skills']);
  final mcpServers = _mcpServers(vars['mcp_servers']);
  final skillsRoot = vars['skills_root'] as String?;

  if (skillsRoot == null) {
    context.logger.err('Missing required var: skills_root.');
    throw Exception('missing required var');
  }

  final configuration = AgentsConfiguration(
    skills: skills,
    agents: agents,
    claudeSettings: ClaudeSettings.forMarketplace(
      const Marketplace.veryGood(),
      vgvPlugins,
    ),
    geminiSettings: GeminiSettings.fromServers(mcpServers),
    openCodeConfig: OpenCodeConfig.fromServers(mcpServers),
    piSettings: PiSettings([skillsRoot]),
    codexConfig: CodexConfig.fromServers(mcpServers),
  );

  context.vars = {...vars, ...configuration.toVars()};
}

List<Skill> _skills(Object? value) =>
    _listOfMaps(value).map(Skill.fromJson).toList();

List<Agent> _agents(Object? value) =>
    _listOfMaps(value).map(Agent.fromJson).toList();

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<dynamic, dynamic>>()
      .map(Map<String, dynamic>.from)
      .toList();
}

Map<String, McpServer> _mcpServers(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in value.entries)
      if (value is Map) '$key': McpServer.fromVars(value),
  };
}
