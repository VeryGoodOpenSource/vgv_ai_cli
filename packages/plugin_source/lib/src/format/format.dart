/// The file formats plugins are written in, and the boundary that validates
/// them against a schema.
///
/// Nothing here knows about any harness or any asset type: parsers combine
/// these decoders with their own schemas for the keys they read.
library;

export 'frontmatter.dart';
export 'plugin_parse_exception.dart';
export 'plugin_schema.dart';
