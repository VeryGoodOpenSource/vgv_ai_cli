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
  /// [path] names the file in any [PluginParseException]. A nullable schema
  /// that accepts a null [value] throws too, since a document cannot be
  /// nothing.
  T decode(Object? value, {required String path}) => switch (safeParse(value)) {
    Ok(:final value?) => value,
    Ok() => throw PluginParseException(path, '#: Expected a value, got null'),
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
  /// A value that fits none of an `anyOf`'s shapes names them all. One that
  /// has the type of a shape but fails inside it is described by that shape.
  static String _describe(SchemaError error) => switch (error) {
    SchemaNestedError(schema: AnyOfSchema(), :final errors)
        when errors.isNotEmpty && errors.every((e) => e is TypeMismatchError) =>
      _expectedOneOf(error.path, errors.cast<TypeMismatchError>()),
    SchemaNestedError(schema: AnyOfSchema(), :final errors)
        when errors.any((e) => e is! TypeMismatchError) =>
      _describe(errors.firstWhere((e) => e is! TypeMismatchError)),
    SchemaNestedError(errors: [final first, ...]) => _describe(first),
    _ => '${error.path}: ${error.message}',
  };

  /// A value at [path] that fits none of an `anyOf`'s [mismatches].
  static String _expectedOneOf(
    String path,
    List<TypeMismatchError> mismatches,
  ) =>
      '$path: Expected ${mismatches.map((e) => e.expectedType).join(' or ')}, '
      'got ${mismatches.first.actualType}';
}

/// [parent], a JSON pointer, extended by [token].
///
/// The token is escaped as RFC 6901 requires, `~` as `~0` and `/` as `~1`, so
/// a key holding either still names one segment.
String jsonPointer(String parent, Object token) =>
    '$parent/${'$token'.replaceAll('~', '~0').replaceAll('/', '~1')}';
