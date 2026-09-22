/// The file formats plugins are written in, decoded into one tolerant view.
///
/// Nothing here knows about any harness or any asset type: parsers combine
/// these decoders with their own knowledge of where each key lives.
library;

export 'config_map.dart';
export 'frontmatter.dart';
export 'plugin_parse_exception.dart';
