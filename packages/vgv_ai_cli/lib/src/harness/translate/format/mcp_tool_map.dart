/// Maps MCP tool names onto the command line that does the same job.
///
/// Pi has no MCP support by design, so a skill naming `mcp__dart__*` in its
/// `allowed-tools` names a tool it cannot invoke. The rewrite is applied to the
/// one shared copy under `~/.agents/skills` rather than per harness: the CLI
/// command is correct advice on every harness, so one copy stays one copy.
abstract final class McpToolMap {
  /// The MCP tools the VGV plugins reference, and their CLI equivalents.
  ///
  /// Keyed by the bare tool name. The plugins also write plugin-qualified
  /// forms such as `mcp__plugin_vgv-ai-flutter-plugin_dart__analyze_files`,
  /// which [rewrite] reduces to the bare name before looking it up.
  static const commands = <String, String>{
    'mcp__dart__analyze_files': 'dart analyze',
    'mcp__dart__dart_format': 'dart format',
    'mcp__dart__pub': 'dart pub',
    'mcp__dart__pub_dev_search': 'dart pub search',
    'mcp__very-good-cli__test': 'very_good test',
    'mcp__very-good-cli__create': 'very_good create',
    'mcp__very-good-cli__packages_get': 'very_good packages get',
    'mcp__very-good-cli__packages_check_licenses':
        'very_good packages check licenses',
  };

  /// Any `mcp__<server>__<tool>` reference, including the plugin-qualified
  /// forms the marketplace generates.
  ///
  /// The character class excludes `.` deliberately: tool names carry none, and
  /// allowing it makes the greedy match swallow the full stop that ends a
  /// sentence, so the lookup misses and a mapped tool reads as unmapped.
  static final _reference = RegExp('mcp__[A-Za-z0-9_-]+__[A-Za-z0-9_-]+');

  /// Strips a `plugin_<plugin>_` prefix from a server name.
  ///
  /// The same server is written both as `mcp__dart__x` and as
  /// `mcp__plugin_vgv-ai-flutter-plugin_dart__x` across the two plugins, and
  /// both mean the same tool.
  static String canonical(String reference) =>
      reference.replaceFirst(RegExp('^mcp__plugin_[A-Za-z0-9-]+_'), 'mcp__');

  /// Replaces every mapped MCP tool name in [contents] with its command.
  ///
  /// References with no mapping are left exactly as they are, so
  /// [unmapped] can still find them and report them.
  static String rewrite(String contents) =>
      contents.replaceAllMapped(_reference, (match) {
        final command = commands[canonical(match[0]!)];
        return command == null ? match[0]! : '`$command`';
      });

  /// The MCP tool names in [contents] that have no CLI equivalent.
  ///
  /// Sorted so a report reads the same way twice.
  static List<String> unmapped(String contents) =>
      _reference
          .allMatches(contents)
          .map((match) => match[0]!)
          .where((tool) => !commands.containsKey(canonical(tool)))
          .toSet()
          .toList()
        ..sort();
}
