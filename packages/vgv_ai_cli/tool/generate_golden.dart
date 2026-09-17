// Regenerates the golden manifest fixture from the sample plugin tree.
//
// Run from the package root:
//   dart run tool/generate_golden.dart
//
// Review the diff before committing. The golden file is the contract the brick
// workstream builds against, so an unreviewed regeneration can lock in a bug.
import 'dart:io';

import 'package:vgv_ai_cli/src/plugins/plugins.dart';

void main() {
  const parser = PluginParser();
  final manifest = parser.parseAll([
    (
      directory: Directory('test/fixtures/sample_plugin'),
      source: const PluginSource(
        repo: 'https://github.com/example/sample-plugin',
        ref: 'v0.1.0',
      ),
    ),
  ]);
  File('test/fixtures/sample_plugin_manifest.json')
      .writeAsStringSync(manifest.toJsonString());
  stdout.writeln('wrote test/fixtures/sample_plugin_manifest.json');
}
