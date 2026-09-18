import 'dart:convert';

import 'package:hooks/pre_gen.dart';
import 'package:mason/mason.dart';
import 'package:test/test.dart';

class _TestLogger extends Logger {
  final errors = <String>[];

  @override
  void err(String? message, {LogStyle? style}) => errors.add(message ?? '');
}

class _TestContext implements HookContext {
  new(this._vars);

  Map<String, dynamic> _vars;

  @override
  final Logger logger = _TestLogger();

  @override
  Map<String, dynamic> get vars => _vars;

  @override
  set vars(Map<String, dynamic> value) => _vars = value;
}

const _marketplace = 'VeryGoodOpenSource/very_good_claude_marketplace';

const _baseVars = <String, dynamic>{
  'claude': true,
  'gemini': false,
  'codex': false,
  'opencode': false,
  'pi': false,
  'skills_root': '~/.agents/skills',
};

Map<String, dynamic> _decode(HookContext context, String key) {
  return jsonDecode(context.vars[key] as String) as Map<String, dynamic>;
}

void main() {
  group('pre_gen', () {
    test('throws and logs when no harness is selected', () async {
      final context = _TestContext({..._baseVars, 'claude': false});

      await expectLater(run(context), throwsA(isA<Exception>()));
      expect(
        (context.logger as _TestLogger).errors.single,
        contains('No harness selected'),
      );
    });

    test('throws and logs when a required var is missing', () async {
      final context = _TestContext(
        {..._baseVars}..removeWhere((key, _) => key == 'skills_root'),
      );

      await expectLater(run(context), throwsA(isA<Exception>()));
      expect(
        (context.logger as _TestLogger).errors.single,
        'Missing required var: skills_root.',
      );
    });

    test('defaults missing skills and agents to empty', () async {
      final context = _TestContext({..._baseVars});

      await run(context);

      expect(context.vars['skills'], isEmpty);
      expect(context.vars['agents'], isEmpty);
      expect(context.vars['has_skills'], isFalse);
      expect(context.vars['has_agents'], isFalse);
    });

    test('flags presence when skills and agents are supplied', () async {
      final context = _TestContext({
        ..._baseVars,
        'skills': [
          {'name': 'testing', 'description': 'write tests'},
        ],
        'agents': [
          {'name': 'flutter-reviewer', 'description': 'review dart'},
        ],
      });

      await run(context);

      expect(context.vars['has_skills'], isTrue);
      expect(context.vars['has_agents'], isTrue);
      expect(context.vars['skills'], [
        {'name': 'testing', 'description': 'write tests'},
      ]);
      expect(context.vars['agents'], [
        {'name': 'flutter-reviewer', 'description': 'review dart'},
      ]);
    });

    test('enables every VGV plugin against the marketplace', () async {
      final context = _TestContext({..._baseVars});

      await run(context);

      final settings = _decode(context, 'claude_settings_json');
      expect(settings['extraKnownMarketplaces'], {
        _marketplace: {'source': 'github', 'repo': _marketplace},
      });
      expect(settings['enabledPlugins'], {
        for (final plugin in vgvPlugins) '${plugin.name}@$_marketplace': true,
      });
    });

    test(
      'points Gemini at AGENTS.md and keeps command and args apart',
      () async {
        final context = _TestContext({
          ..._baseVars,
          'mcp_servers': {
            'dart': {
              'command': 'dart',
              'args': ['mcp-server'],
            },
          },
        });

        await run(context);

        final settings = _decode(context, 'gemini_settings_json');
        expect(settings['context'], {'fileName': 'AGENTS.md'});
        expect(settings['mcpServers'], {
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
        });
      },
    );

    test('merges command and args into one array for OpenCode', () async {
      final context = _TestContext({
        ..._baseVars,
        'mcp_servers': {
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
        },
      });

      await run(context);

      final config = _decode(context, 'opencode_config_json');
      expect(config['mcp'], {
        'dart': {
          'type': 'local',
          'command': ['dart', 'mcp-server'],
        },
      });
      expect(config['instructions'], ['AGENTS.md']);
    });

    test('types remote servers by url for OpenCode', () async {
      final context = _TestContext({
        ..._baseVars,
        'mcp_servers': {
          'context7': {'url': 'https://mcp.context7.com/mcp'},
        },
      });

      await run(context);

      expect(_decode(context, 'opencode_config_json')['mcp'], {
        'context7': {'type': 'remote', 'url': 'https://mcp.context7.com/mcp'},
      });
    });

    test('drops an empty env rather than emitting it', () async {
      final context = _TestContext({
        ..._baseVars,
        'mcp_servers': {
          'very-good-cli': {
            'command': 'very_good',
            'args': ['mcp'],
            'env': <String, dynamic>{},
          },
        },
      });

      await run(context);

      final mcp =
          _decode(context, 'opencode_config_json')['mcp']
              as Map<String, dynamic>;
      final server = mcp['very-good-cli'] as Map<String, dynamic>;
      expect(server.containsKey('environment'), isFalse);
    });

    test('forwards a populated env to OpenCode', () async {
      final context = _TestContext({
        ..._baseVars,
        'mcp_servers': {
          'very-good-cli': {
            'command': 'very_good',
            'args': ['mcp'],
            'env': {'VGV_TOKEN': 'abc123'},
          },
        },
      });

      await run(context);

      final mcp =
          _decode(context, 'opencode_config_json')['mcp']
              as Map<String, dynamic>;
      final server = mcp['very-good-cli'] as Map<String, dynamic>;
      expect(server['environment'], {'VGV_TOKEN': 'abc123'});
    });

    test('points Pi at the canonical skills root', () async {
      final context = _TestContext({..._baseVars});

      await run(context);

      expect(_decode(context, 'pi_settings_json'), {
        'skills': ['~/.agents/skills'],
      });
    });

    test('emits a Codex table per server', () async {
      final context = _TestContext({
        ..._baseVars,
        'mcp_servers': {
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
          'context7': {'url': 'https://mcp.context7.com/mcp'},
        },
      });

      await run(context);

      expect(
        context.vars['codex_config_toml'],
        '[mcp_servers.dart]\n'
        "command = 'dart'\n"
        "args = ['mcp-server']\n"
        '\n'
        '[mcp_servers.context7]\n'
        "url = 'https://mcp.context7.com/mcp'",
      );
    });

    test('emits a Codex env sub-table when a server carries one', () async {
      final context = _TestContext({
        ..._baseVars,
        'mcp_servers': {
          'very-good-cli': {
            'command': 'very_good',
            'args': ['mcp'],
            'env': {'VGV_TOKEN': 'abc123'},
          },
        },
      });

      await run(context);

      expect(
        context.vars['codex_config_toml'],
        '[mcp_servers.very-good-cli]\n'
        "command = 'very_good'\n"
        "args = ['mcp']\n"
        '\n'
        '[mcp_servers.very-good-cli.env]\n'
        "VGV_TOKEN = 'abc123'",
      );
    });

    test('emits a comment when Codex has no servers', () async {
      final context = _TestContext({..._baseVars});

      await run(context);

      expect(
        context.vars['codex_config_toml'],
        '# No MCP servers were resolved.',
      );
    });
  });
}
