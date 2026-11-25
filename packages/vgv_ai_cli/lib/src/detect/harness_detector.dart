import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template harness_status}
/// What probing for a [Harness] found.
/// {@endtemplate}
enum HarnessStatus {
  /// On the path, at its [Harness.minimumVersion] or later.
  supported,

  /// On the path, but older than its [Harness.minimumVersion].
  outdated,

  /// On the path, but printed nothing that looks like a version, so whether
  /// it is supported is unknown.
  unversioned,

  /// Not usable on this machine.
  missing,
}

/// {@template harness_detection}
/// The result of probing for a single [Harness].
/// {@endtemplate}
class const HarnessDetection._({
  /// What the probe found.
  required final HarnessStatus status,

  /// The reported version, or `null` when absent or unparseable.
  final String? version,
}) {
  /// {@macro harness_detection}
  ///
  /// The harness is on the path at a supported [version].
  const new detected({required String version})
    : this._(status: HarnessStatus.supported, version: version);

  /// {@macro harness_detection}
  ///
  /// The harness is on the path at a [version] older than it supports.
  const new outdated({required String version})
    : this._(status: HarnessStatus.outdated, version: version);

  /// {@macro harness_detection}
  ///
  /// The harness is on the path, but answered with no version.
  const new unversioned() : this._(status: HarnessStatus.unversioned);

  /// {@macro harness_detection}
  ///
  /// The harness is not usable on this machine.
  const new missing() : this._(status: HarnessStatus.missing);

  /// Whether the binary is on the path.
  bool get installed => status != HarnessStatus.missing;
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

  /// What [result] printed to either stream, since harnesses differ in which
  /// one their version banner goes to.
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

      final version = _versionPattern.firstMatch(_banner(result))?.group(0);
      return version == null
          ? const HarnessDetection.unversioned()
          : _compare(harness, version);
    } on Exception {
      return const HarnessDetection.missing();
    }
  }

  /// [version] of [harness], as supported or outdated.
  static HarnessDetection _compare(Harness harness, String version) =>
      Version.parse(version) < Version.parse(harness.minimumVersion)
      ? HarnessDetection.outdated(version: version)
      : HarnessDetection.detected(version: version);
}
