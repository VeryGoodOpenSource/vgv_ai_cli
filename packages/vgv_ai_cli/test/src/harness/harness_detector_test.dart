import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/harness/harness_detector.dart';

/// A [RunProcess] that always answers with [result].
///
/// `RunProcess` is a function typedef, so there is nothing for mocktail to
/// implement. Tests pass plain closures instead.
RunProcess _responds(ProcessResult result) =>
    (executable, arguments, {runInShell = false}) async => result;

ProcessResult _exits(int code, {String stdout = '', String stderr = ''}) =>
    ProcessResult(0, code, stdout, stderr);

void main() {
  group('HarnessDetector', () {
    test('uses the real Process.run when none is injected', () {
      // Coverage of the default argument only. Asserts no behaviour, because
      // doing so would spawn the developer's real harness binaries.
      expect(HarnessDetector(), isNotNull);
    });

    test('reports the version printed by each real harness', () async {
      const banners = {
        '2.1.270 (Claude Code)': '2.1.270',
        '0.52.0': '0.52.0',
        'codex-cli 0.153.4': '0.153.4',
      };

      for (final banner in banners.entries) {
        final detector = HarnessDetector(
          runProcess: _responds(_exits(0, stdout: banner.key)),
        );

        final detection = await detector.detect(Harness.claude);

        expect(detection.installed, isTrue, reason: banner.key);
        expect(detection.version, banner.value, reason: banner.key);
      }
    });

    test(
      'is installed without a version when the banner has no number',
      () async {
        final detector = HarnessDetector(
          runProcess: _responds(_exits(0, stdout: 'nightly build')),
        );

        final detection = await detector.detect(Harness.pi);

        expect(detection.installed, isTrue);
        expect(detection.version, isNull);
      },
    );

    test('asks for --version through a shell', () async {
      late final bool usedShell;
      late final List<String> arguments;
      final detector = HarnessDetector(
        runProcess: (executable, args, {runInShell = false}) async {
          usedShell = runInShell;
          arguments = args;
          expect(executable, Harness.gemini.executable);
          return _exits(0, stdout: '0.52.0');
        },
      );

      await detector.detect(Harness.gemini);

      expect(arguments, ['--version']);
      expect(
        usedShell,
        isTrue,
        reason: 'npm shims are .cmd files on Windows and need a shell',
      );
    });

    test('is missing when the binary is not on the path', () async {
      final detector = HarnessDetector(
        runProcess: _responds(_exits(127, stderr: 'command not found')),
      );

      final detection = await detector.detect(Harness.opencode);

      expect(detection.installed, isFalse);
      expect(detection.version, isNull);
    });

    test('is missing when the process cannot be started', () async {
      final detector = HarnessDetector(
        runProcess: (executable, arguments, {runInShell = false}) async =>
            throw ProcessException(executable, arguments),
      );

      expect((await detector.detect(Harness.pi)).installed, isFalse);
    });

    test('is missing when the probe outlives the timeout', () async {
      final detector = HarnessDetector(
        runProcess: (executable, arguments, {runInShell = false}) =>
            Completer<ProcessResult>().future,
        timeout: const Duration(milliseconds: 10),
      );

      expect((await detector.detect(Harness.claude)).installed, isFalse);
    });

    test('detectAll probes every harness exactly once', () async {
      final probed = <String>[];
      final detector = HarnessDetector(
        runProcess: (executable, arguments, {runInShell = false}) async {
          probed.add(executable);
          return _exits(0, stdout: '1.2.3');
        },
      );

      final detections = await detector.detectAll();

      expect(probed, Harness.values.map((harness) => harness.executable));
      expect(detections.map((detection) => detection.harness), Harness.values);
      expect(detections.every((detection) => detection.installed), isTrue);
    });
  });
}
