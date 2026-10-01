import 'package:vgv_ai_cli/src/manifest/model/reversed_entry.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template reversal}
/// What reversing a manifest did, entry by entry, and the manifest that
/// records what VGV still owns afterwards.
/// {@endtemplate}
class const Reversal({
  /// Each entry that was reversed, and what reversing it did.
  required final List<ReversedEntry> entries,

  /// The manifest the entries were reversed from, without those that no
  /// longer hold anything of VGV's. On a dry run it records what would
  /// have been taken back.
  required final InstallManifest manifest,
});
