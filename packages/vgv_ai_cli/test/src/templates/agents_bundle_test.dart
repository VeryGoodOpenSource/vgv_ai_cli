@Tags(['brick'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/templates/templates.dart';

/// Vars the CLI supplies at install time, standing in for resolved plugins.
const _marketplace = 'VeryGoodOpenSource/very_good_claude_marketplace';

Map<String, dynamic> _vars({
  bool claude = false,
  bool gemini = false,
  bool codex = false,
  bool opencode = false,
  bool pi = false,
  bool populated = true,
}) {
  return <String, dynamic>{
    'claude': claude,
    'gemini': gemini,
    'codex': codex,
    'opencode': opencode,
    'pi': pi,
    'skills_root': '~/.agents/skills',
    if (populated) ...{
      'skills': [
        {'name': 'testing', 'description': 'Writing or reviewing Dart tests.'},
        {'name': 'bloc', 'description': 'Bloc state management.'},
      ],
      'agents': [
        {'name': 'flutter-reviewer', 'description': 'Read-only Dart review.'},
      ],
      'mcp_servers': {
        'dart': {
          'command': 'dart',
          'args': ['mcp-server'],
        },
        'very-good-cli': {
          'command': 'very_good',
          'args': ['mcp'],
          'env': <String, dynamic>{},
        },
        'context7': {'url': 'https://mcp.context7.com/mcp'},
      },
    },
  };
}

/// Renders the bundled brick into a temp directory and returns it.
Future<Directory> _render(Map<String, dynamic> vars) async {
  final generator = await MasonGenerator.fromBundle(agentsBundle);
  final target = Directory.systemTemp.createTempSync('agents_');
  addTearDown(() => target.deleteSync(recursive: true));

  var resolved = vars;
  await generator.hooks.preGen(
    vars: resolved,
    onVarsChanged: (updated) => resolved = updated,
  );
  await generator.generate(
    DirectoryGeneratorTarget(target),
    vars: resolved,
    fileConflictResolution: FileConflictResolution.overwrite,
  );
  return target;
}

List<String> _paths(Directory dir) {
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => p.relative(f.path, from: dir.path))
      .toList()
    ..sort();
}

void main() {
  group('agentsBundle', () {
    test(
      'generates only the config files for the selected harnesses',
      () async {
        final dir = await _render(_vars(claude: true, opencode: true));

        expect(_paths(dir), [
          p.join('claude', 'settings.json'),
          p.join('opencode', 'AGENTS.md'),
          p.join('opencode', 'opencode.json'),
        ]);
      },
    );

    test(
      'generates every config file when all harnesses are selected',
      () async {
        final dir = await _render(
          _vars(
            claude: true,
            gemini: true,
            codex: true,
            opencode: true,
            pi: true,
          ),
        );

        expect(_paths(dir), [
          p.join('claude', 'settings.json'),
          p.join('codex', 'AGENTS.md'),
          p.join('codex', 'config.toml'),
          p.join('gemini', 'AGENTS.md'),
          p.join('gemini', 'settings.json'),
          p.join('opencode', 'AGENTS.md'),
          p.join('opencode', 'opencode.json'),
          p.join('pi', 'settings.json'),
        ]);
      },
    );

    test('fails when no harness is selected', () async {
      await expectLater(_render(_vars()), throwsA(isA<Exception>()));
    });

    // A typo in a template name would leave `{{ ... }}` unrendered. This is the
    // only thing standing between such a typo and silently truncated output.
    test('leaves no unrendered mustache behind', () async {
      final dir = await _render(
        _vars(
          claude: true,
          gemini: true,
          codex: true,
          opencode: true,
          pi: true,
        ),
      );

      for (final path in _paths(dir)) {
        final contents = File(p.join(dir.path, path)).readAsStringSync();
        expect(
          contents,
          isNot(anyOf(contains('{{'), contains('}}'))),
          reason: '$path still contains mustache syntax',
        );
      }
    });

    test('generates no empty or near-empty file', () async {
      final dir = await _render(
        _vars(
          claude: true,
          gemini: true,
          codex: true,
          opencode: true,
          pi: true,
        ),
      );

      for (final path in _paths(dir)) {
        final contents = File(p.join(dir.path, path)).readAsStringSync().trim();
        expect(contents, isNotEmpty, reason: '$path is empty');
        expect(
          contents.length,
          greaterThan(20),
          reason: '$path is suspiciously short: $contents',
        );
      }
    });

    test('does not html-escape paths', () async {
      final dir = await _render(_vars(claude: true, pi: true));

      for (final path in _paths(dir)) {
        expect(
          File(p.join(dir.path, path)).readAsStringSync(),
          isNot(contains('&#')),
          reason: '$path contains HTML-escaped output',
        );
      }
    });

    test('emits valid JSON for every json config file', () async {
      final dir = await _render(
        _vars(claude: true, gemini: true, opencode: true, pi: true),
      );

      for (final path in _paths(dir).where((p) => p.endsWith('.json'))) {
        final contents = File(p.join(dir.path, path)).readAsStringSync();
        expect(
          () => jsonDecode(contents),
          returnsNormally,
          reason: '$path is not valid JSON',
        );
      }
    });

    test('wires Claude to the marketplace rather than copying files', () async {
      final dir = await _render(_vars(claude: true));
      final settings = jsonDecode(
        File(p.join(dir.path, 'claude', 'settings.json')).readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(settings['extraKnownMarketplaces'], contains(_marketplace));
      expect(
        (settings['enabledPlugins'] as Map).keys,
        containsAll(<String>[
          'vgv-wingspan@$_marketplace',
          'vgv-ai-flutter-plugin@$_marketplace',
        ]),
      );
    });
  });
}
