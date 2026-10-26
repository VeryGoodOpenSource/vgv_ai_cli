import 'package:vgv_ai_cli/src/commands/doctor/model/finding.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/fix_command.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template report_section}
/// What `doctor` found about one thing, such as a harness, under [title].
/// {@endtemplate}
class const ReportSection({
  /// What the section is about, such as `Codex` or `Shared`.
  required final String title,

  /// The harnesses whose `install` fixes what was found, which for the
  /// shared skills are every configured harness that reads them.
  required final Set<Harness> installs,

  /// What was found, in the order it was found.
  required final List<Finding> findings,

  /// The plugins the fix installs, empty for every pinned one, or null when
  /// the harnesses were installed from different ones and no one `install`
  /// fixes them all.
  final Set<String>? plugins = const {},
}) {
  /// Whether anything was found that is wrong.
  bool get hasProblems => findings.any((finding) => finding.isProblem);

  /// Whether anything was found that is worth knowing, though not wrong.
  bool get hasNotices => findings.any((finding) => finding.isNotice);

  /// Whether `install` fixes something here that [fix] cannot say in one
  /// command, because the harnesses were installed from different plugins.
  bool get needsItsOwnFix =>
      fix == null && findings.any((finding) => finding.needsInstall);

  /// The one `install` command that fixes every finding `install` can fix,
  /// or null when there are none, or when no one command fixes them.
  FixCommand? get fix {
    if (plugins case final plugins?
        when findings.any((finding) => finding.needsInstall)) {
      return FixCommand(
        harnesses: installs,
        force: findings.any((finding) => finding.needsForce),
        plugins: plugins,
      );
    }
    return null;
  }
}
