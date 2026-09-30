import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:toml/toml.dart';

/// Compares decoded documents, and the values inside them, structurally.
const deepEquality = DeepCollectionEquality();

/// Compares file contents byte by byte.
const bytesEquality = ListEquality<int>();

/// Whether [list] holds a value structurally equal to [item].
bool listContains(List<dynamic> list, Object? item) =>
    list.any((entry) => deepEquality.equals(entry, item));

const _encoder = JsonEncoder.withIndent('  ');

/// The SHA-256 of [bytes], as hex.
String hashBytes(List<int> bytes) => sha256.convert(bytes).toString();

/// The SHA-256 of [text] as UTF-8, as hex.
String hashText(String text) => hashBytes(utf8.encode(text));

/// [bytes] as text, or null when they are not UTF-8.
String? decodeUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// Decodes a JSON object, or null when it is malformed or not an object.
///
/// Gemini and OpenCode accept comments in their JSON settings, and a file
/// that has them lands here as malformed. Rewriting it would drop the
/// comments, so it is reported as unparseable for the user to edit by hand.
Map<String, dynamic>? decodeJson(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } on FormatException catch (_) {
    return null;
  }
}

/// Encodes a decoded map back to canonical JSON with a trailing newline.
String encodeJson(Map<String, dynamic> map) => '${_encoder.convert(map)}\n';

/// Decodes a TOML document, or null when it is malformed.
Map<String, dynamic>? decodeToml(String source) {
  try {
    return TomlDocument.parse(source).toMap();
  } on TomlException catch (_) {
    return null;
  }
}

/// Encodes a decoded map back to canonical TOML with a trailing newline.
String encodeToml(Map<String, dynamic> map) {
  final toml = TomlDocument.fromMap(map).toString().trim();
  return '$toml\n';
}

/// Writes [bytes] to [file], through a symlink and keeping its permissions.
///
/// The bytes go to a temporary file beside the target and are published by
/// rename, so an interrupted run cannot leave a half-written config behind.
/// The temporary file starts as a copy of the target, or of [source] when
/// there is no target yet, because a copy carries the file mode across.
void writeAtomically(
  File file,
  List<int> bytes, {
  required bool existed,
  File? source,
}) {
  final target = existed
      ? file.fileSystem.file(file.resolveSymbolicLinksSync())
      : file;
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

/// Deletes [file], and what it links to when it is a symlink.
///
/// [writeAtomically] writes through a symlink, so what VGV wrote is in the
/// file it links to. Deleting only the link would leave that behind, and
/// deleting only the target would leave the link dangling.
void deleteThrough(File file) {
  final target = file.fileSystem.file(file.resolveSymbolicLinksSync())
    ..deleteSync();
  if (target.path != file.path) file.fileSystem.link(file.path).deleteSync();
}

/// Why [error] happened, as one line.
String describeError(FileSystemException error) =>
    [error.message, ?error.osError?.message].join(': ');
