import 'dart:convert';

import 'package:vgv_ai_cli/src/plugin_source/format/config_map.dart';
import 'package:vgv_ai_cli/src/plugin_source/format/plugin_parse_exception.dart';

/// Decodes [source] as a JSON object, wrapped in a [ConfigMap].
///
/// [path] names the file in any [PluginParseException]. `jsonDecode` throws
/// `FormatException`, which the command runner would render as a CLI usage
/// error, so it is converted here. A non-object value throws the same way.
ConfigMap parseJsonObject(String source, {required String path}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw PluginParseException(path, error.message);
  }

  if (decoded is! Map) {
    throw PluginParseException(path, 'expected a JSON object');
  }

  return ConfigMap.of(decoded);
}
