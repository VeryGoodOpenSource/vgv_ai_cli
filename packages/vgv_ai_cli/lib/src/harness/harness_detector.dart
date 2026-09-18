import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';

/// Signature of [Process.run], narrowed to what detection needs.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

/// {@template harness_detection}
/// The result of probing for a single [Harness].
///
/// Constructed through [HarnessDetection.detected] or
/// [HarnessDetection.missing] so that an absent harness can never carry a
/// version.
/// {@endtemplate}
class HarnessDetection {
  /// The harness is on the path.
  ///
  /// [version] is `null` when the binary answered but printed nothing that
  /// looks like a version.
  const new detected({required this.harness, required this.version})
    : installed = true;

  /// The harness is not usable on this machine.
  const new missing({required this.harness})
    : installed = false,
      version = null;

  /// The harness that was probed.
  final Harness harness;

  /// Whether the binary is on the path.
  final bool installed;

  /// The reported version, or `null` when absent or unparseable.
  final String? version;
}

/// {@template harness_detector}
/// Probes the machine for installed harnesses.
///
/// Presence is the binary starting and exiting cleanly, not the shape of its
/// output, because the harnesses disagree on how they report a version.
/// {@endtemplate}
class HarnessDetector {
  /// {@macro harness_detector}
  new({RunProcess? runProcess, this._timeout = const Duration(seconds: 5)})
    : _runProcess = runProcess ?? Process.run;

  /// Matches the first `x.y.z` in a version banner.
  ///
  /// First match wins by choice: Codex prefixes its number with `codex-cli`,
  /// so the number is extracted rather than the line returned.
  static final _versionPattern = RegExp(r'\d+\.\d+\.\d+');

  final RunProcess _runProcess;
  final Duration _timeout;

  /// Probes every known harness, in parallel.
  ///
  /// Only `Exception`s are handled per harness. An `Error` is a bug and
  /// propagates rather than being reported as five absent harnesses.
  Future<List<HarnessDetection>> detectAll() =>
      Future.wait(Harness.values.map(detect));

  /// Probes a single [harness].
  ///
  /// Any non-zero exit reads as missing. Telling "not found" apart from
  /// "installed but broken" would mean keying on exit `127`, a POSIX shell
  /// convention `cmd.exe` does not share.
  Future<HarnessDetection> detect(Harness harness) async {
    try {
      final result = await _runProcess(
        harness.executable,
        ['--version'],
        // Claude, Gemini and OpenCode ship as npm shims, which on Windows are
        // `.cmd` files a shell must resolve.
        runInShell: true,
      ).timeout(_timeout);

      if (result.exitCode != ExitCode.success.code) {
        return HarnessDetection.missing(harness: harness);
      }

      return HarnessDetection.detected(
        harness: harness,
        version: _versionPattern.firstMatch('${result.stdout}')?.group(0),
      );
    } on Exception {
      return HarnessDetection.missing(harness: harness);
    }
  }
}
