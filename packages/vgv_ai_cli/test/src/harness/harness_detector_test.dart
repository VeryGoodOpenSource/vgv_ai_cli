import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/harness/harness_detector.dart';

/// A [RunProcess] that always answers with [result].
///
/// `RunProcess` is a function typedef, so there is nothing for mocktail to
/// implement. Tests pass plain closures instead.
///
/// Never call `expect` inside one of these: `TestFailure` implements
/// `Exception`, so [HarnessDetector.detect] would swallow it and the
/// assertion could never fail. Capture instead, and assert after the call.
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

    group('detect', () {
      const banners = {
        'claude': '2.1.270 (Claude Code)',
        'gemini': '0.52.0',
        'codex': 'codex-cli 0.153.4',
      };
      const versions = {
        'claude': '2.1.270',
        'gemini': '0.52.0',
        'codex': '0.153.4',
      };

      for (final harness in banners.keys) {
        test('reads ${versions[harness]} out of the $harness banner', () async {
          final detector = HarnessDetector(
            runProcess: _responds(_exits(0, stdout: banners[harness]!)),
          );

          final detection = await detector.detect(Harness.claude);

          expect(detection.installed, isTrue);
          expect(detection.version, versions[harness]);
        });
      }

      test('reads the version from stderr when stdout is empty', () async {
        // OpenCode and Pi were unavailable to check, so a harness that
        // banners to stderr must not read as installed with a blank version.
        final detector = HarnessDetector(
          runProcess: _responds(_exits(0, stderr: 'opencode 1.4.2')),
        );

        expect((await detector.detect(Harness.opencode)).version, '1.4.2');
      });

      test('prefers stdout over stderr when both carry a version', () async {
        final detector = HarnessDetector(
          runProcess: _responds(
            _exits(0, stdout: '1.2.3', stderr: 'warning from 9.9.9'),
          ),
        );

        expect((await detector.detect(Harness.pi)).version, '1.2.3');
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
        String? executable;
        List<String>? arguments;
        bool? usedShell;
        final detector = HarnessDetector(
          runProcess: (exe, args, {runInShell = false}) async {
            executable = exe;
            arguments = args;
            usedShell = runInShell;
            return _exits(0, stdout: '0.52.0');
          },
        );

        await detector.detect(Harness.gemini);

        expect(executable, 'gemini');
        expect(arguments, ['--version']);
        expect(
          usedShell,
          isTrue,
          reason: 'npm shims are .cmd files on Windows and need a shell',
        );
      });

      for (final code in [1, 2, 127]) {
        test('is missing when the probe exits $code', () async {
          // Pins "any non-zero", so special-casing 127 would fail here.
          final detector = HarnessDetector(
            runProcess: _responds(_exits(code, stdout: '1.2.3')),
          );

          final detection = await detector.detect(Harness.opencode);

          expect(detection.installed, isFalse);
          expect(detection.version, isNull);
        });
      }

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

      test(
        'lets an Error surface instead of reporting a missing harness',
        () async {
          // Conditions are caught, bugs are not.
          final detector = HarnessDetector(
            runProcess: (executable, arguments, {runInShell = false}) async =>
                throw ArgumentError('a bug, not a missing binary'),
          );

          await expectLater(
            detector.detect(Harness.claude),
            throwsA(isA<ArgumentError>()),
          );
        },
      );
    });

    group('detectAll', () {
      test('probes every harness exactly once', () async {
        final probed = <String>[];
        final detector = HarnessDetector(
          runProcess: (executable, arguments, {runInShell = false}) async {
            probed.add(executable);
            return _exits(0, stdout: '1.2.3');
          },
        );

        final detections = await detector.detectAll();

        // Unordered: the probes run in parallel, so arrival order is an
        // implementation detail. The keys themselves are ordered.
        expect(
          probed,
          unorderedEquals(Harness.values.map((harness) => harness.executable)),
        );
        expect(detections.keys, Harness.values);
      });

      test('reports a mix of installed and missing harnesses', () async {
        // The shape `install` (#20) actually consumes.
        const present = {'claude', 'gemini'};
        final detector = HarnessDetector(
          runProcess: (executable, arguments, {runInShell = false}) async =>
              present.contains(executable)
              ? _exits(0, stdout: '1.2.3')
              : _exits(127, stderr: 'command not found'),
        );

        final detections = await detector.detectAll();

        expect(detections[Harness.claude]!.installed, isTrue);
        expect(detections[Harness.claude]!.version, '1.2.3');
        expect(detections[Harness.pi]!.installed, isFalse);
        expect(detections[Harness.pi]!.version, isNull);
        expect(
          detections.values.where((detection) => detection.installed),
          hasLength(present.length),
        );
      });
    });
  });
}
