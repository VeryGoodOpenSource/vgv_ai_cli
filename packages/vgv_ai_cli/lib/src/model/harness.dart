import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// {@template harness}
/// A coding agent harness `vgv_ai` knows how to configure.
///
/// [Harness.values] is the single source of truth for harness selection and
/// reporting. Adding a harness takes four steps:
///
/// 1. Add an entry here.
/// 2. Write its `HarnessTranslator` and add it to `harnessTranslators`.
/// 3. Add a boolean var named after it to `bricks/agents/brick.yaml`, and a
///    folder of the same name under `__brick__` holding the files it reads.
/// 4. Regenerate the bundle with `tool/generate_agents_bundle.sh`.
/// {@endtemplate}
enum Harness {
  /// Claude Code, which installs the VGV plugins from the marketplace.
  claude(displayName: 'Claude Code', executable: 'claude', config: '.claude'),

  /// Gemini CLI.
  gemini(displayName: 'Gemini', executable: 'gemini', config: '.gemini'),

  /// Codex CLI.
  codex(displayName: 'Codex', executable: 'codex', config: '.codex'),

  /// OpenCode, which keeps its config under the XDG config root.
  opencode(
    displayName: 'OpenCode',
    executable: 'opencode',
    config: '.config/opencode',
  ),

  /// Pi.
  pi(displayName: 'Pi', executable: 'pi', config: '.pi/agent');

  /// {@macro harness}
  new({
    required this.displayName,
    required this.executable,
    required this._config,
  });

  /// A human readable name, for output.
  ///
  /// The enum's own [name] is the flag and reporting name, e.g. `opencode`,
  /// and the folder the `agents` brick renders this harness into.
  final String displayName;

  /// The binary looked for on the path.
  final String executable;

  /// [configDirectory] relative to home, with `/` separators.
  final String _config;

  /// The directory this harness reads its user-level config from.
  Directory configDirectory(Directory home) => home.fileSystem.directory(
    p.joinAll([home.path, ...p.posix.split(_config)]),
  );
}
