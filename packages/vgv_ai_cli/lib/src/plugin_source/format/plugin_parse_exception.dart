/// {@template plugin_parse_exception}
/// Thrown when a plugin file exists but cannot be understood.
///
/// Deliberately not a [FormatException]: the command runner renders those as
/// CLI usage errors, so a corrupt plugin file would wrongly tell the user
/// their command-line arguments were bad.
/// {@endtemplate}
class const PluginParseException(final String path, final String message)
    implements Exception {
  @override
  String toString() => 'Could not parse $path: $message';
}
