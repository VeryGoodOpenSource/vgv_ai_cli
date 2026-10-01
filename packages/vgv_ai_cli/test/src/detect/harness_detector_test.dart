import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/detect/detect.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

RunProcess _responds(ProcessResult result) =>
    (executable, arguments, {runInShell = false}) async => result;

ProcessResult _exits(int code, {String stdout = '', String stderr = ''}) =>
    ProcessResult(0, code, stdout, stderr);

/// Exit codes that must all read as a missing harness, not just `127`.
const missingExitCodes = [1, 2, 127];

Matcher _hasVersion(String version) =>
    isA<HarnessDetection>().having((d) => d.version, 'version', version);

void main() {
  group('HarnessDetector', () {
    test('uses the real Process.run when none is injected', () {
      expect(const HarnessDetector(), isNotNull);
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
        final detector = HarnessDetector(
          runProcess: _responds(_exits(0, stderr: 'opencode 1.4.2')),
        );

        await expectLater(
          detector.detect(Harness.opencode),
          completion(_hasVersion('1.4.2')),
        );
      });

      test('prefers stdout over stderr when both carry a version', () async {
        final detector = HarnessDetector(
          runProcess: _responds(
            _exits(0, stdout: '1.2.3', stderr: 'warning from 9.9.9'),
          ),
        );

        await expectLater(
          detector.detect(Harness.pi),
          completion(_hasVersion('1.2.3')),
        );
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

      for (final code in missingExitCodes) {
        test('is missing when the probe exits $code', () async {
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
