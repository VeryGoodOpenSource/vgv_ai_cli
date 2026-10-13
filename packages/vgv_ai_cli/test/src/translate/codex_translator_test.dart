import 'dart:convert';

import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '_assets.dart';

void main() {
  group('CodexTranslator', () {
    const translator = CodexTranslator();

    test('configures Codex', () {
      expect(translator.harness, Harness.codex);
    });

    test('declares that it runs the hooks, which the notes read', () {
      expect(translator.runsHooks, isTrue);
    });

    test('declares MCP servers as TOML tables, headers as http_headers', () {
      final toml = translator.settings(
        pluginAssets(
          mcpServers: [
            const RemoteMCPServer(
              name: 'docs',
              url: 'https://docs.example',
              headers: {'X-Region': 'us'},
            ),
            const LocalMCPServer(
              name: 'dart',
              command: 'dart',
              env: {'TOKEN': 'x'},
            ),
          ],
        ),
      );

      expect(TomlDocument.parse(toml).toMap(), {
        'mcp_servers': {
          'docs': {
            'url': 'https://docs.example',
            'http_headers': {'X-Region': 'us'},
          },
          'dart': {
            'command': 'dart',
            'env': {'TOKEN': 'x'},
          },
        },
      });
    });

    group('agents', () {
      test('carry the three keys the loader needs, as parseable TOML', () {
        final toml = translator
            .agent(agentAsset('reviewer'), instructions: 'You review code.\n')
            .toml!;

        expect(TomlDocument.parse(toml).toMap(), {
          'name': 'reviewer',
          'description': 'reviews code',
          'developer_instructions': 'You review code.\n',
        });
      });

      test(
        'survive instructions full of quotes, backticks and backslashes',
        () {
          const instructions = 'Say "no" to `rm -rf`\\ and \'"""\' too.\n';

          final toml = translator
              .agent(agentAsset('reviewer'), instructions: instructions)
              .toml!;

          expect(
            TomlDocument.parse(toml).toMap()['developer_instructions'],
            instructions,
          );
        },
      );
    });

    test('spells no command, since Codex reads no custom prompts', () {
      final fs = MemoryFileSystem.test();

      expect(translator.command(skillAsset(fs, 'plan')), const HarnessFields());
    });

    group('hooks', () {
      late MemoryFileSystem fs;

      setUp(() => fs = MemoryFileSystem.test());

      /// The registrations [hooks] translates to, under their event.
      Map<String, Object?> events(List<HookAsset> hooks) {
        final json = translator.hooks(
          pluginAssets(hooks: hooks),
          hooksRoot: fs.directory('/home/.codex/hooks'),
        )!;
        return (jsonDecode(json) as Map<String, Object?>)['hooks']!
            as Map<String, Object?>;
      }

      test("spell a file-edit matcher with Codex's own tool name", () {
        // Codex writes every edit through apply_patch, and Claude's two names
        // are kept because Codex documents all three as interchangeable.
        final registrations =
            events([hookAsset(fs, matcher: 'Edit|Write')])['PostToolUse']!
                as List<Object?>;

        expect(
          (registrations.single! as Map)['matcher'],
          'Edit|apply_patch|Write',
        );
      });

      test('watch the shell for a hook that watches reads', () {
        // Codex reads files through the shell, so wingspan's Read|Glob|Grep
        // hook fires on the first command instead of the first read.
        final registrations =
            events([
                  hookAsset(fs, event: 'PreToolUse', matcher: 'Read|Glob|Grep'),
                ])['PreToolUse']!
                as List<Object?>;

        expect((registrations.single! as Map)['matcher'], 'Bash');
      });

      test('carry over a matcher Codex spells the same way', () {
        for (final matcher in ['Bash', 'mcp__.*very-good-cli__.*']) {
          final registrations =
              events([
                    hookAsset(fs, event: 'PreToolUse', matcher: matcher),
                  ])['PreToolUse']!
                  as List<Object?>;

          expect((registrations.single! as Map)['matcher'], matcher);
        }
      });

      test('leave a hook that matches no tool with no matcher', () {
        final registrations =
            events([hookAsset(fs, event: 'SessionStart')])['SessionStart']!
                as List<Object?>;

        expect(registrations.single! as Map, isNot(contains('matcher')));
      });

      test("point a command at Codex's copy of the plugin", () {
        // The copy is where the preamble lives, so the command has to run
        // that script and not the plugin's own.
        final registrations =
            events([hookAsset(fs)])['PostToolUse']! as List<Object?>;
        final commands =
            (registrations.single! as Map)['hooks']! as List<Object?>;

        expect(
          (commands.single! as Map)['command'],
          'bash "/home/.codex/hooks/vgv-wingspan"/hooks/scripts/analyze.sh',
        );
      });

      test('point a file outside the hooks folder at the plugin itself', () {
        // Only the hooks folder is copied, so anything else a command names
        // is still read from where the plugin keeps it.
        final registrations =
            events([
                  hookAsset(
                    fs,
                    commands: const [
                      HookCommand(
                        type: 'command',
                        command: r'dart run ${PLUGIN_ROOT}/scripts/check.dart',
                      ),
                    ],
                  ),
                ])['PostToolUse']!
                as List<Object?>;
        final commands =
            (registrations.single! as Map)['hooks']! as List<Object?>;

        expect(
          (commands.single! as Map)['command'],
          'dart run "/plugins/vgv-wingspan"/scripts/check.dart',
        );
      });

      test('quote a copy root that holds a space', () {
        final json = translator.hooks(
          pluginAssets(hooks: [hookAsset(fs)]),
          hooksRoot: fs.directory('/home/Jane Doe/.codex/hooks'),
        )!;

        expect(
          json,
          contains(r'bash \"/home/Jane Doe/.codex/hooks/vgv-wingspan\"/hooks'),
        );
      });

      test('carry a handler that runs no shell command as it is', () {
        // Codex takes an mcp_tool handler and Claude a prompt one. Neither
        // names a script, so there is nothing to point elsewhere.
        final registrations =
            events([
                  hookAsset(
                    fs,
                    matcher: 'Edit',
                    commands: const [
                      HookCommand(type: 'prompt', command: 'say-hello'),
                    ],
                  ),
                ])['PostToolUse']!
                as List<Object?>;
        final commands =
            (registrations.single! as Map)['hooks']! as List<Object?>;

        expect((commands.single! as Map)['command'], 'say-hello');
      });

      test('carry the type and the timeout, and leave an absent one out', () {
        final registrations =
            events([
                  hookAsset(
                    fs,
                    commands: const [
                      HookCommand(type: 'command', command: 'a.sh', timeout: 5),
                      HookCommand(type: 'prompt', command: 'b.sh'),
                    ],
                  ),
                ])['PostToolUse']!
                as List<Object?>;
        final commands =
            (registrations.single! as Map)['hooks']! as List<Object?>;

        expect(commands.first! as Map, containsPair('type', 'command'));
        expect(commands.first! as Map, containsPair('timeout', 5));
        expect(commands.last! as Map, containsPair('type', 'prompt'));
        expect(commands.last! as Map, containsPair('command', 'b.sh'));
        expect(commands.last! as Map, isNot(contains('timeout')));
      });

      test('group every registration of one event together', () {
        final registrations =
            events([
                  hookAsset(fs, matcher: 'Edit'),
                  hookAsset(fs, matcher: 'Write'),
                ])['PostToolUse']!
                as List<Object?>;

        expect(registrations, hasLength(2));
      });

      test('are null when the plugins ship none', () {
        expect(
          translator.hooks(
            pluginAssets(),
            hooksRoot: fs.directory('/home/.codex/hooks'),
          ),
          isNull,
        );
      });
    });

    group('hookFiles', () {
      late MemoryFileSystem fs;

      setUp(() => fs = MemoryFileSystem.test());

      List<PlannedChange> files(List<HookAsset> hooks) => translator.hookFiles(
        pluginAssets(hooks: hooks),
        hooksRoot: fs.directory('/home/.codex/hooks'),
      );

      PlannedChange at(List<PlannedChange> changes, String suffix) =>
          changes.singleWhere((c) => c.file.path.endsWith(suffix));

      test("copy the plugin's hooks folder under its name, registry aside", () {
        // Every neighbour comes along, because a script sources and reads
        // files by its own location. The plugin's hooks.json is what hooks()
        // translated, so a copy of it would only mislead.
        final changes = files([hookAsset(fs)]);

        expect(changes.map((c) => c.file.path), [
          '/home/.codex/hooks/vgv-wingspan/hooks/scripts/analyze.sh',
          '/home/.codex/hooks/vgv-wingspan/hooks/scripts/common.sh',
        ]);
        expect(changes.map((c) => c.harness).toSet(), {Harness.codex});
      });

      test('copy each file from its source', () {
        // The reconciler copies the source's mode across, which a hook that
        // runs its script directly needs.
        final change = at(files([hookAsset(fs)]), 'common.sh');

        expect(
          change.source?.path,
          '/plugins/vgv-wingspan/hooks/scripts/common.sh',
        );
        expect(change.contents, 'hi() { echo hi; }\n');
      });

      test('keep the copies of two plugins apart', () {
        final other = fs.directory('/plugins/other')
          ..createSync(recursive: true);
        other.childDirectory('hooks').childDirectory('scripts')
          ..createSync(recursive: true)
          ..childFile('analyze.sh').writeAsStringSync('#!/bin/bash\necho o\n');
        final hook = HookAsset(
          event: 'PostToolUse',
          commands: const [
            HookCommand(
              type: 'command',
              command: r'bash ${PLUGIN_ROOT}/hooks/scripts/analyze.sh',
            ),
          ],
          plugin: 'other',
          pluginRoot: other,
        );

        final changes = files([hookAsset(fs), hook]);

        expect(changes.map((c) => c.file.path), [
          '/home/.codex/hooks/vgv-wingspan/hooks/scripts/analyze.sh',
          '/home/.codex/hooks/vgv-wingspan/hooks/scripts/common.sh',
          '/home/.codex/hooks/other/hooks/scripts/analyze.sh',
        ]);
      });

      test('put the preamble below the shebang of a script a hook runs', () {
        final script = at(files([hookAsset(fs)]), 'analyze.sh').contents;
        final preamble = codexPreamble
            .replaceAll('__ROOT__', '"/plugins/vgv-wingspan"')
            .replaceAll('__AGENT__', '""');

        expect(script, '#!/bin/bash\n${preamble}source common.sh\necho hi\n');
      });

      test('put the preamble in every script one command names', () {
        final hook = hookAsset(
          fs,
          commands: const [
            HookCommand(
              type: 'command',
              command:
                  r'bash ${PLUGIN_ROOT}/hooks/a.sh && '
                  r'bash "${PLUGIN_ROOT}/hooks/b.sh"',
            ),
          ],
        );
        for (final name in ['a.sh', 'b.sh']) {
          hook.pluginRoot
              .childDirectory('hooks')
              .childFile(name)
              .writeAsStringSync('#!/bin/bash\necho $name\n');
        }

        final changes = files([hook]);

        // The second is quoted in the command, and is still found.
        for (final name in ['a.sh', 'b.sh']) {
          expect(at(changes, name).contents, contains('vgv_ai install'));
        }
      });

      test('put the preamble at the top of a script bash runs unshebanged', () {
        final hook = hookAsset(
          fs,
          commands: const [
            HookCommand(
              type: 'command',
              command: r'bash ${PLUGIN_ROOT}/hooks/run.sh',
            ),
          ],
        );
        hook.pluginRoot
            .childDirectory('hooks')
            .childFile('run.sh')
            .writeAsStringSync('echo run\n');

        final script = at(files([hook]), 'run.sh').contents;

        expect(script, startsWith('# Added by vgv_ai install'));
        expect(script, endsWith('fi\necho run\n'));
      });

      test('quote a plugin root that holds a quote, a dollar or a space', () {
        final root = fs.directory(r'/plugins/it"s $5 ok')
          ..createSync(recursive: true);
        root.childDirectory('hooks').childFile('run.sh')
          ..createSync(recursive: true)
          ..writeAsStringSync('#!/bin/bash\necho run\n');
        final hook = HookAsset(
          event: 'Stop',
          commands: const [
            HookCommand(
              type: 'command',
              command: r'${PLUGIN_ROOT}/hooks/run.sh',
            ),
          ],
          plugin: 'quoted',
          pluginRoot: root,
        );

        expect(
          at(files([hook]), 'run.sh').contents,
          contains(r'export CLAUDE_PLUGIN_ROOT="/plugins/it\"s \$5 ok"'),
        );
      });

      test('scope a script to the agent whose hook names it', () {
        // flutter-reviewer declares its Bash guard for itself, so the copy
        // stands aside for any other agent.
        final script = at(
          files([hookAsset(fs, matcher: 'Bash', agent: 'flutter-reviewer')]),
          'analyze.sh',
        ).contents;

        expect(script, contains('vgv_agent="flutter-reviewer"\n'));
      });

      test('leave a script hooks of two scopes name unscoped, and say so', () {
        final hooks = [
          hookAsset(fs),
          hookAsset(fs, matcher: 'Bash', agent: 'flutter-reviewer'),
        ];

        expect(
          at(files(hooks), 'analyze.sh').contents,
          contains('vgv_agent=""\n'),
        );
        expect(
          translator.notes(pluginAssets(hooks: hooks)),
          contains(
            isA<TranslationNote>().having(
              (n) => n.reason,
              'reason',
              contains('more than one agent scope'),
            ),
          ),
        );
      });

      test('leave a script no shell command names as it is', () {
        // A prompt handler names no script, and common.sh is only sourced.
        final hook = hookAsset(
          fs,
          commands: const [HookCommand(type: 'prompt', command: 'say-hello')],
        );

        for (final change in files([hook])) {
          expect(change.contents, isNot(contains('vgv_ai install')));
        }
      });

      test('leave a script bash does not run as it is, and say so', () {
        // The preamble is bash. A script with another shebang that a hook
        // runs directly would die on the preamble's first bash-only line.
        final hook = hookAsset(
          fs,
          commands: const [
            HookCommand(
              type: 'command',
              command: r'${PLUGIN_ROOT}/hooks/run.sh',
            ),
          ],
        );
        hook.pluginRoot
            .childDirectory('hooks')
            .childFile('run.sh')
            .writeAsStringSync('#!/bin/sh\necho run\n');

        expect(at(files([hook]), 'run.sh').contents, '#!/bin/sh\necho run\n');
        expect(
          translator.notes(pluginAssets(hooks: [hook])),
          contains(
            isA<TranslationNote>()
                .having(
                  (n) => n.subject,
                  'subject',
                  'vgv-wingspan/hooks/run.sh',
                )
                .having((n) => n.reason, 'reason', contains('not a bash')),
          ),
        );
      });

      test('leave a script that is not UTF-8 text as it is, and say so', () {
        final hook = hookAsset(fs);
        hook.pluginRoot
            .childDirectory('hooks')
            .childDirectory('scripts')
            .childFile('analyze.sh')
            .writeAsBytesSync([0x23, 0x21, 0xff, 0xfe]);

        expect(at(files([hook]), 'analyze.sh').bytes, [0x23, 0x21, 0xff, 0xfe]);
        expect(
          translator.notes(pluginAssets(hooks: [hook])),
          contains(
            isA<TranslationNote>().having(
              (n) => n.reason,
              'reason',
              contains('not UTF-8'),
            ),
          ),
        );
      });

      test('copy what a symlink points at, under the link name', () {
        final hook = hookAsset(fs);
        fs.file('/plugins/shared/lint.sh')
          ..createSync(recursive: true)
          ..writeAsStringSync('lint\n');
        fs
            .link('/plugins/vgv-wingspan/hooks/scripts/lint.sh')
            .createSync('/plugins/shared/lint.sh');

        final change = at(files([hook]), 'scripts/lint.sh');

        expect(change.source?.path, '/plugins/shared/lint.sh');
        expect(change.contents, 'lint\n');
      });

      test('report a symlink that points nowhere, or at a directory', () {
        final hook = hookAsset(fs);
        final hooks = hook.pluginRoot.childDirectory('hooks');
        fs.link(hooks.childFile('gone.sh').path).createSync('/plugins/none');
        fs.link(hooks.childFile('dir.sh').path).createSync('/plugins/shared');
        fs.directory('/plugins/shared').createSync(recursive: true);

        const dangling = 'the symlink points at something that does not exist';
        const directory =
            'the symlink points at a directory, which is not copied';
        final notes = translator.notes(pluginAssets(hooks: [hook]));

        expect(files([hook]).map((c) => c.file.path), [
          '/home/.codex/hooks/vgv-wingspan/hooks/scripts/analyze.sh',
          '/home/.codex/hooks/vgv-wingspan/hooks/scripts/common.sh',
        ]);
        expect(
          notes.map((n) => '${n.subject}: ${n.reason}'),
          containsAll([
            'vgv-wingspan/hooks/gone.sh: $dangling',
            'vgv-wingspan/hooks/dir.sh: $directory',
          ]),
        );
      });

      test(
        'copy nothing for a plugin whose hooks folder is gone, and say so',
        () {
          // A cache cleared between resolution and translation. hooks() still
          // registers the scripts, so the note is what tells the user why they
          // will fail, which beats throwing out of install.
          final hook = hookAsset(fs);
          hook.pluginRoot.childDirectory('hooks').deleteSync(recursive: true);

          expect(files([hook]), isEmpty);
          expect(
            translator.notes(pluginAssets(hooks: [hook])),
            contains(
              isA<TranslationNote>()
                  .having((n) => n.subject, 'subject', 'vgv-wingspan')
                  .having((n) => n.reason, 'reason', contains('has gone away')),
            ),
          );
        },
      );
    });

    group('notes', () {
      late MemoryFileSystem fs;

      setUp(() => fs = MemoryFileSystem.test());

      test('ask for the trust that lets the rest run', () {
        final notes = translator.notes(pluginAssets(hooks: [hookAsset(fs)]));

        expect(notes.single.reason, contains('/hooks'));
      });

      test('say nothing about hooks when there are none', () {
        expect(translator.notes(pluginAssets()), isEmpty);
      });
    });
  });
}
