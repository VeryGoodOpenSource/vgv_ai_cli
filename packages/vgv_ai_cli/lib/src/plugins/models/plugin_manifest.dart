import 'dart:convert';

import 'package:vgv_ai_cli/src/plugins/models/parsed_plugin.dart';

/// {@template plugin_manifest}
/// The complete, versioned description of one or more Claude plugins.
///
/// This is the contract mason bricks generate from. It holds many plugins
/// rather than one, because the real case is generating several plugins into a
/// single install, and merging separate manifests afterwards would push
/// cross-plugin id collisions onto the brick layer, which cannot resolve them.
/// {@endtemplate}
class PluginManifest {
  /// {@macro plugin_manifest}
  new({required List<ParsedPlugin> plugins, this.schemaVersion = currentSchema})
    : plugins = List<ParsedPlugin>.unmodifiable(
        <ParsedPlugin>[...plugins]
          ..sort((a, b) => a.metadata.name.compareTo(b.metadata.name)),
      );

  /// The schema this producer emits.
  ///
  /// Consumers read it and fail hard on a mismatch. Nothing validates it here.
  static const currentSchema = 1;

  /// The schema version of this manifest.
  final int schemaVersion;

  /// The plugins described, sorted by name.
  final List<ParsedPlugin> plugins;

  /// This manifest as a JSON map.
  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'plugins': plugins.map((p) => p.toJson()).toList(),
  };

  /// This manifest as indented JSON with a trailing newline.
  ///
  /// Deterministic: plugins are sorted by name, agents by id, and every map
  /// lifted out of YAML has sorted keys.
  String toJsonString() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}
