import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/cli/cli.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// Configures Pi (earendil-works/pi).
///
/// Pi reads `~/.agents/skills` and `AGENTS.md`, so skills and instructions
/// need no work. It has no subagent primitive and, by design, no MCP support,
/// so agents are written as prompts and the MCP-backed tools named in
/// `allowed-tools` are rewritten to their CLI equivalents.
class PiHarness extends Harness {
  /// Creates a [PiHarness].
  const new();

  /// MCP tools mapped to the command that does the same job.
  ///
  /// Pi's stated philosophy is "no MCP, build CLI tools with READMEs", so this
  /// follows the grain of the tool rather than bridging MCP into it. `doctor`
  /// reports anything left unmapped instead of failing quietly.
  static const mcpToCli = <String, String>{
    'mcp__dart__analyze_files': 'dart analyze',
    'mcp__dart__dart_format': 'dart format',
    'mcp__very-good-cli__test': 'very_good test',
    'mcp__very-good-cli__create': 'very_good create',
    'mcp__very-good-cli__packages_get': 'very_good packages get',
    'mcp__very-good-cli__packages_check_licenses':
        'very_good packages check licenses',
  };

  @override
  String get name => 'pi';

  @override
  String get displayName => 'Pi';

  @override
  Future<bool> detected({required Logger logger}) =>
      PiCli.installed(logger: logger);

  @override
  Directory configRoot(Directory home) =>
      Directory(p.join(home.path, '.pi', 'agent'));

  @override
  List<PlannedChange> plan({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = configRoot(home);
    final changes = <PlannedChange>[];

    final settings = staged['pi_settings.fragment.json'];
    if (settings != null) {
      changes.add(
        merge(
          File(p.join(root.path, 'settings.json')),
          settings,
          ChangeMode.mergeJson,
        ),
      );
    }

    final block = staged['vgv_block.md'];
    if (block != null) {
      changes.add(
        merge(File(p.join(root.path, 'AGENTS.md')), block, ChangeMode.block),
      );
    }

    // No subagents, so each agent becomes a prompt the user invokes directly.
    for (final agent in assets.agents) {
      changes.add(
        own(
          File(p.join(root.path, 'prompts', '${agent.name}.md')),
          rewriteMcpReferences(
            Translate.agent(
              agent,
              const {},
              skillsRoot: agentsSkillsRoot(home),
            ),
          ),
        ),
      );
    }

    for (final skill in assets.skills.where((s) => s.userInvocable)) {
      changes.add(
        own(
          File(p.join(root.path, 'prompts', '${skill.name}.md')),
          rewriteMcpReferences(skill.body),
        ),
      );
    }

    return changes;
  }

  /// Replaces MCP tool names with the command that does the same job.
  static String rewriteMcpReferences(String contents) {
    var result = contents;
    for (final MapEntry(:key, :value) in mcpToCli.entries) {
      result = result.replaceAll(key, '`$value`');
    }
    return result;
  }

  /// MCP tool names in [contents] that have no CLI equivalent.
  static List<String> unmappedMcpReferences(String contents) {
    return RegExp('mcp__[a-zA-Z0-9_-]+__[a-zA-Z0-9_-]+')
        .allMatches(contents)
        .map((m) => m.group(0)!)
        .where((tool) => !mcpToCli.containsKey(tool))
        .toSet()
        .toList();
  }
}
