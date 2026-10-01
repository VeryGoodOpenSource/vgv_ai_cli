import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template manifest_store}
/// Where the [InstallManifest] for a home directory is kept, at
/// `~/.vgv_ai/manifest.json`, and the one place it is read from and written
/// to disk.
/// {@endtemplate}
class const ManifestStore(
  /// The home directory the manifest records, and is kept under.
  final Directory home,
) {
  /// Why a manifest this version cannot read is left as it is.
  static const unreadable =
      'the manifest was written by another version of vgv_ai, so it was '
      'left as it is';

  /// The manifest file.
  File get file =>
      home.fileSystem.file(p.join(home.path, '.vgv_ai', 'manifest.json'));

  /// The manifest in [file], an empty one when there is none, or null when
  /// another version of vgv_ai wrote it and it must be left alone.
  InstallManifest? load() {
    final file = this.file;
    return file.existsSync()
        ? InstallManifest.decode(file.readAsStringSync(), home: home.path)
        : InstallManifest();
  }

  /// Writes [manifest] to [file], or deletes [file] once nothing is left.
  void save(InstallManifest manifest) {
    final file = this.file;
    if (manifest.entries.isNotEmpty) {
      file.writeAtomically(
        utf8.encode(manifest.encode(home: home.path)),
        existed: file.existsSync(),
      );
    } else if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
