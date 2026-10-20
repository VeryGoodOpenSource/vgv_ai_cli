import 'dart:io';

import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template harness_detection}
/// The result of probing for a single [Harness].
/// {@endtemplate}
class HarnessDetection {
  /// The harness is on the path.
  ///
  /// [version] is `null` when the binary answered but printed nothing that
  /// looks like a version.
  const new detected({required this.version}) : installed = true;

  /// The harness is not usable on this machine.
  const new missing() : installed = false, version = null;

  /// Whether the binary is on the path.
  final bool installed;

  /// The reported version, or `null` when absent or unparseable.
  final String? version;
}

/// {@template harness_detector}
/// Probes the machine for installed harnesses.
/// {@endtemplate}
class const HarnessDetector({
  final RunProcess _runProcess = Process.run,
  final Duration _timeout = const Duration(seconds: 5),
}) {
  /// {@macro harness_detector}
  this;

  /// Matches the first `x.y.z` in a version banner.
  static final _versionPattern = RegExp(r'\d+\.\d+\.\d+');

  /// Harnesses banner to either stream, so both are searched.
  static String _banner(ProcessResult result) {
    return '${result.stdout}${result.stderr}';
  }

  /// Probes every known harness, in parallel.
  Future<Map<Harness, HarnessDetection>> detectAll() async {
    final detections = await Future.wait(Harness.values.map(detect));
    return Map.fromIterables(Harness.values, detections);
  }

  /// Probes a single [harness]. Any non-zero exit reads as missing.
  Future<HarnessDetection> detect(Harness harness) async {
    try {
      final result = await _runProcess(
        harness.executable,
        ['--version'],
        // npm shims are `.cmd` files on Windows and need a shell.
        runInShell: true,
      ).timeout(_timeout);

      if (result.exitCode != 0) {
        return const HarnessDetection.missing();
      }

      return HarnessDetection.detected(
        version: _versionPattern.firstMatch(_banner(result))?.group(0),
      );
    } on Exception {
      return const HarnessDetection.missing();
    }
  }
}
