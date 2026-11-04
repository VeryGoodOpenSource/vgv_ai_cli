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
/// copied, one folder per plugin.
///
/// Beside [skillsRoot] rather than in it, since a harness would read a
/// folder there with no `SKILL.md` as a broken skill.
Directory pluginFilesRoot(Directory skillsRoot) =>
    skillsRoot.parent.childDirectory('vgv-plugins');

/// [text] with [PluginPath.placeholder] spelled out as the plugin files
/// beside [skillsRoot].
String expandPluginFiles(String text, {required Directory skillsRoot}) =>
    text.replaceAll(PluginPath.placeholder, pluginFilesRoot(skillsRoot).path);
