import 'package:file/file.dart';
import 'package:path/path.dart' as p;

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

/// The folder, inside a harness's own config directory, holding the helper
/// scripts VGV writes for that harness's hooks.
///
/// Named here because two places must agree on it: the `agents` brick renders
/// into it, and a translator spells its absolute path into a hook command.
const harnessHooksFolder = 'hooks';

/// Where [harnessConfig] keeps the hook helper scripts VGV writes.
Directory harnessHooksRoot(Directory harnessConfig) => harnessConfig.fileSystem
    .directory(p.join(harnessConfig.path, harnessHooksFolder));
