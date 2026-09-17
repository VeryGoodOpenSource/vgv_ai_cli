import 'package:hooks/models/marketplace/marketplace.dart';
import 'package:hooks/models/vgv_plugin.dart';
import 'package:json_annotation/json_annotation.dart';

part 'claude_settings.g.dart';

/// {@template claude_settings}
/// The settings fragment merged into `~/.claude/settings.json`.
///
/// Rather than copying plugin files, Claude Code is pointed at a marketplace
/// and the VGV plugins are enabled against it.
/// {@endtemplate}
@JsonSerializable(createFactory: false, explicitToJson: true)
class const ClaudeSettings({
  required final Map<String, Marketplace> extraKnownMarketplaces,
  required final Map<String, bool> enabledPlugins,
}) {
  /// Enables every [plugins] entry against [marketplace].
  factory forMarketplace(Marketplace marketplace, List<VGVPlugin> plugins) =>
      ClaudeSettings(
        extraKnownMarketplaces: {marketplace.repo: marketplace},
        enabledPlugins: {
          for (final plugin in plugins)
            '${plugin.name}@${marketplace.repo}': true,
        },
      );

  /// Serializes the settings fragment to JSON.
  Map<String, dynamic> toJson() => _$ClaudeSettingsToJson(this);
}
