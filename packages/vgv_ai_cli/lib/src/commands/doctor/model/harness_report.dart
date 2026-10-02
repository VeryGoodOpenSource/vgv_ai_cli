import 'package:vgv_ai_cli/src/commands/doctor/model/finding.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/fix_command.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template harness_report}
/// What `doctor` found for one [owner].
/// {@endtemplate}
class const HarnessReport({
  /// The harness reported on, or null for the shared skills.
  required final Harness? owner,

  /// The harnesses whose `install` fixes what was found, which for the
  /// shared skills are every configured harness that reads them.
  required final Set<Harness> installs,

  /// What was found, in the order it was found.
  required final List<Finding> findings,
}) {
  /// How [owner] is named in the report.
  String get title => owner?.displayName ?? 'Shared';

  /// Whether anything was found that is wrong.
  bool get hasProblems => findings.isNotEmpty;

  /// The `install` command that fixes [finding].
  FixCommand fixFor(Finding finding) =>
      FixCommand(harnesses: installs, force: finding.needsForce);
}
