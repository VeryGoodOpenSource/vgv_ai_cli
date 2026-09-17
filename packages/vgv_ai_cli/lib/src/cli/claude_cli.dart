part of 'cli.dart';

/// Claude Code CLI.
///
/// Claude Code installs the VGV plugins natively from the marketplace, so this
/// wrapper drives that install rather than translating any files.
class ClaudeCli {
  /// The executable name.
  static const executable = 'claude';

  /// Whether `claude` is on the path.
  static Future<bool> installed({required Logger logger}) {
    return _Cmd.exists(executable, ['--version'], logger: logger);
  }

  /// The installed version, or `null` when it cannot be determined.
  static Future<String?> version({required Logger logger}) async {
    final result = await _Cmd.run(
      executable,
      ['--version'],
      logger: logger,
      throwOnError: false,
    );
    if (result.exitCode != ExitCode.success.code) return null;
    return _parseVersion(result.stdout.toString());
  }

  /// Registers [repo] as a known marketplace.
  static Future<bool> marketplaceAdd(
    String repo, {
    required Logger logger,
  }) async {
    final result = await _Cmd.run(
      executable,
      ['plugin', 'marketplace', 'add', repo],
      logger: logger,
      throwOnError: false,
    );
    return result.exitCode == ExitCode.success.code;
  }

  /// Installs [plugin] from an already registered marketplace.
  static Future<bool> pluginInstall(
    String plugin, {
    required Logger logger,
  }) async {
    final result = await _Cmd.run(
      executable,
      ['plugin', 'install', plugin],
      logger: logger,
      throwOnError: false,
    );
    return result.exitCode == ExitCode.success.code;
  }

  /// The plugins Claude Code currently reports as installed.
  ///
  /// Used to verify an install actually took effect rather than trusting the
  /// exit code of `plugin install`.
  static Future<List<String>> installedPlugins({required Logger logger}) async {
    final result = await _Cmd.run(
      executable,
      ['plugin', 'list'],
      logger: logger,
      throwOnError: false,
    );
    if (result.exitCode != ExitCode.success.code) return [];
    return LineSplitter.split(result.stdout.toString())
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.split(RegExp(r'\s+')).first)
        .toList();
  }
}
