import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template scope}
/// Where an install goes: the user's home, or one project.
///
/// Answers every question that differs between the two, so the rest of the
/// install asks the scope rather than assuming home.
/// {@endtemplate}
sealed class const Scope(
  /// The directory everything is installed under, and the manifest kept in.
  final Directory root,
) {
  /// {@macro scope}
  this;

  /// The canonical directory the translated skills are written to.
  ///
  /// Gemini, Codex, OpenCode, Pi and Copilot all read `.agents/skills` with
  /// no configuration, so one copy serves five harnesses. Claude Code needs
  /// none: it installs the same plugins from the marketplace, and a second
  /// copy would drift from the first. Antigravity reads neither, so it keeps
  /// its own copy inside its plugin.
  ///
  /// The whole shared-copy strategy rests on that, so each harness's own
  /// documentation for where it reads skills from:
  ///
  /// - Gemini: https://geminicli.com/docs/cli/skills/
  /// - Codex: https://developers.openai.com/codex/skills
  /// - OpenCode: https://opencode.ai/docs/skills/
  /// - Pi: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md
  /// - Copilot: https://docs.github.com/en/copilot/concepts/agents/about-agent-skills
  /// - Antigravity: https://antigravity.google/docs/plugins/
  Directory get skillsRoot =>
      root.fileSystem.directory(p.join(root.path, '.agents', 'skills'));

  /// How a file written in this scope spells [path].
  String reference(String path);

  /// How a file written in this scope spells the root of [plugin], or null
  /// to spell the directory it was resolved to.
  String? pluginRoot(PluginRef plugin);
}

/// {@template home_scope}
/// An install into the user's home, which every project on the machine
/// shares.
/// {@endtemplate}
final class const HomeScope(
  /// The user's home directory.
  super.root,
) extends Scope {
  /// {@macro home_scope}
  this;

  /// [path] as it is: a home install only serves this machine, so an
  /// absolute path is the one that works from any directory.
  @override
  String reference(String path) => path;

  /// Null: the plugin is read where it was resolved.
  @override
  String? pluginRoot(PluginRef plugin) => null;
}

/// {@template project_scope}
/// An install into one project, committed so every contributor, CI and bots
/// share it.
/// {@endtemplate}
final class const ProjectScope(
  /// The project directory.
  super.root,
) extends Scope {
  /// {@macro project_scope}
  this;

  /// [path] relative to the project, with `/` separators, so the files read
  /// the same on every clone and every platform.
  @override
  String reference(String path) => p.posix.joinAll(
    root.fileSystem.path.split(
      root.fileSystem.path.relative(path, from: root.path),
    ),
  );

  /// `.vgv_ai/plugins/<name>@<gitRef>`, where the project keeps its copy of
  /// [plugin].
  @override
  String pluginRoot(PluginRef plugin) =>
      '.vgv_ai/plugins/${plugin.name}@${plugin.gitRef}';
}
