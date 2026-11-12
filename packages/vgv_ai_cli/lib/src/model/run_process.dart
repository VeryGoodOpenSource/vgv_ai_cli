import 'dart:io';

/// Signature of [Process.run], narrowed to what the CLI needs.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

/// Signature of [Process.start], narrowed to what the CLI needs.
typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});
