import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template failing_auditor}
/// A [ManifestAuditor] that fails to reverse every entry it is given.
/// {@endtemplate}
class const FailingAuditor() extends ManifestAuditor {
  /// {@macro failing_auditor}
  this;

  @override
  Reversal reverse(
    InstallManifest manifest,
    FileSystem fileSystem, {
    Set<Harness?>? owners,
    Set<String>? paths,
    bool force = false,
    bool dryRun = false,
  }) => Reversal(
    entries: [
      for (final entry in manifest.entries)
        if ((owners?.contains(entry.owner) ?? true) &&
            (paths?.contains(entry.path) ?? true))
          ReversedEntry.failed(entry, error: 'Permission denied'),
    ],
    manifest: manifest,
  );
}
