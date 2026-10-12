import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/model/model.dart';

/// The canonical directory the translated skills are written to.
///
/// Gemini, Codex, OpenCode and Pi all read `~/.agents/skills` with no
/// configuration, so one copy serves four harnesses. Claude Code needs none: it
/// installs the same plugins from the marketplace, and a second copy would
/// drift from the first.
///
/// The whole shared-copy strategy rests on that, so each harness's own
/// documentation for it:
///
/// - Gemini: https://geminicli.com/docs/cli/skills/
/// - Codex: https://developers.openai.com/codex/skills
/// - OpenCode: https://opencode.ai/docs/skills/
/// - Pi: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md
Directory agentsSkillsRoot(Directory home) =>
    home.fileSystem.directory(p.join(home.path, '.agents', 'skills'));

/// Where [harness] keeps its own copy of the plugins' hook scripts, which
/// its hooks file points at: the `hooks` folder of its config directory.
Directory harnessHooksRoot(Harness harness, {required Directory home}) {
  final config = harness.configDirectory(home);
  return config.fileSystem.directory(p.join(config.path, 'hooks'));
}
