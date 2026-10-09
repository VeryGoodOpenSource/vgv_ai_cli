/// Bumps every pin in `vgvPlugins` that is behind its plugin's latest GitHub
/// release, rewriting `lib/src/plugin_ref.dart` in place.
///
/// Run by the `bot_bump_plugin_pins` workflow. Needs an authenticated `gh`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:plugin_source/plugin_source.dart';

/// Runs `gh` with the given arguments.
typedef RunGh = Future<ProcessResult> Function(List<String> args);

Future<void> main() async {
  final bumps = await bumpPins(
    File.fromUri(Platform.script.resolve('../lib/src/plugin_ref.dart')),
    runGh: (args) => Process.run('gh', args),
  );
  stdout.writeln(bumps.isEmpty ? 'Every pin is current.' : bumps.join('\n'));
}

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

/// {@template pin_bump}
/// A pin moved [from] one release [to] another.
/// {@endtemplate}
class const PinBump(final PluginRef from, final PluginRef to) {
  @override
  String toString() =>
      '${from.name}: ${from.version} (${from.gitRef}) -> '
      '${to.version} (${to.gitRef}) '
      'https://github.com/${to.repo}/releases/tag/${to.gitRef}';
}

/// Moves every pin in [pins] that is behind its latest release, rewriting
/// [file] only when at least one moved.
Future<List<PinBump>> bumpPins(
  File file, {
  required RunGh runGh,
  List<PluginRef> pins = vgvPlugins,
}) async {
  final bumps = <PinBump>[];
  for (final pin in pins) {
    final to = bumpFor(pin, await latestRelease(pin, runGh: runGh));
    if (to != null) bumps.add(PinBump(pin, to));
  }
  if (bumps.isNotEmpty) {
    file.writeAsStringSync(
      bumps.map((bump) => bump.to).fold(file.readAsStringSync(), rewritePin),
    );
  }
  return bumps;
}

/// The latest published release of [pin]'s repo.
///
/// `releases/latest` excludes drafts and pre-releases, and is keyed on
/// releases rather than tags, so stray tags never count.
Future<PluginRelease> latestRelease(
  PluginRef pin, {
  required RunGh runGh,
}) async {
  final tag = (await _gh(runGh, [
    'api',
    'repos/${pin.repo}/releases/latest',
    '--jq',
    '.tag_name',
  ])).trim();
  final manifest = await _gh(runGh, [
    'api',
    'repos/${pin.repo}/contents/.claude-plugin/plugin.json?ref=$tag',
    '-H',
    'Accept: application/vnd.github.raw+json',
  ]);
  return switch (jsonDecode(manifest)) {
    {'version': final String version} => PluginRelease(
      tag: tag,
      version: version,
    ),
    _ => throw FormatException(
      'No version in ${pin.repo} .claude-plugin/plugin.json at $tag.',
    ),
  };
}

Future<String> _gh(RunGh runGh, List<String> args) async {
  final result = await runGh(args);
  if (result.exitCode != 0) {
    throw ProcessException(
      'gh',
      args,
      '${result.stderr}'.trim(),
      result.exitCode,
    );
  }
  return '${result.stdout}';
}
