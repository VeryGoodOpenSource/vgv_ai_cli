import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/plugin_source/frontmatter.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// The canonical location translated skills are written to.
///
/// Gemini, Codex, OpenCode and Pi all read `~/.agents/skills` natively, so one
/// copy serves four harnesses. Claude Code is the exception, and it does not
/// need a copy at all because it installs the plugins from the marketplace.
String agentsSkillsRoot(Directory home) =>
    p.join(home.path, '.agents', 'skills');

/// {@template staged_output}
/// The brick's rendered output, keyed by file name.
/// {@endtemplate}
typedef StagedOutput = Map<String, String>;

/// {@template harness}
/// One coding agent harness `vgv_ai` knows how to configure.
/// {@endtemplate}
abstract class Harness {
  /// {@macro harness}
  const new();

  /// The flag and reporting name, e.g. `gemini`.
  String get name;

  /// A human readable name for output.
  String get displayName;

  /// Whether the harness binary is on the path.
  Future<bool> detected({required Logger logger});

  /// Where this harness keeps its user-level config.
  Directory configRoot(Directory home);

  /// The changes needed to configure this harness.
  ///
  /// Returns changes rather than applying them so `--check` is a true dry run
  /// and the merge and backup rules stay in one place.
  List<PlannedChange> plan({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  });

  /// Builds a change owned by this harness.
  PlannedChange own(File file, String contents) => PlannedChange(
    file: file,
    contents: contents,
    mode: ChangeMode.own,
    harness: name,
  );

  /// Builds a merge or block change owned by this harness.
  PlannedChange merge(File file, String contents, ChangeMode mode) =>
      PlannedChange(file: file, contents: contents, mode: mode, harness: name);
}

/// Helpers shared by the translators.
abstract final class Translate {
  /// Renders a skill for a harness that reads the Agent Skills standard.
  ///
  /// Claude-only frontmatter is dropped, because packaging a skill with keys
  /// like `user-invocable` or `effort` breaks it elsewhere.
  static String skill(SkillAsset skill) {
    return '${Frontmatter.render(skill.portableFrontmatter)}\n${skill.body}';
  }

  /// Renders an agent as markdown with the given frontmatter.
  ///
  /// Claude Code resolves an agent's `skills:` list itself. Nowhere else does,
  /// so the list is restated as an instruction pointing at the canonical
  /// skills directory. Inlining the bodies instead would duplicate content
  /// that is already on disk and grow a single agent file more than tenfold.
  static String agent(
    AgentAsset agent,
    Map<String, String> frontmatter, {
    String? skillsRoot,
  }) {
    final buffer = StringBuffer(Frontmatter.render(frontmatter))
      ..writeln()
      ..writeln(agent.body.trimRight());

    if (agent.skills.isNotEmpty) {
      final location = skillsRoot == null ? '' : ' from `$skillsRoot`';
      buffer
        ..writeln()
        ..writeln('## Required skills')
        ..writeln()
        ..writeln(
          'Load these skills$location before you start. They are part of '
          'your instructions, not optional reading.',
        )
        ..writeln();
      for (final skill in agent.skills) {
        buffer.writeln('- `$skill`');
      }
    }
    return buffer.toString();
  }

  /// Escapes a string for a TOML basic string.
  static String tomlString(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  /// Renders a TOML multi-line string.
  static String tomlMultiline(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"""', r'\"\"\"');
    return '"""\n$escaped\n"""';
  }

  /// Rewrites `${CLAUDE_PLUGIN_ROOT}` to where the plugin actually landed.
  static String rewritePluginRoot(String contents, String root) {
    return contents
        .replaceAll(r'${CLAUDE_PLUGIN_ROOT}', root)
        .replaceAll(r'$CLAUDE_PLUGIN_ROOT', root);
  }
}
