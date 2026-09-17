import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/harnesses.dart';
import 'package:vgv_ai_cli/src/harness/skills_writer.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

final _fixture = Directory('test/fixtures/plugin');

const _staged = <String, String>{
  'vgv_block.md': '<!-- vgv:begin -->\nblock\n<!-- vgv:end -->',
  'claude_settings.fragment.json': '{"enabledPlugins":{}}',
  'gemini_settings.fragment.json': '{"context":{"fileName":"AGENTS.md"}}',
  'codex_config.fragment.toml': '[mcp_servers.dart]\ncommand = "dart"',
  'opencode.fragment.json': '{"mcp":{}}',
  'pi_settings.fragment.json': '{"skills":["~/.agents/skills"]}',
};

void main() {
  late PluginAssets assets;
  late Directory home;

  setUp(() {
    assets = PluginAssetsReader().read(_fixture);
    home = Directory.systemTemp.createTempSync('vgv_harness_');
  });

  tearDown(() => home.deleteSync(recursive: true));

  List<PlannedChange> planFor(Harness harness) =>
      harness.plan(assets: assets, home: home, staged: _staged);

  String contentsOf(List<PlannedChange> changes, String endsWith) {
    return changes.firstWhere((c) => c.file.path.endsWith(endsWith)).contents;
  }

  group('ClaudeHarness', () {
    test('writes only settings and the instruction block', () {
      final changes = planFor(const ClaudeHarness());

      expect(changes, hasLength(2));
      expect(
        changes.map((c) => p.basename(c.file.path)),
        containsAll(['settings.json', 'CLAUDE.md']),
      );
    });

    test('writes no skills, because the marketplace supplies them', () {
      final changes = planFor(const ClaudeHarness());

      expect(
        changes.where((c) => c.file.path.contains('skills')),
        isEmpty,
        reason: 'duplicating the plugin content would let the copies drift',
      );
    });

    test('merges settings rather than owning them', () {
      final change = planFor(const ClaudeHarness())
          .firstWhere((c) => c.file.path.endsWith('settings.json'));

      expect(change.mode, ChangeMode.mergeJson);
    });
  });

  group('GeminiHarness', () {
    test('writes commands as TOML with a required prompt', () {
      final changes = planFor(const GeminiHarness());
      final command = contentsOf(changes, 'commands/testing.toml');

      expect(command, contains('description = '));
      expect(command, contains('prompt = """'));
    });

    test('rewrites ARGUMENTS to the Gemini placeholder', () {
      final command = contentsOf(
        planFor(const GeminiHarness()),
        'commands/testing.toml',
      );

      expect(command, contains('{{args}}'));
      expect(command, isNot(contains(r'$ARGUMENTS')));
    });

    test('omits a skill that is not user invocable', () {
      final changes = planFor(const GeminiHarness());

      expect(
        changes.map((c) => c.file.path),
        isNot(contains(contains('elements-of-style.toml'))),
      );
    });

    test('writes agents flat, not nested by category', () {
      final changes = planFor(const GeminiHarness());
      final agents = changes.where((c) => c.file.path.contains('/agents/'));

      expect(agents, hasLength(2));
      for (final change in agents) {
        expect(p.dirname(change.file.path), endsWith('.gemini/agents'));
      }
    });
  });

  group('CodexHarness', () {
    test('writes agents as TOML with the three required keys', () {
      final agent = contentsOf(
        planFor(const CodexHarness()),
        'agents/flutter-reviewer.toml',
      );

      expect(agent, contains('name = '));
      expect(agent, contains('description = '));
      expect(agent, contains('developer_instructions = """'));
    });

    test('merges config.toml by table', () {
      final change = planFor(const CodexHarness())
          .firstWhere((c) => c.file.path.endsWith('config.toml'));

      expect(change.mode, ChangeMode.mergeToml);
    });

    test('writes prompts flat, since Codex reads no subdirectories', () {
      final prompts = planFor(const CodexHarness())
          .where((c) => c.file.path.contains('/prompts/'));

      for (final change in prompts) {
        expect(p.dirname(change.file.path), endsWith('.codex/prompts'));
      }
    });
  });

  group('OpenCodeHarness', () {
    test('marks agents as subagents', () {
      final agent = contentsOf(
        planFor(const OpenCodeHarness()),
        'agents/flutter-reviewer.md',
      );

      expect(agent, contains('mode: subagent'));
    });

    test('writes config under .config/opencode', () {
      final change = planFor(const OpenCodeHarness())
          .firstWhere((c) => c.file.path.endsWith('opencode.json'));

      expect(change.file.path, contains(p.join('.config', 'opencode')));
    });
  });

  group('PiHarness', () {
    test('writes agents as prompts, since Pi has no subagents', () {
      final changes = planFor(const PiHarness());

      expect(
        changes.map((c) => c.file.path),
        isNot(contains(contains('/agents/'))),
      );
      expect(
        changes.where(
          (c) => c.file.path.endsWith('prompts/flutter-reviewer.md'),
        ),
        hasLength(1),
      );
    });

    test('rewrites MCP tool references to CLI commands', () {
      const body =
          'Run mcp__very-good-cli__test then mcp__dart__analyze_files.';

      expect(
        PiHarness.rewriteMcpReferences(body),
        'Run `very_good test` then `dart analyze`.',
      );
    });

    test('reports an MCP tool it cannot map', () {
      const body = 'Uses mcp__dart__analyze_files and mcp__other__thing.';

      expect(PiHarness.unmappedMcpReferences(body), ['mcp__other__thing']);
    });

    test('leaves no mappable MCP reference behind in a real skill', () {
      final prompts = planFor(const PiHarness())
          .where((c) => c.file.path.contains('/prompts/'));

      for (final change in prompts) {
        expect(
          PiHarness.unmappedMcpReferences(change.contents),
          isEmpty,
          reason: '${change.file.path} names an MCP tool with no CLI mapping',
        );
      }
    });
  });

  group('SkillsWriter', () {
    test('writes every skill to the shared canonical location', () {
      final changes = const SkillsWriter().plan(assets: assets, home: home);
      final skillFiles = changes.where(
        (c) => p.basename(c.file.path) == 'SKILL.md',
      );

      expect(skillFiles, hasLength(assets.skills.length));
      for (final change in changes) {
        expect(change.file.path, contains(p.join('.agents', 'skills')));
        expect(change.harness, 'shared');
      }
    });

    test('carries bundled reference files alongside the skill', () {
      final changes = const SkillsWriter().plan(assets: assets, home: home);

      expect(
        changes.map((c) => c.file.path),
        containsAll([
          contains(p.join('testing', 'references', 'matchers.md')),
          contains(p.join('ui-package', 'reference.md')),
        ]),
      );
    });

    test('strips Claude-only frontmatter from the written skill', () {
      final changes = const SkillsWriter().plan(assets: assets, home: home);
      final testing = contentsOf(changes, p.join('testing', 'SKILL.md'));

      expect(testing, contains('name: testing'));
      expect(testing, isNot(contains('effort:')));
      expect(testing, isNot(contains('when_to_use:')));
    });
  });

  group('agent skill references', () {
    test('points at the canonical skills rather than inlining them', () {
      final agent = contentsOf(
        planFor(const OpenCodeHarness()),
        'agents/flutter-reviewer.md',
      );

      expect(agent, contains('## Required skills'));
      expect(agent, contains('- `testing`'));
      expect(agent, contains('- `animations`'));
      // Inlining would drag the whole skill body in and grow the file tenfold.
      expect(agent, isNot(contains('# Dart Testing')));
    });

    test('omits the section for an agent with no skills', () {
      final assetsNoSkills = PluginAssets(
        skills: assets.skills,
        agents: const [
          AgentAsset(
            name: 'plain',
            frontmatter: {'description': 'd'},
            body: 'body',
            skills: [],
          ),
        ],
        mcpServers: const {},
      );

      final changes = const OpenCodeHarness().plan(
        assets: assetsNoSkills,
        home: home,
        staged: _staged,
      );

      expect(
        contentsOf(changes, 'agents/plain.md'),
        isNot(contains('Required skills')),
      );
    });
  });
}
