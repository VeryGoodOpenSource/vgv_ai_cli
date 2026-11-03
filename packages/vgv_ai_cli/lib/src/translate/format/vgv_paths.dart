import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// The canonical directory the translated skills are written to.
///
/// Gemini, Codex, OpenCode, Pi and Copilot all read `~/.agents/skills` with
/// no configuration, so one copy serves five harnesses. Claude Code needs
/// none: it installs the same plugins from the marketplace, and a second copy
/// would drift from the first. Antigravity reads neither, so it keeps its own
/// copy inside its plugin.
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
Directory agentsSkillsRoot(Directory home) =>
    home.fileSystem.directory(p.join(home.path, '.agents', 'skills'));

/// Where [harness] keeps the files its hooks file points at.
Directory harnessHooksRoot(Harness harness, {required Directory home}) {
  final config = harness.configDirectory(home);
  return config.fileSystem.directory(p.join(config.path, 'hooks'));
}

/// Where the plugin files that the skills under [skillsRoot] name are
/// copied: beside it, one folder per plugin.
///
/// A skill's own directory travels with it, but a file it names under its
/// plugin's root, such as the FFCA plugin's `references/ffca/`, lives outside
/// every skill. Kept out of [skillsRoot] itself, since a harness would read
/// a folder there with no `SKILL.md` as a broken skill.
Directory pluginFilesRoot(Directory skillsRoot) =>
    skillsRoot.parent.childDirectory('vgv-plugins');

/// [text] with [PluginPath.placeholder] spelled out as [filesRoot], where
/// the copy of every plugin's files is kept.
String expandPluginFiles(String text, {required Directory filesRoot}) =>
    text.replaceAll(PluginPath.placeholder, filesRoot.path);

/// What a plugin may be named, since its name becomes a folder under the
/// hooks root and under [pluginFilesRoot].
final _pluginNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// Whether [plugin], a plugin's name, is safe as a folder name.
bool isSafePluginName(String plugin) => _pluginNamePattern.hasMatch(plugin);
