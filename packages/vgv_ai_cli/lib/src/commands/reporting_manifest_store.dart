import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template reporting_manifest_store}
/// Loads and saves the manifest in a [ManifestStore] for a command that
/// changes files, and tells the user why when either step fails.
/// {@endtemplate}
class const ReportingManifestStore(
  final ManifestStore _store,
  final Logger _logger, {

  /// What the command did when the manifest cannot be loaded, such as
  /// `Installed nothing`.
  required final String _nothingDone,

  /// What the command did to the files it records, such as `written`.
  required final String _done,
}) {
  /// The manifest in the store, or null, having said why, when it cannot be
  /// read or was written by a newer version.
  InstallManifest? load() {
    try {
      final manifest = _store.load();
      if (manifest == null) {
        _logger.err(
          '$_nothingDone, because ${ManifestStore.unreadable}: '
          '${_store.file.path}',
        );
      }
      return manifest;
    } on FileSystemException catch (error) {
      _logger.err(
        '$_nothingDone, because ${_store.file.path} could not be read: '
        '${error.description}',
      );
      return null;
    }
  }

  /// Saves [to] in the store unless it is [from], and returns whether it
  /// could.
  ///
  /// A manifest that could not be saved still holds its old entries, so the
  /// files this run changed count as the user's until a later run records
  /// them.
  bool save({required InstallManifest from, required InstallManifest to}) {
    if (to == from) return true;

    try {
      _store.save(to);
      return true;
    } on FileSystemException catch (error) {
      _logger.err(
        'Could not record what was $_done in ${_store.file.path}: '
        '${error.description}',
      );
      return false;
    }
  }
}
