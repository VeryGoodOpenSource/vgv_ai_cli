import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

import '_assets.dart';

void main() {
  group(Translator, () {
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

    Future<TranslationPlan> translate(
      Set<Harness> selected, {
      PluginAssets? using,
      Scope? scope,
      List<PluginDirectory> plugins = const [],
    }) => const Translator().translate(
      assets: using ?? assets,
      scope: scope ?? UserScope(home),
      selected: selected,
      plugins: plugins,
    );

    /// Every planned path under [harness]'s config directory, relative to it.
    Future<List<String>> tree(Harness harness, {PluginAssets? using}) async {
      final plan = await translate({harness}, using: using);
      final root = harness.configDirectory(home).path;
      return [
        for (final change in plan.harnesses[harness]!.changes)
          if (change.file.path.startsWith('$root/'))
            change.file.path.substring(root.length + 1),
      ]..sort();
    }

    /// Parses [contents] as the JSON or TOML that [path] names.
    Object? parseStructured(String path, String contents) =>
        path.endsWith('.json')
        ? jsonDecode(contents)
        : TomlDocument.parse(contents);

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

      test('Codex gets config, instructions, agents and hooks', () async {
        expect(await tree(Harness.codex), [
          'AGENTS.md',
          'agents/planner.toml',
          'agents/review.toml',
          'config.toml',
          'hooks.json',
          'hooks/${CodexTranslator.compatScript}',
          'hooks/vgv-wingspan/hooks/scripts/analyze.sh',
          'hooks/vgv-wingspan/hooks/scripts/common.sh',
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

      test('Copilot gets MCP config, instructions, agents and hooks', () async {
        expect(await tree(Harness.copilot), [
          'agents/planner.agent.md',
          'agents/review.agent.md',
          'copilot-instructions.md',
          'hooks/vgv.json',
          'mcp-config.json',
          'vgv_ai/hooks/${CopilotTranslator.compatScript}',
          'vgv_ai/hooks/vgv-wingspan/hooks/scripts/analyze.sh',
          'vgv_ai/hooks/vgv-wingspan/hooks/scripts/common.sh',
        ]);
      });

      test('Antigravity gets one plugin holding everything', () async {
        expect(await tree(Harness.antigravity), [
          'plugins/vgv/agents/planner.md',
          'plugins/vgv/agents/review.md',
          'plugins/vgv/hooks.json',
          'plugins/vgv/hooks/${AntigravityTranslator.compatScript}',
          'plugins/vgv/hooks/vgv-wingspan/hooks/scripts/analyze.sh',
          'plugins/vgv/hooks/vgv-wingspan/hooks/scripts/common.sh',
          'plugins/vgv/mcp_config.json',
          'plugins/vgv/plugin.json',
          'plugins/vgv/skills/plan/SKILL.md',
          'plugins/vgv/skills/quiet/SKILL.md',
          'plugins/vgv/skills/review/SKILL.md',
          'plugins/vgv/skills/testing/SKILL.md',
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
      final plan = await translate(Harness.values.toSet());
      final modes = {
        for (final change in plan.changes)
          change.file.path.substring(home.path.length + 1): change.mode,
      };

      expect(
        modes,
        containsPair('.claude/settings.json', ChangeMode.mergeJson),
      );
      expect(modes, containsPair('.codex/config.toml', ChangeMode.mergeToml));
      expect(
        modes,
        containsPair('.copilot/mcp-config.json', ChangeMode.mergeJson),
      );
      expect(modes, containsPair('.copilot/hooks/vgv.json', ChangeMode.own));
      expect(
        modes,
        containsPair(
          '.copilot/copilot-instructions.md',
          ChangeMode.mergeMarkdown,
        ),
      );
      expect(
        modes,
        containsPair('.gemini/AGENTS.md', ChangeMode.mergeMarkdown),
      );
      expect(modes, containsPair('.gemini/agents/review.md', ChangeMode.own));
      expect(
        modes,
        containsPair('.agents/skills/plan/SKILL.md', ChangeMode.own),
      );
      expect(
        modes,
        containsPair('.gemini/config/plugins/vgv/plugin.json', ChangeMode.own),
      );
    });

    test('tags every change with the harness it configures', () async {
      final plan = await translate(Harness.values.toSet());

      expect(plan.shared!.changes.map((c) => c.harness).toSet(), {null});
      for (final MapEntry(key: harness, value: result)
          in plan.harnesses.entries) {
        expect(result.changes.map((c) => c.harness).toSet(), {harness});
      }
    });

    test('plans the shared skills once, when a harness reads them', () async {
      final plan = await translate({Harness.gemini, Harness.pi});
      final documents = plan.shared!.changes
          .where((c) => c.file.path.endsWith('SKILL.md'))
          .map((c) => c.file.path);

      expect(documents, hasLength(assets.skills.length));
      expect(plan.harnesses.keys, [Harness.gemini, Harness.pi]);
    });

    test('plans nothing when no harness is selected', () async {
      final plan = await translate({});

      expect(plan.shared, isNull);
      expect(plan.harnesses, isEmpty);
    });

    test('plans no shared skills for Claude Code alone', () async {
      final plan = await translate({Harness.claude});

      expect(plan.shared, isNull);
      expect(plan.harnesses.keys, [Harness.claude]);
    });

    test(
      'plans Antigravity its own copy of the skills, not the shared one',
      () async {
        final plan = await translate({Harness.antigravity});
        final documents = plan.harnesses[Harness.antigravity]!.changes
            .where((c) => c.file.path.endsWith('SKILL.md'))
            .map((c) => c.harness);

        expect(plan.shared, isNull);
        expect(documents, everyElement(Harness.antigravity));
        expect(documents, hasLength(assets.skills.length));
      },
    );

    test('carries each harness its own notes', () async {
      final plan = await translate({Harness.claude, Harness.pi});

      expect(plan.harnesses[Harness.claude]!.notes, isEmpty);
      expect(plan.harnesses[Harness.pi]!.notes.last.subject, '1 hook(s)');
    });

    test('tells a harness that runs no hooks so, once', () async {
      final plan = await translate({Harness.gemini});

      expect(
        plan.harnesses[Harness.gemini]!.notes.single.reason,
        contains("nothing in Gemini's config runs one"),
      );
    });

    group('in a project', () {
      late Scope project;

      setUp(() => project = ProjectScope(fs.directory('/work/app')));

      /// Every path [harness] plans in the project, relative to it.
      Future<List<String>> projectTree(
        Harness harness, {
        PluginAssets? using,
      }) async {
        final plan = await translate({harness}, using: using, scope: project);
        return [
          for (final change in plan.harnesses[harness]!.changes)
            fs.path.relative(change.file.path, from: project.root.path),
        ]..sort();
      }

      PlannedChange changeAt(TranslationPlan plan, String path) =>
          plan.changes.singleWhere((c) => c.file.path == '/work/app/$path');

      test('Claude Code gets only the marketplace settings', () async {
        expect(await projectTree(Harness.claude), ['.claude/settings.json']);
      });

      test('Gemini gets settings, agents and commands', () async {
        expect(await projectTree(Harness.gemini), [
          '.gemini/agents/planner.md',
          '.gemini/agents/review.md',
          '.gemini/commands/plan.toml',
          '.gemini/commands/review.toml',
          '.gemini/commands/testing.toml',
          '.gemini/settings.json',
        ]);
      });

      test("Gemini's settings only point it at AGENTS.md", () async {
        final plan = await translate({Harness.gemini}, scope: project);
        final settings = changeAt(plan, '.gemini/settings.json');

        expect(settings.mode, ChangeMode.mergeJson);
        expect(jsonDecode(settings.contents), {
          'context': {
            'fileName': ['AGENTS.md', 'GEMINI.md'],
          },
        });
      });

      test('an agent points at the skills relative to the project', () async {
        final plan = await translate({Harness.gemini}, scope: project);

        expect(
          changeAt(plan, '.gemini/agents/review.md').contents,
          contains('`.agents/skills`'),
        );
      });

      test('Codex gets agents', () async {
        expect(await projectTree(Harness.codex), [
          '.codex/agents/planner.toml',
          '.codex/agents/review.toml',
        ]);
      });

      test("Codex's policy lands beside the project's skills", () async {
        final plan = await translate(
          {Harness.codex},
          using: pluginAssets(
            skills: [skillAsset(fs, 'create-pr', disableModelInvocation: true)],
          ),
          scope: project,
        );

        expect(plan.harnesses[Harness.codex]!.changes.map((c) => c.file.path), [
          '/work/app/.agents/skills/create-pr/${CodexTranslator.metadata}',
        ]);
      });

      test('Codex is told to trust the project for its agents', () async {
        final plan = await translate({Harness.codex}, scope: project);

        expect(
          plan.harnesses[Harness.codex]!.notes.map((n) => n.subject),
          contains('2 agent(s) in .codex/agents'),
        );
      });

      test('Codex needs no trust note without agents', () async {
        final plan = await translate(
          {Harness.codex},
          using: pluginAssets(),
          scope: project,
        );

        expect(plan.harnesses[Harness.codex]!.notes, isEmpty);
      });

      test('OpenCode gets agents and commands', () async {
        expect(await projectTree(Harness.opencode), [
          '.opencode/agents/planner.md',
          '.opencode/agents/review.md',
          '.opencode/commands/plan.md',
          '.opencode/commands/review.md',
          '.opencode/commands/testing.md',
        ]);
      });

      test('Pi gets prompts, and no agents', () async {
        expect(await projectTree(Harness.pi), [
          '.pi/prompts/plan.md',
          '.pi/prompts/review.md',
          '.pi/prompts/testing.md',
        ]);
      });

      test('Pi is told to trust the project for its skills', () async {
        final plan = await translate({Harness.pi}, scope: project);

        expect(
          plan.harnesses[Harness.pi]!.notes.map((n) => n.subject),
          contains("the project's skills and prompts"),
        );
      });

      test('Pi needs no trust note without skills', () async {
        final plan = await translate(
          {Harness.pi},
          using: pluginAssets(),
          scope: project,
        );

        expect(plan.harnesses[Harness.pi]!.notes, isEmpty);
      });

      test('Pi gets one note for its MCP servers, its own', () async {
        final plan = await translate({Harness.pi}, scope: project);

        final mcp = plan.harnesses[Harness.pi]!.notes.where(
          (n) => n.subject == '1 MCP server(s)',
        );
        expect(mcp.single.reason, contains('Pi has no MCP support'));
      });

      test('writes no instructions file for any harness', () async {
        final plan = await translate(Harness.values.toSet(), scope: project);

        expect(
          plan.changes.map((c) => fs.path.basename(c.file.path)),
          everyElement(
            isNot(
              anyOf(
                'AGENTS.md',
                'GEMINI.md',
                'CLAUDE.md',
                'copilot-instructions.md',
              ),
            ),
          ),
        );
        expect(
          plan.changes.map((c) => c.mode),
          everyElement(isNot(ChangeMode.mergeMarkdown)),
        );
      });

      test('Copilot gets agents', () async {
        expect(await projectTree(Harness.copilot), [
          '.github/agents/planner.agent.md',
          '.github/agents/review.agent.md',
        ]);
      });

      test('plans no hook files', () async {
        final plan = await translate({Harness.codex}, scope: project);

        expect(
          plan.changes.map((c) => c.file.path),
          everyElement(isNot(contains('hooks'))),
        );
      });

      test(
        'tells a harness that runs hooks they wait, with its MCP servers',
        () async {
          final plan = await translate({Harness.codex}, scope: project);

          final waiting = plan.harnesses[Harness.codex]!.notes.where(
            (n) => n.subject == '1 hook(s)' || n.subject == '1 MCP server(s)',
          );
          expect(waiting, hasLength(2));
          expect(
            waiting.map((n) => n.reason),
            everyElement(contains('issues/140')),
          );
        },
      );

      test('tells a harness that runs no hooks so, as at home', () async {
        final plan = await translate({Harness.opencode}, scope: project);

        expect(
          plan.harnesses[Harness.opencode]!.notes
              .singleWhere((n) => n.subject == '1 hook(s)')
              .reason,
          contains("nothing in OpenCode's config runs one"),
        );
      });

      test('says nothing of hooks or MCP servers the plugins lack', () async {
        final plan = await translate(
          {Harness.opencode},
          using: pluginAssets(),
          scope: project,
        );

        expect(plan.harnesses[Harness.opencode]!.notes, isEmpty);
      });

      test("adds a harness's own project notes", () async {
        final plan = await translate({Harness.gemini}, scope: project);

        expect(
          plan.harnesses[Harness.gemini]!.notes.map((n) => n.subject),
          contains("the project's .gemini folder"),
        );
      });

      test('adds no project notes at home', () async {
        final plan = await translate({Harness.gemini});

        expect(
          plan.harnesses[Harness.gemini]!.notes.map((n) => n.subject),
          isNot(contains("the project's .gemini folder")),
        );
      });

      group('plugin files', () {
        late List<PluginDirectory> plugins;

        setUp(() {
          fs.file('/cache/ffca/references/x.md')
            ..createSync(recursive: true)
            ..writeAsStringSync('x');
          plugins = [
            PluginDirectory(
              plugin: const PluginRef(
                name: 'ffca',
                repo: 'acme/ffca',
                version: '1.0.0',
                gitRef: 'v1.0.0',
              ),
              directory: fs.directory('/cache/ffca'),
              referencedEntries: const ['references'],
            ),
          ];
        });

        const copy = '/work/app/.vgv_ai/plugins/ffca@v1.0.0/references/x.md';

        test('are copied beside the shared skills', () async {
          final plan = await translate(
            {Harness.gemini},
            scope: project,
            plugins: plugins,
          );

          expect(plan.shared!.changes.map((c) => c.file.path), contains(copy));
          expect(
            plan.shared!.changes.map((c) => c.file.path),
            contains('/work/app/.agents/skills/review/SKILL.md'),
          );
        });

        test('are copied for a harness that keeps its own skills', () async {
          final plan = await translate(
            {Harness.antigravity},
            scope: project,
            plugins: plugins,
          );

          expect(plan.shared!.changes.map((c) => c.file.path).single, copy);
        });

        test('are not copied for Claude Code, which installs them', () async {
          final plan = await translate(
            {Harness.claude},
            scope: project,
            plugins: plugins,
          );

          expect(plan.shared, isNull);
        });

        test(
          'are not copied at home, where bodies read them in place',
          () async {
            final plan = await translate({Harness.gemini}, plugins: plugins);

            expect(
              plan.changes.map((c) => c.file.path),
              everyElement(isNot(contains('.vgv_ai'))),
            );
          },
        );
      });

      test('says nothing to Claude Code, which installs both', () async {
        final plan = await translate({Harness.claude}, scope: project);

        expect(plan.harnesses[Harness.claude]!.notes, isEmpty);
      });
    });

    group('a skill only the user may start', () {
      late PluginAssets userOnly;

      setUp(() {
        userOnly = pluginAssets(
          skills: [
            skillAsset(fs, 'create-pr', disableModelInvocation: true),
            skillAsset(fs, 'testing'),
          ],
        );
      });

      test(
        'is named in a note for each harness that cannot keep it so',
        () async {
          final unguarded = Harness.values.toSet()
            ..removeAll({Harness.claude, Harness.codex});

          final plan = await translate(unguarded, using: userOnly);

          for (final harness in unguarded) {
            final note = plan.harnesses[harness]!.notes.single;
            expect(note.subject, 'the create-pr skill');
            expect(
              note.reason,
              contains("${harness.displayName}'s config stops the model"),
            );
          }
        },
      );

      test('needs no note for Claude Code or Codex', () async {
        final plan = await translate({
          Harness.claude,
          Harness.codex,
        }, using: userOnly);

        expect(plan.harnesses[Harness.claude]!.notes, isEmpty);
        expect(plan.harnesses[Harness.codex]!.notes, isEmpty);
      });

      test("carries Codex's policy beside the shared copy", () async {
        final plan = await translate({Harness.codex}, using: userOnly);

        final policy = plan.harnesses[Harness.codex]!.changes.singleWhere(
          (c) => c.file.path.endsWith(CodexTranslator.metadata),
        );
        expect(
          policy.file.path,
          '/home/dev/.agents/skills/create-pr/${CodexTranslator.metadata}',
        );
        expect(policy.harness, Harness.codex);
      });

      test('leaves the shared copy without the policy for others', () async {
        final plan = await translate({Harness.gemini}, using: userOnly);

        expect(
          plan.changes.map((c) => c.file.path),
          isNot(contains(endsWith(CodexTranslator.metadata))),
        );
      });
    });

    group('renders contents the harness can read', () {
      Future<String> contents(Harness harness, String relative) async {
        final plan = await translate({harness});
        final path = '${harness.configDirectory(home).path}/$relative';
        return plan.harnesses[harness]!.changes
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

      test('a Pi prompt is the skill body as written', () async {
        expect(await contents(Harness.pi, 'prompts/plan.md'), '# Body\n');
      });

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

      test(
        "Codex's hooks merge into the ones the user already keeps",
        () async {
          final copy = p.join(
            harnessHooksRoot(Harness.codex, home: home).path,
            'vgv-wingspan',
          );
          final plan = await translate({Harness.codex});
          final hooks = plan.harnesses[Harness.codex]!.changes.singleWhere(
            (change) => change.file.path.endsWith('hooks.json'),
          );

          expect(hooks.mode, ChangeMode.mergeJson);
          expect(jsonDecode(hooks.contents), {
            'hooks': {
              'PostToolUse': [
                {
                  'hooks': [
                    {
                      'type': 'command',
                      'command': 'bash "$copy"/hooks/scripts/analyze.sh',
                      'timeout': 30,
                    },
                  ],
                },
              ],
            },
          });
        },
      );

      test(
        'an Antigravity agent names its skills and keeps its body',
        () async {
          final agent = await contents(
            Harness.antigravity,
            'plugins/vgv/agents/review.md',
          );

          expect(frontmatterValues(agent)['skills'], ['skills/plan']);
          expect(agent, endsWith('---\n\nYou review code.\n'));
        },
      );

      test('AGENTS.md indexes every skill and agent', () async {
        final instructions = await contents(Harness.gemini, 'AGENTS.md');

        expect(instructions, contains('- **quiet**: what it does\n'));
        expect(instructions, contains('- **planner**: reviews code\n'));
      });

      test("Pi's AGENTS.md indexes the skills but no agents", () async {
        // Pi has no subagents, so pointing it at one would be advice it
        // cannot follow.
        final instructions = await contents(Harness.pi, 'AGENTS.md');

        expect(instructions, contains('- **quiet**: what it does\n'));
        expect(instructions, isNot(contains('## Agents')));
        expect(instructions, isNot(contains('planner')));
      });

      test('AGENTS.md says so when there is nothing to index', () async {
        final plan = await translate({Harness.opencode}, using: pluginAssets());
        final instructions = plan.harnesses[Harness.opencode]!.changes
            .singleWhere((c) => c.file.path.endsWith('AGENTS.md'))
            .contents;

        expect(instructions, contains('No skills are configured.'));
        expect(instructions, contains('No agents are configured.'));
      });
    });

    // The brick is checked file by file above. These sweep every file every
    // harness gets, so a template bug in a file no test names still fails.
    for (final inProject in [false, true]) {
      group('renders every ${inProject ? 'project' : 'user'} file cleanly', () {
        late Map<String, String> files;

        setUp(() async {
          // Characters mustache would HTML-escape if a template used a double
          // mustache where it needs a triple one.
          const awkward = 'Compare <T> & "U" with \'V\'.';
          final plan = await translate(
            Harness.values.toSet(),
            using: pluginAssets(
              skills: [
                skillAsset(
                  fs,
                  'plan',
                  body: '$awkward\n',
                  description: awkward,
                ),
              ],
              agents: [agentAsset('review', body: '$awkward\n')],
              mcpServers: [const LocalMCPServer(name: 'dart', command: 'dart')],
            ),
            scope: inProject ? ProjectScope(fs.directory('/work/app')) : null,
          );
          files = {
            for (final change in plan.changes)
              change.file.path: change.contents,
          };
        });

        if (!inProject) {
          test('covers every harness', () {
            for (final harness in Harness.values) {
              expect(
                files.keys,
                contains(startsWith(harness.configDirectory(home).path)),
              );
            }
          });
        }

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
          final structured = files.entries.where(
            (file) => file.key.endsWith('.json') || file.key.endsWith('.toml'),
          );

          expect(structured, isNotEmpty);
          for (final MapEntry(key: path, value: contents) in structured) {
            expect(
              () => parseStructured(path, contents),
              returnsNormally,
              reason: path,
            );
          }
        });
      });
    }
  });
}
