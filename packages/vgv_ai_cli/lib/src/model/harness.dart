import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// {@template harness}
/// A coding agent harness `vgv_ai` knows how to configure.
///
/// [Harness.values] is the single source of truth for harness selection and
/// reporting. Adding a harness takes four steps:
///
/// 1. Add an entry here, with the oldest version that reads everything the
///    `user_config` brick renders for it as its `minimumVersion`, and a row in
///    the harness table of the README.
/// 2. Write its `HarnessTranslator` and add it to `harnessTranslators`.
///    Override `hooks()` when its config can run a shell command.
/// 3. Add a boolean var named after it to `bricks/user_config/brick.yaml`,
///    and a folder of the same name under `__brick__` holding the files it
///    reads.
/// 4. Regenerate the bundle with `tool/generate_bundles.sh`.
/// {@endtemplate}
enum Harness({
  /// A human readable name, for output.
  ///
  /// The enum's own [name] is the flag and reporting name, such as `opencode`,
  /// and the folder the `user_config` brick renders this harness into.
  required final String displayName,

  /// The binary looked for on the path.
  required final String executable,

  /// The oldest `x.y.z` this release supports: the first version that reads
  /// everything the `user_config` brick renders for this harness. An older one
  /// ignores some of those files, so `install` and `doctor` report it.
  required final String minimumVersion,

  /// [configDirectory] relative to home, with `/` separators.
  required final String _config,
}) {
  /// Claude Code, which installs the VGV plugins from the marketplace.
  ///
  /// 2.0.12 added plugins and marketplaces.
  claude(
    displayName: 'Claude Code',
    executable: 'claude',
    minimumVersion: '2.0.12',
    config: '.claude',
  ),

  /// Gemini CLI.
  ///
  /// 0.35.0 turned subagents on by default, after 0.28.0 began reading
  /// `~/.agents/skills`.
  gemini(
    displayName: 'Gemini',
    executable: 'gemini',
    minimumVersion: '0.35.0',
    config: '.gemini',
  ),

  /// Codex CLI.
  ///
  /// 0.124.0 turned hooks on by default, after 0.115.0 added TOML agents.
  codex(
    displayName: 'Codex',
    executable: 'codex',
    minimumVersion: '0.124.0',
    config: '.codex',
  ),

  /// OpenCode, which keeps its config under the XDG config root.
  ///
  /// 1.1.50 began reading `~/.agents/skills`.
  opencode(
    displayName: 'OpenCode',
    executable: 'opencode',
    minimumVersion: '1.1.50',
    config: '.config/opencode',
  ),

  /// Pi.
  ///
  /// 0.54.0 began reading `~/.agents/skills`. Writing its MCP servers will
  /// raise this to 0.99.0, the first to read `~/.pi/agent/mcp.json`.
  pi(
    displayName: 'Pi',
    executable: 'pi',
    minimumVersion: '0.54.0',
    config: '.pi/agent',
  ),

  /// GitHub Copilot CLI.
  ///
  /// 1.0.11 began reading `~/.agents/skills`.
  copilot(
    displayName: 'Copilot',
    executable: 'copilot',
    minimumVersion: '1.0.11',
    config: '.copilot',
  ),

  /// Antigravity CLI, which keeps the config it shares with the Antigravity
  /// IDE beside Gemini's.
  ///
  /// 1.2.0 fixed MCP servers in global plugins failing to start, the last of
  /// the plugin pieces to work.
  antigravity(
    displayName: 'Antigravity',
    executable: 'agy',
    minimumVersion: '1.2.0',
    config: '.gemini/config',
  );

  /// The directory this harness reads its user-level config from.
  Directory configDirectory(Directory home) => home.fileSystem.directory(
    p.joinAll([home.path, ...p.posix.split(_config)]),
  );
}
