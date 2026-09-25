import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/harness/translate/translate.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

import '_assets.dart';

void main() {
  late FileSystem fs;
  late Directory home;
  late PluginAssets assets;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);

    // Two plugins, merged the way install will merge them. `review` is
    // deliberately both an agent and a command name.
    assets = PluginAssets.merge([
      pluginAssets(
        skills: [skillAsset(fs, 'review'), skillAsset(fs, 'plan')],
        agents: [
          agentAsset('review', skills: ['plan']),
          agentAsset('planner'),
        ],
        mcpServers: [const LocalMCPServer(name: 'dart', command: 'dart')],
      ),
      pluginAssets(
        skills: [
          skillAsset(fs, 'testing'),
          skillAsset(fs, 'quiet', userInvocable: false),
        ],
        hooks: [hookAsset(fs)],
      ),
    ]);
  });

  Future<Map<Harness?, TranslationResult>> translate(
    Set<Harness> selected, {
    PluginAssets? using,
  }) => const Translator().translate(
    assets: using ?? assets,
    home: home,
    selected: selected,
  );

  /// Every planned path under [harness]'s config directory, relative to it.
  Future<List<String>> tree(Harness harness, {PluginAssets? using}) async {
    final results = await translate({harness}, using: using);
    final root = harness.configDirectory(home).path;
    return [
      for (final change in results[harness]!.changes)
        change.file.path.substring(root.length + 1),
    ]..sort();
  }

  group('Translator', () {
    test('lists every harness once, in reporting order', () {
      expect(harnessTranslators.map((t) => t.harness), Harness.values);
    });

    group('renders each harness what it supports and nothing else', () {
      test('Claude Code gets only the marketplace settings', () async {
        expect(await tree(Harness.claude), ['settings.json']);
      });

      test('Gemini gets settings, instructions, agents and commands', () async {
        expect(await tree(Harness.gemini), [
          'AGENTS.md',
          'agents/planner.md',
          'agents/review.md',
          'commands/plan.toml',
          'commands/review.toml',
          'commands/testing.toml',
          'settings.json',
        ]);
      });

      test('Codex gets config, instructions, agents and prompts', () async {
        expect(await tree(Harness.codex), [
          'AGENTS.md',
          'agents/planner.toml',
          'agents/review.toml',
          'config.toml',
          'prompts/plan.md',
          'prompts/review.md',
          'prompts/testing.md',
        ]);
      });

      test('OpenCode gets config, instructions, agents and commands', () async {
        expect(await tree(Harness.opencode), [
          'AGENTS.md',
          'agent/planner.md',
          'agent/review.md',
          'command/plan.md',
          'command/review.md',
          'command/testing.md',
          'opencode.json',
        ]);
      });

      test('Pi gets instructions and prompts, and no agents', () async {
        expect(await tree(Harness.pi), [
          'AGENTS.md',
          'prompts/plan.md',
          'prompts/review.md',
          'prompts/testing.md',
        ]);
      });
    });

    test('renders no nameless file when there are no agents or commands', () {
      // Mason renders an empty path loop as a file called `.md`.
      final bare = pluginAssets(
        skills: [skillAsset(fs, 'quiet', userInvocable: false)],
      );

      expect(
        tree(Harness.gemini, using: bare),
        completion(['AGENTS.md', 'settings.json']),
      );
    });

    test('merges root config files and owns everything beneath', () async {
      final results = await translate(Harness.values.toSet());
      final modes = {
        for (final result in results.values)
          for (final change in result.changes)
            change.file.path.substring(home.path.length + 1): change.mode,
      };

      expect(
        modes,
        containsPair('.claude/settings.json', ChangeMode.mergeJson),
      );
      expect(modes, containsPair('.codex/config.toml', ChangeMode.mergeToml));
      expect(
        modes,
        containsPair('.gemini/AGENTS.md', ChangeMode.mergeMarkdown),
      );
      expect(modes, containsPair('.gemini/agents/review.md', ChangeMode.own));
      expect(
        modes,
        containsPair('.agents/skills/plan/SKILL.md', ChangeMode.own),
      );
    });

    test('tags every change with the harness it configures', () async {
      final results = await translate(Harness.values.toSet());

      for (final MapEntry(key: harness, value: result) in results.entries) {
        expect(result.changes.map((c) => c.harness).toSet(), {harness});
      }
    });

    test('plans the shared skills once, when a harness reads them', () async {
      final results = await translate({Harness.gemini, Harness.pi});
      final documents = results[null]!.changes
          .where((c) => c.file.path.endsWith('SKILL.md'))
          .map((c) => c.file.path);

      expect(documents, hasLength(assets.skills.length));
      expect(results.keys, [null, Harness.gemini, Harness.pi]);
    });

    test('plans nothing when no harness is selected', () async {
      expect(await translate({}), isEmpty);
    });

    test('plans no shared skills for Claude Code alone', () async {
      expect((await translate({Harness.claude})).keys, [Harness.claude]);
    });

    test('carries each harness its own notes', () async {
      final results = await translate({Harness.claude, Harness.codex});

      expect(results[Harness.claude]!.notes, isEmpty);
      expect(results[Harness.codex]!.notes.single.subject, '1 hook(s)');
    });

    group('renders contents the harness can read', () {
      Future<String> contents(Harness harness, String relative) async {
        final results = await translate({harness});
        final path = '${harness.configDirectory(home).path}/$relative';
        return results[harness]!.changes
            .singleWhere((c) => c.file.path == path)
            .contents;
      }

      test(
        'a Gemini agent is frontmatter over the shared instructions',
        () async {
          final agent = await contents(Harness.gemini, 'agents/review.md');

          expect(frontmatterValues(agent), {
            'name': 'review',
            'description': 'reviews code',
          });
          expect(
            agent,
            endsWith(
              '---\n\nYou review code.\n\n## Required skills\n\n'
              'Load these skills from `/home/dev/.agents/skills` before you '
              'start. They are part of your instructions, not optional '
              'reading.\n\n- `plan`\n',
            ),
          );
        },
      );

      test('an OpenCode command is frontmatter over the skill body', () async {
        final command = await contents(Harness.opencode, 'command/plan.md');

        expect(command, '---\ndescription: "what it does"\n---\n\n# Body\n');
      });

      test(
        'a Codex prompt and a Pi prompt are the skill body as written',
        () async {
          expect(await contents(Harness.codex, 'prompts/plan.md'), '# Body\n');
          expect(await contents(Harness.pi, 'prompts/plan.md'), '# Body\n');
        },
      );

      test(
        'Codex agents and Gemini commands are the TOML they were given',
        () async {
          final agent = await contents(Harness.codex, 'agents/planner.toml');
          final command = await contents(Harness.gemini, 'commands/plan.toml');

          expect(TomlDocument.parse(agent).toMap()['name'], 'planner');
          expect(TomlDocument.parse(command).toMap()['prompt'], '# Body\n');
        },
      );

      test('settings arrive as the translator rendered them', () async {
        final settings = await contents(Harness.gemini, 'settings.json');

        expect(
          jsonDecode(settings),
          containsPair('mcpServers', {
            'dart': {'command': 'dart'},
          }),
        );
      });

      test('AGENTS.md indexes every skill and agent', () async {
        final instructions = await contents(Harness.gemini, 'AGENTS.md');

        expect(instructions, contains('- **quiet**: what it does\n'));
        expect(instructions, contains('- **planner**: reviews code\n'));
      });

      test('AGENTS.md says so when there is nothing to index', () async {
        final results = await translate({
          Harness.opencode,
        }, using: pluginAssets());
        final instructions = results[Harness.opencode]!.changes
            .singleWhere((c) => c.file.path.endsWith('AGENTS.md'))
            .contents;

        expect(instructions, contains('No skills are configured.'));
        expect(instructions, contains('No agents are configured.'));
      });
    });

    // The brick is checked file by file above. These sweep every file every
    // harness gets, so a template bug in a file no test names still fails.
    group('renders every file cleanly', () {
      late Map<String, String> files;

      setUp(() async {
        // Characters mustache would HTML-escape if a template used a double
        // mustache where it needs a triple one.
        const awkward = 'Compare <T> & "U" with \'V\'.';
        final results = await translate(
          Harness.values.toSet(),
          using: pluginAssets(
            skills: [
              skillAsset(fs, 'plan', body: '$awkward\n', description: awkward),
            ],
            agents: [agentAsset('review', body: '$awkward\n')],
            mcpServers: [const LocalMCPServer(name: 'dart', command: 'dart')],
          ),
        );
        files = {
          for (final result in results.values)
            for (final change in result.changes)
              change.file.path: change.contents,
        };
      });

      test('covers every harness', () {
        for (final harness in Harness.values) {
          expect(
            files.keys,
            contains(startsWith(harness.configDirectory(home).path)),
          );
        }
      });

      test('leaves no unrendered mustache behind', () {
        // A whole tag, since a JSON object nested last closes with `}}`.
        final tag = RegExp(r'\{\{[^{}]*\}\}');
        for (final MapEntry(key: path, value: contents) in files.entries) {
          expect(
            contents,
            isNot(contains(tag)),
            reason: '$path still contains mustache syntax',
          );
        }
      });

      test('writes no empty file', () {
        for (final MapEntry(key: path, value: contents) in files.entries) {
          expect(contents.trim(), isNotEmpty, reason: '$path is empty');
        }
      });

      test('never HTML-escapes', () {
        for (final MapEntry(key: path, value: contents) in files.entries) {
          expect(
            contents,
            isNot(anyOf(contains('&amp;'), contains('&lt;'), contains('&#'))),
            reason: '$path contains HTML-escaped output',
          );
        }
      });

      test('writes JSON and TOML that parse', () {
        for (final MapEntry(key: path, value: contents) in files.entries) {
          if (path.endsWith('.json')) {
            expect(() => jsonDecode(contents), returnsNormally, reason: path);
          }
          if (path.endsWith('.toml')) {
            expect(
              () => TomlDocument.parse(contents),
              returnsNormally,
              reason: path,
            );
          }
        }
      });
    });
  });
}
