import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';

part 'claude_cli.dart';
part 'codex_cli.dart';
part 'gemini_cli.dart';
part 'opencode_cli.dart';
part 'pi_cli.dart';

const R Function<R>(
  R Function(), {
  Function? onError,
  ZoneSpecification? zoneSpecification,
  Map<Object?, Object?>? zoneValues,
})
_asyncRunZoned = runZoned;

/// Type definition for [Process.run].
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

/// Facilitates overriding [Process.run] so the harness wrappers can be tested
/// without the real binaries installed.
@visibleForTesting
abstract class ProcessOverrides {
  static final _token = Object();

  /// The current [ProcessOverrides], or `null` when the [Zone] has none.
  static ProcessOverrides? get current {
    return Zone.current[_token] as ProcessOverrides?;
  }

  /// Runs [body] in a fresh [Zone] using the provided overrides.
  static R runZoned<R>(R Function() body, {RunProcess? runProcess}) {
    final overrides = _ProcessOverridesScope(runProcess);
    return _asyncRunZoned(body, zoneValues: {_token: overrides});
  }

  /// The method used to run a [Process].
  RunProcess get runProcess => Process.run;
}

class _ProcessOverridesScope extends ProcessOverrides {
  new(this._runProcess);

  final ProcessOverrides? _previous = ProcessOverrides.current;
  final RunProcess? _runProcess;

  @override
  RunProcess get runProcess {
    return _runProcess ?? _previous?.runProcess ?? super.runProcess;
  }
}

/// Abstraction for running commands via command-line.
class _Cmd {
  static Future<ProcessResult> run(
    String cmd,
    List<String> args, {
    required Logger logger,
    bool throwOnError = true,
    String? workingDirectory,
  }) async {
    logger.detail('Running: $cmd with $args');
    final runProcess = ProcessOverrides.current?.runProcess ?? Process.run;
    final result = await runProcess(
      cmd,
      args,
      runInShell: true,
      workingDirectory: workingDirectory,
    );
    logger
      ..detail('stdout:\n${result.stdout}')
      ..detail('stderr:\n${result.stderr}');

    if (throwOnError) _throwIfProcessFailed(result, cmd, args);
    return result;
  }

  /// Whether [cmd] responds to [args] at all.
  ///
  /// Harness binaries disagree on how to report their version, so presence is
  /// decided by the process starting and exiting cleanly, not by its output.
  static Future<bool> exists(
    String cmd,
    List<String> args, {
    required Logger logger,
  }) async {
    try {
      final result = await run(cmd, args, logger: logger, throwOnError: false);
      return result.exitCode == ExitCode.success.code;
    } on ProcessException catch (_) {
      return false;
    } on Exception catch (_) {
      return false;
    }
  }

  static void _throwIfProcessFailed(
    ProcessResult pr,
    String process,
    List<String> args,
  ) {
    if (pr.exitCode == ExitCode.success.code) return;
    final values = {
      'Standard out': pr.stdout.toString().trim(),
      'Standard error': pr.stderr.toString().trim(),
    }..removeWhere((k, v) => v.isEmpty);

    final message = values.isEmpty
        ? 'Unknown error'
        : values.entries.map((e) => '${e.key}\n${e.value}').join('\n');

    throw ProcessException(process, args, message, pr.exitCode);
  }
}

/// Extracts the first `x.y.z` found in [output].
///
/// Every harness prints its version differently, and some wrap it in a banner,
/// so the number is pulled out rather than the whole line returned.
String? _parseVersion(String output) {
  return RegExp(r'\d+\.\d+\.\d+').firstMatch(output)?.group(0);
}
