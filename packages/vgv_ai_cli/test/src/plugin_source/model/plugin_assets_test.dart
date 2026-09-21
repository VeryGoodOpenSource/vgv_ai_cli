import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugin_source/model/model.dart';

void main() {
  final fs = MemoryFileSystem();

  SkillAsset skill(String name, {String description = ''}) => SkillAsset(
    name: name,
    description: description,
    body: '',
    userInvocable: true,
    allowedTools: const [],
    portableFrontmatter: const {},
    directory: fs.directory(name),
  );

  AgentAsset agent(String name, {String description = ''}) => AgentAsset(
    name: name,
    description: description,
    body: '',
    skills: const [],
  );

  HookAsset hook(String event, String command) => HookAsset(
    event: event,
    commands: [HookCommand(type: 'command', command: command)],
    directory: fs.directory('hooks'),
  );

  group('PluginAssets.merge', () {
    test('combines the assets of two plugins', () {
      final merged =
          PluginAssets(
            skills: [skill('a')],
            agents: [agent('x')],
            mcpServers: const {'dart': LocalMCPServer(command: 'dart')},
            hooks: [hook('PostToolUse', 'a.sh')],
          ).merge(
            PluginAssets(
              skills: [skill('b')],
              agents: [agent('y')],
              mcpServers: const {
                'context7': RemoteMCPServer(url: 'https://c7'),
              },
              hooks: [hook('SessionStart', 'b.sh')],
            ),
          );

      expect(merged.skills.map((s) => s.name), ['a', 'b']);
      expect(merged.agents.map((a) => a.name), ['x', 'y']);
      expect(merged.mcpServers.keys, unorderedEquals(['dart', 'context7']));
      expect(merged.hooks, hasLength(2));
    });

    test('lets the later plugin win a skill name clash', () {
      final merged =
          PluginAssets(
            skills: [skill('testing', description: 'earlier')],
            agents: const [],
            mcpServers: const {},
          ).merge(
            PluginAssets(
              skills: [skill('testing', description: 'later')],
              agents: const [],
              mcpServers: const {},
            ),
          );

      expect(merged.skills, hasLength(1));
      expect(merged.skills.single.description, 'later');
    });

    test('lets the later plugin win an agent name clash', () {
      final merged =
          PluginAssets(
            skills: const [],
            agents: [agent('reviewer', description: 'earlier')],
            mcpServers: const {},
          ).merge(
            PluginAssets(
              skills: const [],
              agents: [agent('reviewer', description: 'later')],
              mcpServers: const {},
            ),
          );

      expect(merged.agents, hasLength(1));
      expect(merged.agents.single.description, 'later');
    });

    test('lets the later plugin win an mcpServers key clash', () {
      final merged =
          const PluginAssets(
            skills: [],
            agents: [],
            mcpServers: {'dart': LocalMCPServer(command: 'earlier')},
          ).merge(
            const PluginAssets(
              skills: [],
              agents: [],
              mcpServers: {'dart': LocalMCPServer(command: 'later')},
            ),
          );

      expect(merged.mcpServers, hasLength(1));
      expect((merged.mcpServers['dart']! as LocalMCPServer).command, 'later');
    });

    test('concatenates hooks instead of resolving them by event', () {
      // Both plugins register PostToolUse and both must still run.
      final merged =
          PluginAssets(
            skills: const [],
            agents: const [],
            mcpServers: const {},
            hooks: [hook('PostToolUse', 'a.sh')],
          ).merge(
            PluginAssets(
              skills: const [],
              agents: const [],
              mcpServers: const {},
              hooks: [hook('PostToolUse', 'b.sh')],
            ),
          );

      expect(merged.hooks.map((h) => h.commands.single.command), [
        'a.sh',
        'b.sh',
      ]);
    });

    test('keeps skills and agents sorted by name', () {
      final merged =
          PluginAssets(
            skills: [skill('b'), skill('d')],
            agents: [agent('y')],
            mcpServers: const {},
          ).merge(
            PluginAssets(
              skills: [skill('a'), skill('c')],
              agents: [agent('x')],
              mcpServers: const {},
            ),
          );

      expect(merged.skills.map((s) => s.name), ['a', 'b', 'c', 'd']);
      expect(merged.agents.map((a) => a.name), ['x', 'y']);
    });

    test('empty is a neutral starting point', () {
      final assets = PluginAssets(
        skills: [skill('a')],
        agents: [agent('x')],
        mcpServers: const {'dart': LocalMCPServer(command: 'dart')},
        hooks: [hook('PostToolUse', 'a.sh')],
      );

      final merged = PluginAssets.empty.merge(assets);

      expect(merged.skills, assets.skills);
      expect(merged.agents, assets.agents);
      expect(merged.mcpServers, assets.mcpServers);
      expect(merged.hooks, assets.hooks);
    });
  });
}
