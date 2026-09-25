import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// The canonical directory the translated skills are written to.
///
/// Gemini, Codex, OpenCode and Pi all read `~/.agents/skills` with no
/// configuration, so one copy serves four harnesses. Claude Code needs none: it
/// installs the same plugins from the marketplace, and a second copy would
/// drift from the first.
Directory agentsSkillsRoot(Directory home) =>
    home.fileSystem.directory(p.join(home.path, '.agents', 'skills'));
