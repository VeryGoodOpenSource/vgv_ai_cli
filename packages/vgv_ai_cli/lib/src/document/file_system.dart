import 'package:file/file.dart';

/// Writing and deleting the files VGV shares with the user, through the
/// symlinks a dotfiles repo may keep them behind.
extension SharedFile on File {
  /// Writes [bytes] here, through a symlink and keeping the permissions.
  ///
  /// The bytes go to a temporary file beside the target and are published by
  /// rename, so an interrupted run cannot leave a half-written config
  /// behind. The temporary file starts as a copy of the target, or of
  /// [source] when there is no target yet, because a copy carries the file
  /// mode across.
  void writeAtomically(List<int> bytes, {required bool existed, File? source}) {
    final target = existed ? fileSystem.file(resolveSymbolicLinksSync()) : this;
    target.parent.createSync(recursive: true);
    final temp = target.fileSystem.file('${target.path}.vgv-tmp');

    try {
      (existed ? target : source)?.copySync(temp.path);
      temp
        ..writeAsBytesSync(bytes, flush: true)
        ..renameSync(target.path);
    } on FileSystemException {
      if (temp.existsSync()) temp.deleteSync();
      rethrow;
    }
  }

  /// Deletes this file, and what it links to when it is a symlink.
  ///
  /// [writeAtomically] writes through a symlink, so what VGV wrote is in the
  /// file it links to. Deleting only the link would leave that behind, and
  /// deleting only the target would leave the link dangling. A symlinked
  /// directory above this file is not the file's own link, so it is left.
  void deleteThrough() {
    if (fileSystem.isLinkSync(path)) {
      fileSystem.file(resolveSymbolicLinksSync()).deleteSync();
    }
    deleteHere();
  }

  /// Deletes this path alone: the link when it is one, and never what it
  /// links to.
  void deleteHere() =>
      (fileSystem.isLinkSync(path) ? fileSystem.link(path) : this).deleteSync();
}

/// Cleaning up the directories VGV's files leave empty once they are gone.
extension EmptyDirectory on Directory {
  /// Deletes this directory and each ancestor below [boundary] that is
  /// empty, stopping at the first that is not.
  ///
  /// [boundary] itself is never deleted, and nothing is when this directory
  /// is not inside it, or is reached through a symlink below it, since what
  /// a link leads to is not VGV's to clean up.
  void deleteEmptyUpTo(Directory boundary) {
    final context = fileSystem.path;
    final chain = [
      for (
        var path = this.path;
        context.isWithin(boundary.path, path);
        path = context.dirname(path)
      )
        path,
    ];
    if (chain.any(fileSystem.isLinkSync)) return;

    for (final directory in chain.map(fileSystem.directory)) {
      if (!directory.existsSync()) continue;
      if (directory.listSync().isNotEmpty) return;
      directory.deleteSync();
    }
  }
}

/// Reporting a file error to the user.
extension DescribedFileSystemException on FileSystemException {
  /// Why this happened, as one line.
  String get description => [message, ?osError?.message].join(': ');
}
