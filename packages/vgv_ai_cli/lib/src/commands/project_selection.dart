import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template project_selection}
/// The `--project [<dir>]` option of a command that works on either the
/// user's home or one project.
///
/// The directory is the command's one positional argument, so it follows
/// the options, and defaults to the working directory.
/// {@endtemplate}
mixin ProjectSelection on Command<int> {
  /// The flag that works on a project instead of the user's home.
  static const String projectFlag = 'project';

  /// Adds the option, with [help] saying what the command does to the
  /// project.
  void addProjectOption(String help) {
    argParser.addFlag(projectFlag, help: help, negatable: false);
  }

  @override
  String get invocation => '${super.invocation} [--$projectFlag [<dir>]]';

  /// The directory `--project` names as it was given, `.` when it names
  /// none, or null without `--project`.
  String? get projectArgument => argResults![projectFlag] == true
      ? argResults!.rest.firstOrNull ?? '.'
      : null;

  /// Where the command works: the project `--project` names, resolved
  /// against [workingDirectory], or the user's [home]. [action] finishes
  /// the hint for a directory passed without `--project`, such as
  /// `install into a directory`.
  ///
  /// Throws a [UsageException] for a directory without `--project`, more
  /// than one directory, one that does not exist, or [home] itself.
  Scope selectScope(
    Directory home, {
    required Directory workingDirectory,
    required String action,
  }) {
    final rest = argResults!.rest;
    if (argResults![projectFlag] != true) {
      if (rest.isNotEmpty) {
        usageException(
          'Unexpected argument "${rest.first}". Pass --$projectFlag to '
          '$action.',
        );
      }
      return UserScope(home);
    }

    if (rest.length > 1) {
      usageException('--$projectFlag takes one directory, not ${rest.length}.');
    }
    final path = workingDirectory.fileSystem.path;
    final project = workingDirectory.fileSystem.directory(
      path.normalize(path.join(workingDirectory.path, rest.firstOrNull ?? '')),
    );
    if (!project.existsSync()) {
      usageException('${project.path} is not a directory.');
    }
    // A project rooted at home would share the user install's manifest and
    // skills, and a rerun would then prune the user install.
    if (home.existsSync() &&
        path.equals(
          project.resolveSymbolicLinksSync(),
          home.resolveSymbolicLinksSync(),
        )) {
      usageException(
        '${project.path} is your home directory. Pass --$projectFlag a '
        'repository instead.',
      );
    }
    return ProjectScope(project);
  }
}
