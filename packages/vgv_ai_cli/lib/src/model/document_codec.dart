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
  /// The keys whose list is an argv: a command and its arguments.
  static const Set<String> _argvKeys = {'command', 'args'};

  /// Whether a list at [key] is a collection VGV adds its entries to, as
  /// it does a server's hooks or OpenCode's `instructions`, rather than one
  /// value.
  ///
  /// An argv, the list at a `command` or `args` key, is one value: the order
  /// of its entries is what it means, so VGV's entries appended to the
  /// user's would make a command neither of them wrote.
  bool mergesEntries(String key) => !_argvKeys.contains(key);

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
