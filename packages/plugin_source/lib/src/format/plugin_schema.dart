import 'dart:convert';

import 'package:ack/ack.dart';
import 'package:plugin_source/src/format/plugin_parse_exception.dart';

/// Validates plugin file content against an `ack` schema.
///
/// The one decoding boundary for plugin files: every mismatch becomes a
/// [PluginParseException] that names the file and the deepest failing field,
/// as a JSON pointer such as `#/hooks/PreToolUse/0/matcher`.
extension PluginSchema<T extends Object> on AckSchema<Object, T> {
  /// Validates [value], an already-decoded document such as a YAML map.
  ///
  /// [path] names the file in any [PluginParseException]. The schema must
  /// not be nullable.
  T decode(Object? value, {required String path}) => switch (safeParse(value)) {
    Ok(:final value) => value!,
    Fail(:final error) => throw PluginParseException(path, _describe(error)),
  };

  /// Decodes [source] as JSON, then validates it like [decode].
  ///
  /// `jsonDecode` throws `FormatException`, which the command runner would
  /// render as a CLI usage error, so it is converted here.
  T decodeJson(String source, {required String path}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw PluginParseException(path, error.message);
    }
    return decode(decoded, path: path);
  }

  /// The first leaf beneath [error]'s nesting, as `<pointer>: <message>`.
  ///
  /// A nested error's own message only says that something beneath it failed.
  static String _describe(SchemaError error) => switch (error) {
    SchemaNestedError(errors: [final first, ...]) => _describe(first),
    _ => '${error.path}: ${error.message}',
  };
}
