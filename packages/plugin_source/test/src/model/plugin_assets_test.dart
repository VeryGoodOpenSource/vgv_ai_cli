import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';

late FileSystem _fs;

SkillAsset _skill(String name) => SkillAsset(
  name: name,
  description: 'the $name skill',
  body: 'body',
  userInvocable: true,
  allowedTools: const [],
  portableFrontmatter: {'name': name},
  directory: _fs.directory('/plugins/$name'),
);

AgentAsset _agent(String name) =>
    AgentAsset(name: name, description: 'd', body: 'b', skills: const []);

HookAsset _hook(String plugin) => HookAsset(
  event: 'PreToolUse',
  plugin: plugin,
  commands: const [HookCommand(type: 'command', command: 'run.sh')],
  directory: _fs.directory('/plugins/$plugin/hooks'),
);

PluginAssets _assets({
  List<SkillAsset> skills = const [],
  List<AgentAsset> agents = const [],
  Map<String, MCPServer> mcpServers = const {},
  List<HookAsset> hooks = const [],
}) => PluginAssets(
  skills: skills,
  agents: agents,
  mcpServers: mcpServers,
  hooks: hooks,
);

void main() {
  setUp(() => _fs = MemoryFileSystem.test());

  group('PluginAssets.invocableSkills', () {
    test('keeps only the skills a user can invoke as a command', () {
      final assets = _assets(
        skills: [
          _skill('green-gate'),
          SkillAsset(
            name: 'elements-of-style',
            description: 'd',
            body: 'b',
            userInvocable: false,
            allowedTools: const [],
            portableFrontmatter: const {},
            directory: _fs.directory('/plugins/elements-of-style'),
          ),
        ],
      );

      expect(assets.invocableSkills.map((s) => s.name), ['green-gate']);
    });

    test('is empty when no skill is invocable', () {
      expect(_assets().invocableSkills, isEmpty);
    });
  });

  group('PluginAssets.merge', () {
    test('sorts skills by name across plugins', () {
      // Each plugin sorts its own, so the merged order must not depend on
      // which plugin resolved first.
      final merged = PluginAssets.merge([
        _assets(skills: [_skill('testing'), _skill('ui-package')]),
        _assets(skills: [_skill('bloc'), _skill('navigation')]),
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
        _assets(agents: [_agent('reviewer')]),
        _assets(agents: [_agent('architect')]),
      ]);

      expect(merged.agents.map((a) => a.name), ['architect', 'reviewer']);
    });

    test('keeps every hook, labelled with its own plugin', () {
      final merged = PluginAssets.merge([
        _assets(hooks: [_hook('vgv-wingspan')]),
        _assets(hooks: [_hook('vgv-ai-flutter-plugin')]),
      ]);

      expect(merged.hooks.map((h) => h.plugin), [
        'vgv-wingspan',
        'vgv-ai-flutter-plugin',
      ]);
    });

    test('combines MCP servers declared by different plugins', () {
      final merged = PluginAssets.merge([
        _assets(mcpServers: {'dart': const LocalMCPServer(command: 'dart')}),
        _assets(mcpServers: {'cli': const LocalMCPServer(command: 'vg')}),
      ]);

      expect(merged.mcpServers.keys, {'dart', 'cli'});
    });

    test('keeps the first declaration when two plugins claim one name', () {
      final merged = PluginAssets.merge([
        _assets(mcpServers: {'dart': const LocalMCPServer(command: 'first')}),
        _assets(mcpServers: {'dart': const LocalMCPServer(command: 'second')}),
      ]);

      expect((merged.mcpServers['dart']! as LocalMCPServer).command, 'first');
    });

    test('merges nothing into an empty view', () {
      final merged = PluginAssets.merge([]);

      expect(merged.skills, isEmpty);
      expect(merged.agents, isEmpty);
      expect(merged.hooks, isEmpty);
      expect(merged.mcpServers, isEmpty);
    });
  });
}
