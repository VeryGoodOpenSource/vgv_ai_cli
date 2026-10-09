import 'package:plugin_source/plugin_source.dart';

/// {@template plugin_release}
/// The latest release of a plugin: its [tag], and the [version] its
/// `.claude-plugin/plugin.json` declares at that tag.
/// {@endtemplate}
class const PluginRelease({
  required final String tag,
  required final String version,
});

/// The pin [release] moves [pin] to, or null when [pin] is already there.
///
/// [PluginRef.version] is read from the release's `plugin.json`, never derived
/// from the tag, for the reasons on [PluginRef].
PluginRef? bumpFor(PluginRef pin, PluginRelease release) {
  if (pin.gitRef == release.tag && pin.version == release.version) return null;
  return PluginRef(
    name: pin.name,
    repo: pin.repo,
    version: release.version,
    gitRef: release.tag,
  );
}

/// [source] with the `version` and `gitRef` of the one `PluginRef(...)` block
/// whose `repo` is [pin]'s replaced by [pin]'s.
///
/// Throws a [FormatException] unless exactly one block names the repo and it
/// holds exactly one of each field, so a reformatted file fails loudly rather
/// than being half rewritten.
String rewritePin(String source, PluginRef pin) {
  final blocks = RegExp(r'PluginRef\([^)]*\)')
      .allMatches(source)
      .where((block) => block[0]!.contains("repo: '${pin.repo}',"))
      .toList();
  if (blocks.length != 1) {
    throw FormatException(
      'Expected one PluginRef block for ${pin.repo}, found ${blocks.length}.',
    );
  }

  final block = blocks.single;
  final rewritten = _replaceField(
    _replaceField(block[0]!, 'version', pin.version),
    'gitRef',
    pin.gitRef,
  );
  return source.replaceRange(block.start, block.end, rewritten);
}

String _replaceField(String block, String field, String value) {
  final pattern = RegExp("$field: '[^']*',");
  final count = pattern.allMatches(block).length;
  if (count != 1) {
    throw FormatException('Expected one $field in $block, found $count.');
  }
  return block.replaceFirst(pattern, "$field: '$value',");
}
