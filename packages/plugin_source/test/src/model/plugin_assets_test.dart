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

HookAsset _hook(String event) => HookAsset(
  event: event,
  commands: const [HookCommand(type: 'command', command: 'run.sh')],
  plugin: 'hooks',
  pluginRoot: _fs.directory('/plugins/hooks'),
);

PluginAssets _assets({
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

    test('keeps the first skill of a name two plugins share', () {
      final first = _skill('testing');
      final merged = PluginAssets.merge([
        _assets(skills: [first]),
        _assets(skills: [_skill('testing')]),
      ]);

      expect(merged.skills, [same(first)]);
    });

    test('keeps the first agent of a name two plugins share', () {
      final first = _agent('reviewer');
      final merged = PluginAssets.merge([
        _assets(agents: [first]),
        _assets(agents: [_agent('reviewer')]),
      ]);

      expect(merged.agents, [same(first)]);
    });

    test('keeps every hook from every plugin', () {
      final merged = PluginAssets.merge([
        _assets(hooks: [_hook('PreToolUse')]),
        _assets(hooks: [_hook('PostToolUse')]),
      ]);

      expect(merged.hooks.map((h) => h.event), ['PreToolUse', 'PostToolUse']);
    });

    test('combines MCP servers declared by different plugins', () {
      final merged = PluginAssets.merge([
        _assets(
          mcpServers: [const LocalMCPServer(name: 'dart', command: 'dart')],
        ),
        _assets(
          mcpServers: [const LocalMCPServer(name: 'cli', command: 'vg')],
        ),
      ]);

      // Sorted by name, like skills and agents.
      expect(merged.mcpServers.map((server) => server.name), ['cli', 'dart']);
    });

    test('keeps the first declaration when two plugins claim one name', () {
      final merged = PluginAssets.merge([
        _assets(
          mcpServers: [const LocalMCPServer(name: 'dart', command: 'first')],
        ),
        _assets(
          mcpServers: [const LocalMCPServer(name: 'dart', command: 'second')],
        ),
      ]);

      expect(merged.mcpServers, hasLength(1));
      expect((merged.mcpServers.single as LocalMCPServer).command, 'first');
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
