import 'dart:convert';

import 'package:collection/collection.dart';

/// Compares decoded documents, and the values inside them, structurally.
const deepEquality = DeepCollectionEquality();

/// Compares file contents byte by byte.
const bytesEquality = ListEquality<int>();

/// Whether [list] holds a value structurally equal to [item].
bool listContains(List<dynamic> list, Object? item) =>
    list.any((entry) => deepEquality.equals(entry, item));

/// [bytes] as text, or null when they are not UTF-8.
String? decodeUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
