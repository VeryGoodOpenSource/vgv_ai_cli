import 'dart:convert';

import 'package:collection/collection.dart';

/// {@template document_codec}
/// Reads the bytes of the documents VGV shares with the user, and compares
/// them and what they decode to.
/// {@endtemplate}
class const DocumentCodec({
  /// Compares file contents byte by byte.
  final ListEquality<int> bytesEquality = const ListEquality<int>(),

  /// Compares decoded documents, and the values inside them, structurally.
  final DeepCollectionEquality deepEquality = const DeepCollectionEquality(),
}) {
  /// Whether [list] holds a value structurally equal to [item].
  bool listContains(List<dynamic> list, Object? item) {
    return list.any((entry) => deepEquality.equals(entry, item));
  }

  /// [bytes] as text, or null when they are not UTF-8.
  String? decodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }
}
