import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/src/format/format.dart';
import 'package:plugin_source/src/model/model.dart';
import 'package:plugin_source/src/parser/claude_plugin_parser.dart';
import 'package:test/test.dart';

const _fs = LocalFileSystem();

/// The fixture reproduces the inconsistencies the real plugins have, so a
/// reader that only handles the documented shape fails here.
Directory _fixture(String name) =>
    _fs.directory(p.join('test', 'fixtures', name));

/// Copies [from] into [to] without shelling out, so the test runs anywhere.
void _copyInto(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final target = p.join(to.path, p.basename(entity.path));
    if (entity is Directory) {
      _copyInto(entity, _fs.directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

void main() {
  late PluginAssets assets;

  setUp(() => assets = const ClaudePluginParser().parse(_fixture('plugin')));

  group('skills', () {
    test('reads every directory holding a SKILL.md, sorted by name', () {
      expect(assets.skills.map((s) => s.name), [
        'animations',
        'elements-of-style',
        'rebase',
        'testing',
        'ui-package',
        'unnamed-skill',
      ]);
    });

    test('skips skills/shared, which has no SKILL.md', () {
      // It is a pooled link target, not a skill.
      expect(assets.skills.map((s) => s.name), isNot(contains('shared')));
    });

    test('separates frontmatter from body', () {
      final testing = assets.skills.firstWhere((s) => s.name == 'testing');

      expect(testing.description, startsWith('Best practices'));
      expect(testing.body, startsWith('# Dart Testing'));
      expect(testing.body, isNot(contains('allowed-tools')));
    });

    test('keeps body content past a horizontal rule', () {
      final testing = assets.skills.firstWhere((s) => s.name == 'testing');

      expect(testing.body, contains('must not be mistaken'));
    });

    test('treats an absent user-invocable as invocable', () {
      final testing = assets.skills.firstWhere((s) => s.name == 'testing');

      expect(testing.userInvocable, isTrue);
    });

    test('honours an explicit user-invocable: false', () {
      final style = assets.skills.firstWhere(
        (s) => s.name == 'elements-of-style',
      );

      expect(style.userInvocable, isFalse);
    });

    test('reads comma-separated allowed-tools', () {
      final animations = assets.skills.firstWhere(
        (s) => s.name == 'animations',
      );

      expect(animations.allowedTools, ['Read', 'Glob', 'Grep']);
    });

    test('keeps parenthesized Bash scopes whole', () {
      final rebase = assets.skills.firstWhere((s) => s.name == 'rebase');

      expect(rebase.allowedTools, [
        'Bash(*/scripts/detect-base-branch.sh)',
        'Bash(git fetch *)',
        'Bash(git rebase *)',
        'Bash(git stash *)',
      ]);
    });

    test('folds when_to_use into the description', () {
      final testing = assets.skills.firstWhere((s) => s.name == 'testing');

      expect(
        testing.description,
        'Best practices for Dart unit tests. Second line folds away. - '
        'Use when writing or reviewing tests.',
      );
    });

    test('falls back to the directory name when frontmatter has none', () {
      // The fixture skill's SKILL.md declares no name, so the only way it can
      // be called 'unnamed-skill' is the directory-name fallback.
      expect(assets.skills.map((s) => s.name), contains('unnamed-skill'));
    });
  });

  group('portableFrontmatter', () {
    late SkillAsset testing;

    setUp(() => testing = assets.skills.firstWhere((s) => s.name == 'testing'));

    test('drops Claude-only keys', () {
      expect(testing.portableFrontmatter, isNot(contains('effort')));
      expect(testing.portableFrontmatter, isNot(contains('when_to_use')));
    });

    test('drops keys outside the Agent Skills spec, such as model', () {
      // `model: sonnet` is a Claude Code routing hint. A denylist would have
      // let it through into every other harness's skill file.
      expect(testing.portableFrontmatter, isNot(contains('model')));
    });

    test('keeps spec keys', () {
      expect(
        testing.portableFrontmatter,
        allOf(
          contains('name'),
          contains('description'),
          contains('allowed-tools'),
          contains('compatibility'),
        ),
      );
    });

    test('carries the folded description, so triggers survive', () {
      expect(
        testing.portableFrontmatter['description'],
        endsWith(' - Use when writing or reviewing tests.'),
      );
    });

    test('leaves the description of a skill without when_to_use alone', () {
      final animations = assets.skills.firstWhere(
        (s) => s.name == 'animations',
      );

      expect(
        animations.portableFrontmatter['description'],
        'Flutter animation practices.',
      );
    });

    test('drops disable-model-invocation', () {
      final unnamed = assets.skills.firstWhere(
        (s) => s.name == 'unnamed-skill',
      );

      expect(
        unnamed.portableFrontmatter,
        isNot(contains('disable-model-invocation')),
      );
    });

    test('drops user-invocable', () {
      final style = assets.skills.firstWhere(
        (s) => s.name == 'elements-of-style',
      );

      expect(style.portableFrontmatter, isNot(contains('user-invocable')));
    });
  });

  group('agents', () {
    test('flattens agents out of category directories, sorted', () {
      expect(assets.agents.map((a) => a.name), [
        'flutter-reviewer',
        'test-quality-review-agent',
        'unnamed-agent',
      ]);
    });

    test('falls back to the filename when frontmatter has no name', () {
      // The fixture agent declares no name, so being called 'unnamed-agent'
      // proves the filename fallback fired.
      expect(assets.agents.map((a) => a.name), contains('unnamed-agent'));
    });

    test('skips a non-markdown file under agents', () {
      expect(assets.agents.map((a) => a.name), isNot(contains('notes')));
    });

    test('parses an inline skills list', () {
      final agent = assets.agents.firstWhere(
        (a) => a.name == 'test-quality-review-agent',
      );

      expect(agent.skills, ['elements-of-style']);
    });

    test('parses a block sequence skills list', () {
      final agent = assets.agents.firstWhere(
        (a) => a.name == 'flutter-reviewer',
      );

      expect(agent.skills, ['testing', 'animations']);
    });

    test('flattens a literal block description onto one line', () {
      final agent = assets.agents.firstWhere(
        (a) => a.name == 'test-quality-review-agent',
      );

      expect(
        agent.description,
        'Reviews test coverage and quality across a change.',
      );
    });

    test('reads a folded description', () {
      final agent = assets.agents.firstWhere(
        (a) => a.name == 'flutter-reviewer',
      );

      expect(agent.description, 'Read-only Flutter reviewer.');
    });

    test('keeps the prompt body', () {
      final agent = assets.agents.firstWhere(
        (a) => a.name == 'flutter-reviewer',
      );

      expect(agent.body, 'Review the diff.\n');
    });
  });

  group('mcpServers', () {
    MCPServer? server(String name) =>
        assets.mcpServers.where((server) => server.name == name).singleOrNull;

    test('names each server by its key in .mcp.json', () {
      expect(assets.mcpServers.map((server) => server.name), [
        'dart',
        'context7',
        'authed',
      ]);
    });

    test('reads a local (stdio) server with args and env', () {
      final dart = server('dart');

      expect(dart, isA<LocalMCPServer>());
      final local = dart! as LocalMCPServer;
      expect(local.command, 'dart');
      expect(local.args, ['mcp-server']);
      expect(local.env, {'MCP_TOKEN': 'secret'});
    });

    test('reads a remote (url) server, defaulting headers to empty', () {
      final context7 = server('context7');

      expect(context7, isA<RemoteMCPServer>());
      final remote = context7! as RemoteMCPServer;
      expect(remote.url, 'https://mcp.context7.com/mcp');
      expect(remote.headers, isEmpty);
    });

    test('reads the headers of a remote server', () {
      final authed = server('authed')! as RemoteMCPServer;

      expect(authed.url, 'https://mcp.example.com/mcp');
      expect(authed.headers, {'Authorization': 'Bearer token'});
    });

    test('skips an entry that is not an object', () {
      expect(server('ignored'), isNull);
    });

    test('skips a declaration that is neither local nor remote', () {
      // No `url` and no `command`: not a valid MCP server, and the union has
      // no unknown fallback, so it is dropped.
      expect(server('broken'), isNull);
    });

    test('is empty when the plugin has no .mcp.json', () {
      final noMcp = const ClaudePluginParser().parse(_fixture('plugin_no_mcp'));

      expect(noMcp.mcpServers, isEmpty);
      expect(noMcp.skills, hasLength(1));
    });

    test('throws when .mcp.json is valid JSON but not an object', () {
      expect(
        () => const ClaudePluginParser().parse(_fixture('plugin_array_mcp')),
        throwsA(
          isA<PluginParseException>().having(
            (e) => e.message,
            'message',
            contains('JSON object'),
          ),
        ),
      );
    });

    test('throws a PluginParseException on invalid JSON', () {
      // jsonDecode throws FormatException, which the runner would render as a
      // CLI usage error.
      expect(
        () => const ClaudePluginParser().parse(_fixture('plugin_bad_mcp')),
        throwsA(
          isA<PluginParseException>().having(
            (e) => e.path,
            'path',
            contains('.mcp.json'),
          ),
        ),
      );
    });
  });

  group('hooks', () {
    HookAsset hookFor(String event) =>
        assets.hooks.firstWhere((h) => h.event == event);

    test('reads an event that matches against a tool', () {
      final post = hookFor('PostToolUse');

      expect(post.matcher, 'Edit|Write');
      expect(post.commands, hasLength(2));
      expect(post.commands.first.command, 'bash analyze.sh');
      expect(post.commands.first.timeout, 30);
    });

    test('reads an event with no matcher', () {
      // SessionStart does not match against a tool.
      expect(hookFor('SessionStart').matcher, isNull);
    });

    test('rewrites CLAUDE_PLUGIN_ROOT to the neutral placeholder', () {
      // Expanding the placeholder belongs to a translator, which knows where
      // the scripts landed for its harness. It must never have to know
      // Claude's spelling of it.
      expect(
        hookFor('SessionStart').commands.single.command,
        'bash ${HookCommand.rootPlaceholder}/hooks/scripts/warn.sh',
      );
    });

    test('defaults an absent type to command', () {
      expect(hookFor('Stop').commands.first.type, 'command');
    });

    test('keeps an explicit non-command type', () {
      expect(hookFor('Stop').commands.last.type, 'prompt');
    });

    test('drops a matcher that is not a string', () {
      expect(hookFor('Stop').matcher, isNull);
    });

    test('defaults an absent timeout to null', () {
      expect(hookFor('PostToolUse').commands.last.timeout, isNull);
    });

    test('carries the plugin root the placeholder stands for', () {
      // HookCommand.rootPlaceholder is spelled relative to the plugin root, not
      // the hooks directory, so this is what a translator substitutes.
      final root = hookFor('SessionStart').pluginRoot;

      expect(
        root
            .childDirectory('hooks')
            .childDirectory('scripts')
            .childFile('warn.sh')
            .existsSync(),
        isTrue,
      );
    });

    test('names the plugin from its manifest', () {
      // The cache files a plugin under its version, so the directory name
      // would say 0.0.5 where a translator needs vgv-wingspan.
      expect(hookFor('SessionStart').plugin, 'fixture-plugin');
    });

    test('names a plugin without a manifest after its directory', () {
      final fs = MemoryFileSystem.test();
      final root = fs.directory('/cache/bare')..createSync(recursive: true);
      root.childDirectory('hooks').childFile('hooks.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"hooks":{"Stop":[{"hooks":[{"command":"run.sh"}]}]}}',
        );

      expect(
        const ClaudePluginParser().parse(root).hooks.single.plugin,
        'bare',
      );
    });

    test('rejects a manifest name that is not safe as a directory', () {
      // The name becomes a folder under the user's home, so "../x" or "a/b"
      // would nest or escape it.
      final fs = MemoryFileSystem.test();
      final root = fs.directory('/cache/odd')..createSync(recursive: true);
      root.childDirectory('.claude-plugin').childFile('plugin.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"name": "../escape"}');
      root.childDirectory('hooks').childFile('hooks.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"hooks":{"Stop":[{"hooks":[{"command":"run.sh"}]}]}}',
        );

      expect(
        () => const ClaudePluginParser().parse(root),
        throwsA(
          isA<PluginParseException>()
              .having((e) => e.path, 'path', endsWith('plugin.json'))
              .having((e) => e.message, 'message', contains('../escape')),
        ),
      );
    });

    test('skips an event whose value is not a list', () {
      expect(assets.hooks.map((h) => h.event), isNot(contains('Malformed')));
    });

    test('skips registrations that contribute no runnable command', () {
      // An empty hooks array, an entry with no command string, and a
      // non-object registration all appear under EmptyCommands.
      expect(
        assets.hooks.map((h) => h.event),
        isNot(contains('EmptyCommands')),
      );
    });

    test('is empty when the plugin ships no hooks', () {
      expect(
        const ClaudePluginParser().parse(_fixture('plugin_no_mcp')).hooks,
        isEmpty,
      );
    });

    test('throws when hooks.json is valid JSON but not an object', () {
      expect(
        () => const ClaudePluginParser().parse(_fixture('plugin_array_hooks')),
        throwsA(
          isA<PluginParseException>().having(
            (e) => e.message,
            'message',
            contains('JSON object'),
          ),
        ),
      );
    });

    test('throws a PluginParseException on invalid JSON', () {
      expect(
        () => const ClaudePluginParser().parse(_fixture('plugin_bad_hooks')),
        throwsA(
          isA<PluginParseException>().having(
            (e) => e.path,
            'path',
            contains('hooks.json'),
          ),
        ),
      );
    });
  });

  group('names', () {
    late Directory root;

    setUp(() {
      root = MemoryFileSystem.test().directory('/plugin')
        ..createSync(recursive: true);
    });

    void write(String relative, String contents) {
      root.childFile(relative)
        ..createSync(recursive: true)
        ..writeAsStringSync(contents);
    }

    Matcher refuses(String name) => throwsA(
      isA<PluginParseException>().having(
        (e) => e.message,
        'message',
        contains('"$name"'),
      ),
    );

    test('refuses a skill name that climbs out of its directory', () {
      write('skills/evil/SKILL.md', '---\nname: ../../.ssh\n---\nbody\n');

      expect(
        () => const ClaudePluginParser().parse(root),
        refuses('../../.ssh'),
      );
    });

    test('refuses an agent name with a separator', () {
      write('agents/evil.md', '---\nname: nested/agent\n---\nbody\n');

      expect(
        () => const ClaudePluginParser().parse(root),
        refuses('nested/agent'),
      );
    });

    test('refuses an unsafe name that came from the file name', () {
      write('agents/Bad:Name.md', '---\ndescription: d\n---\nbody\n');

      expect(() => const ClaudePluginParser().parse(root), refuses('Bad:Name'));
    });

    test('accepts lowercase names with digits, dashes and underscores', () {
      write('skills/a/SKILL.md', '---\nname: dart_3-tips\n---\nbody\n');

      expect(
        const ClaudePluginParser().parse(root).skills.single.name,
        'dart_3-tips',
      );
    });
  });

  group('empty plugin', () {
    test('reads as empty rather than throwing', () {
      // The reader stays total. Whether an empty plugin is a problem is the
      // caller's judgement, because only it knows which plugin it asked for.
      final empty = const ClaudePluginParser().parse(_fixture('plugin_empty'));

      expect(empty.skills, isEmpty);
      expect(empty.agents, isEmpty);
      expect(empty.mcpServers, isEmpty);
    });
  });

  group('symlinked references', () {
    late Directory temp;

    setUpAll(() {
      // Built here rather than committed: a git checkout on Windows without
      // developer mode materializes a committed symlink as a text file holding
      // the target path, so the regression would silently pass there.
      temp = _fs.systemTempDirectory.createTempSync('vgv_symlink_');
      _copyInto(_fixture('plugin'), _fs.directory(p.join(temp.path, 'plugin')));

      final skill = p.join(temp.path, 'plugin', 'skills', 'testing');
      _fs
          .link(p.join(skill, 'references', 'pooled.md'))
          .createSync(p.join('..', '..', 'shared', 'references', 'pooled.md'));
    });

    tearDownAll(() => temp.deleteSync(recursive: true));

    test('stay resolvable through the directory the reader returns', () {
      // A tripwire for #19 rather than a test of reader logic: the reader does
      // not read references/, so this guards against it ever canonicalizing or
      // rewriting the directory it hands on. 21 reference files across 8
      // wingspan skills link into skills/shared, and a copy that does not
      // follow them produces dangling links in ~/.agents/skills.
      final linked = const ClaudePluginParser()
          .parse(_fs.directory(p.join(temp.path, 'plugin')))
          .skills
          .firstWhere((s) => s.name == 'testing');

      final pooled = _fs.file(
        p.join(linked.directory.path, 'references', 'pooled.md'),
      );

      expect(pooled.existsSync(), isTrue);
      expect(pooled.readAsStringSync(), contains('pooled reference content'));
    });
  });

  group('Claude-specific interpretation', () {
    Frontmatter fm(String body) =>
        Frontmatter.parse('---\n$body\n---\n', path: 'a.md');

    test('portableFrontmatterOf keeps exactly the spec keys', () {
      final portable = ClaudePluginParser.portableFrontmatterOf(
        fm(
          'name: a\n'
          'description: b\n'
          'license: MIT\n'
          'compatibility: anywhere\n'
          'metadata: {author: vgv}\n'
          'allowed-tools: Read\n'
          'effort: high\n'
          'when_to_use: later\n'
          'user-invocable: false\n'
          'disable-model-invocation: true\n'
          'model: sonnet\n'
          'argument-hint: <path>',
        ),
      );

      expect(portable.keys, unorderedEquals(SkillAsset.portableKeys));
    });

    test('portableFrontmatterOf folds the triggers into the description', () {
      final portable = ClaudePluginParser.portableFrontmatterOf(
        fm('description: What it does.\nwhen_to_use: Use when asked.'),
      );

      expect(portable['description'], 'What it does. - Use when asked.');
    });

    test('portableFrontmatterOf writes a description with no triggers as '
        'the plugin wrote it', () {
      // Byte-identical output for a plugin that folds its triggers into the
      // description already: a block scalar stays a block scalar.
      final portable = ClaudePluginParser.portableFrontmatterOf(
        fm('description: |\n  First line.\n  Second line.'),
      );

      expect(portable['description'], 'First line.\nSecond line.\n');
    });

    test('portableFrontmatterOf folds in place, keeping key order', () {
      final portable = ClaudePluginParser.portableFrontmatterOf(
        fm('name: a\ndescription: b\nwhen_to_use: c\nlicense: MIT'),
      );

      expect(portable.keys, ['name', 'description', 'license']);
    });

    group('descriptionOf', () {
      test('appends when_to_use, flattened, the way Claude Code joins it', () {
        expect(
          ClaudePluginParser.descriptionOf(
            fm(
              'description: What it does.\n'
              'when_to_use: >\n  Use when\n  asked.',
            ),
          ),
          'What it does. - Use when asked.',
        );
      });

      test('is the description alone when when_to_use is absent', () {
        expect(
          ClaudePluginParser.descriptionOf(fm('description: What it does.')),
          'What it does.',
        );
      });

      test('is the triggers alone when the description is absent', () {
        expect(
          ClaudePluginParser.descriptionOf(fm('when_to_use: Use when asked.')),
          'Use when asked.',
        );
      });
    });

    group('userInvocableOf', () {
      test('defaults to true when absent', () {
        expect(ClaudePluginParser.userInvocableOf(fm('name: a')), isTrue);
      });

      test('is false only when explicitly false', () {
        expect(
          ClaudePluginParser.userInvocableOf(fm('user-invocable: false')),
          isFalse,
        );
      });

      test('is true when explicitly true', () {
        expect(
          ClaudePluginParser.userInvocableOf(fm('user-invocable: true')),
          isTrue,
        );
      });

      test('treats a non-boolean value as absent', () {
        expect(
          ClaudePluginParser.userInvocableOf(fm('user-invocable: nope')),
          isTrue,
        );
      });
    });

    group('tokenizeTools', () {
      test('splits on spaces', () {
        expect(ClaudePluginParser.tokenizeTools('Read Glob'), ['Read', 'Glob']);
      });

      test('splits on commas', () {
        expect(ClaudePluginParser.tokenizeTools('Read,Glob'), ['Read', 'Glob']);
      });

      test('splits on a mix of both', () {
        expect(ClaudePluginParser.tokenizeTools('Read, Glob  Grep'), [
          'Read',
          'Glob',
          'Grep',
        ]);
      });

      test('keeps a parenthesized scope intact', () {
        expect(ClaudePluginParser.tokenizeTools('Bash(git push *) Read'), [
          'Bash(git push *)',
          'Read',
        ]);
      });

      test('keeps a scope containing commas and slashes', () {
        expect(
          ClaudePluginParser.tokenizeTools('Bash(rm -rf docs/reviews/) Read'),
          ['Bash(rm -rf docs/reviews/)', 'Read'],
        );
      });

      test('keeps a glob scope', () {
        expect(ClaudePluginParser.tokenizeTools('Bash(*/scripts/detect.sh)'), [
          'Bash(*/scripts/detect.sh)',
        ]);
      });

      test('keeps mcp tool names whole', () {
        expect(ClaudePluginParser.tokenizeTools('Read mcp__dart__analyze'), [
          'Read',
          'mcp__dart__analyze',
        ]);
      });

      test('is empty for null', () {
        expect(ClaudePluginParser.tokenizeTools(null), isEmpty);
      });
    });

    group('allowedToolsOf', () {
      test('reads allowed-tools', () {
        expect(ClaudePluginParser.allowedToolsOf(fm('allowed-tools: Read')), [
          'Read',
        ]);
      });

      test('falls back to tools', () {
        expect(ClaudePluginParser.allowedToolsOf(fm('tools: Read, Glob')), [
          'Read',
          'Glob',
        ]);
      });

      test('is empty when absent', () {
        expect(ClaudePluginParser.allowedToolsOf(fm('name: a')), isEmpty);
      });
    });
  });
}
