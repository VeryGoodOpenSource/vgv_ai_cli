part of 'cli.dart';

/// Gemini CLI.
class GeminiCli {
  /// The executable name.
  static const executable = 'gemini';

  /// Whether `gemini` is on the path.
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
}
