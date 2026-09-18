import 'dart:io';

/// {@template git_not_found}
/// Thrown when the `git` executable cannot be found on the `PATH`.
/// {@endtemplate}
class GitNotFound implements Exception {
  /// {@macro git_not_found}
  const new();

  @override
  String toString() =>
      'git is not installed or not on your PATH. Install git and try again.';
}

/// {@template unreachable_remote}
/// Thrown when a git [remote] cannot be reached.
/// {@endtemplate}
class UnreachableRemote implements Exception {
  /// {@macro unreachable_remote}
  const new(this.remote);

  /// The remote that could not be reached.
  final Uri remote;

  @override
  String toString() =>
      '$remote is unreachable. Check the URL and your access rights.';
}

/// {@template git_clone_failure}
/// Thrown when a `git clone` fails.
/// {@endtemplate}
class GitCloneFailure implements Exception {
  /// {@macro git_clone_failure}
  const new(this.remote, this.message);

  /// The remote that failed to clone.
  final Uri remote;

  /// The underlying git error output.
  final String message;

  @override
  String toString() => 'Failed to clone $remote: $message';
}

/// {@template git}
/// A thin, mockable wrapper over the `git` executable.
///
/// Modeled on very_good_cli's `Git`, but instance based so it can be injected
/// and mocked in tests rather than reached through static methods.
/// {@endtemplate}
class Git {
  /// {@macro git}
  const new();

  /// Whether [remote] is reachable.
  ///
  /// Throws [UnreachableRemote] when it is not and [GitNotFound] when `git` is
  /// unavailable.
  Future<void> reachable(Uri remote) async {
    final result = await _run(['ls-remote', '$remote', '--exit-code']);
    if (result.exitCode != 0) throw UnreachableRemote(remote);
  }

  /// Shallow-clones [remote] into [destination] and returns the checked-out
  /// commit SHA.
  ///
  /// When [ref] is provided the matching branch or tag is checked out.
  Future<String> clone({
    required Uri remote,
    required Directory destination,
    String? ref,
  }) async {
    final result = await _run([
      'clone',
      '--depth',
      '1',
      if (ref != null) ...['--branch', ref],
      '$remote',
      destination.path,
    ]);
    if (result.exitCode != 0) {
      throw GitCloneFailure(remote, '${result.stderr}'.trim());
    }

    final head = await _run(
      ['rev-parse', 'HEAD'],
      workingDirectory: destination.path,
    );
    return '${head.stdout}'.trim();
  }

  Future<ProcessResult> _run(
    List<String> args, {
    String? workingDirectory,
  }) async {
    try {
      return await Process.run('git', args, workingDirectory: workingDirectory);
    } on ProcessException {
      throw const GitNotFound();
    }
  }
}
