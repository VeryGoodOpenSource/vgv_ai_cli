import 'package:vgv_ai_cli/src/commands/doctor/model/finding.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';

/// {@template content_plan}
/// What `install` would do to each file now, from a dry run, which is how
/// `doctor` tells what this version of the CLI writes from what is on disk.
/// {@endtemplate}
class ContentPlan {
  /// {@macro content_plan}
  ///
  /// [applied] is what a dry run of `install` would do.
  new(Iterable<AppliedChange> applied)
    : _byPath = {for (final change in applied) change.change.file.path: change},
      skipped = null;

  /// {@macro content_plan}
  ///
  /// There is no plan, because no configured harness was checked, so
  /// nothing is stale or orphaned.
  new none() : _byPath = null, skipped = null;

  /// {@macro content_plan}
  ///
  /// There is no plan, because the plugins could not be resolved or parsed,
  /// so nothing is known to be stale or orphaned, and [skipped] says why.
  new unchecked(Finding this.skipped) : _byPath = null;

  /// The outcomes that would write a file.
  static const Set<ChangeOutcome> _writes = {
    ChangeOutcome.created,
    ChangeOutcome.updated,
    ChangeOutcome.partial,
  };

  final Map<String, AppliedChange>? _byPath;

  /// Why content was not checked, or null when it was or did not need to
  /// be.
  final Finding? skipped;

  /// Whether this version no longer installs [entry].
  bool orphans(ManifestEntry entry) =>
      !(_byPath?.containsKey(entry.path) ?? true);

  /// Whether `install` would write to [path].
  bool writes(String path) => _writes.contains(_byPath?[path]?.outcome);

  /// The paths `install` would write for [owner] that [manifest] does not
  /// record yet.
  List<String> additions(Harness? owner, InstallManifest manifest) => [
    for (final AppliedChange(:change, :outcome) in _byPath?.values ?? [])
      if (change.harness == owner &&
          manifest[change.file.path] == null &&
          _writes.contains(outcome))
        change.file.path,
  ];
}
