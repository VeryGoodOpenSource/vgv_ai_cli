import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';

void main() {
  late FileSystem fs;

  SkillAsset skill(String name) => SkillAsset(
    name: name,
    description: 'the $name skill',
    body: 'body',
    userInvocable: true,
    allowedTools: const [],
    portableFrontmatter: {'name': name},
    directory: fs.directory('/plugins/$name'),
  );

  AgentAsset agent(String name) =>
      AgentAsset(name: name, description: 'd', body: 'b', skills: const []);

  HookAsset hook(String event) => HookAsset(
    event: event,
    commands: const [HookCommand(type: 'command', command: 'run.sh')],
    plugin: 'hooks',
    pluginRoot: fs.directory('/plugins/hooks'),
  );

  PluginAssets pluginAssets({
    List<SkillAsset> skills = const [],
    List<AgentAsset> agents = const [],
    List<MCPServer> mcpServers = const [],
    List<HookAsset> hooks = const [],
  }) => PluginAssets(
    skills: skills,
    agents: agents,
    mcpServers: mcpServers,
    hooks: hooks,
  );

  setUp(() => fs = MemoryFileSystem.test());

  group(PluginAssets, () {
    group('invocableSkills', () {
      test('keeps only the skills a user can invoke as a command', () {
        final assets = pluginAssets(
          skills: [
            skill('green-gate'),
            SkillAsset(
              name: 'elements-of-style',
              description: 'd',
              body: 'b',
              userInvocable: false,
              allowedTools: const [],
              portableFrontmatter: const {},
              directory: fs.directory('/plugins/elements-of-style'),
            ),
          ],
        );

        expect(assets.invocableSkills.map((s) => s.name), ['green-gate']);
      });

      test('is empty when no skill is invocable', () {
        expect(pluginAssets().invocableSkills, isEmpty);
      });
    });

    group('merge', () {
      test('sorts skills by name across plugins', () {
        // Each plugin sorts its own, so the merged order must not depend on
        // which plugin resolved first.
        final merged = PluginAssets.merge([
          pluginAssets(skills: [skill('testing'), skill('ui-package')]),
          pluginAssets(skills: [skill('bloc'), skill('navigation')]),
        ]);

        expect(merged.skills.map((s) => s.name), [
          'bloc',
          'navigation',
          'testing',
          'ui-package',
        ]);
      });

      test('sorts agents by name across plugins', () {
        final merged = PluginAssets.merge([
          pluginAssets(agents: [agent('reviewer')]),
          pluginAssets(agents: [agent('architect')]),
        ]);

        expect(merged.agents.map((a) => a.name), ['architect', 'reviewer']);
      });

      test('keeps the first skill of a name two plugins share', () {
        final first = skill('testing');
        final merged = PluginAssets.merge([
          pluginAssets(skills: [first]),
          pluginAssets(skills: [skill('testing')]),
        ]);

        expect(merged.skills, [same(first)]);
      });

      test('keeps the first agent of a name two plugins share', () {
        final first = agent('reviewer');
        final merged = PluginAssets.merge([
          pluginAssets(agents: [first]),
          pluginAssets(agents: [agent('reviewer')]),
        ]);

        expect(merged.agents, [same(first)]);
      });

      test('keeps every hook from every plugin', () {
        final merged = PluginAssets.merge([
          pluginAssets(hooks: [hook('PreToolUse')]),
          pluginAssets(hooks: [hook('PostToolUse')]),
        ]);

        expect(merged.hooks.map((h) => h.event), ['PreToolUse', 'PostToolUse']);
      });

      test('combines MCP servers declared by different plugins', () {
        final merged = PluginAssets.merge([
          pluginAssets(
            mcpServers: [const LocalMCPServer(name: 'dart', command: 'dart')],
          ),
          pluginAssets(
            mcpServers: [const LocalMCPServer(name: 'cli', command: 'vg')],
          ),
        ]);

        // Sorted by name, like skills and agents.
        expect(merged.mcpServers.map((server) => server.name), ['cli', 'dart']);
      });

      test('keeps the first declaration when two plugins claim one name', () {
        final merged = PluginAssets.merge([
          pluginAssets(
            mcpServers: [const LocalMCPServer(name: 'dart', command: 'first')],
          ),
          pluginAssets(
            mcpServers: [const LocalMCPServer(name: 'dart', command: 'second')],
          ),
        ]);

        expect(merged.mcpServers, [
          isA<LocalMCPServer>().having((s) => s.command, 'command', 'first'),
        ]);
      });

      test('merges nothing into an empty view', () {
        final merged = PluginAssets.merge([]);

        expect(merged.skills, isEmpty);
        expect(merged.agents, isEmpty);
        expect(merged.hooks, isEmpty);
        expect(merged.mcpServers, isEmpty);
      });
    });
  });
}
