import 'package:plugin_source/plugin_source.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/finding.dart';

/// {@template plugin_status}
/// How the version of a plugin a home was installed from compares with the
/// version this CLI pins.
/// {@endtemplate}
enum PluginStatus {
  /// The versions match.
  current,

  /// The installed version is older than the pin, or cannot be compared.
  older,

  /// The installed version is newer than the pin, because the CLI was
  /// downgraded since.
  newer,

  /// The manifest records no version for the plugin.
  unrecorded,
}

/// {@template plugin_version}
/// A pinned [plugin] and the version a home was installed from.
/// {@endtemplate}
class const PluginVersion._({
  /// The plugin as this CLI pins it.
  required final PluginRef plugin,

  /// How [installed] compares with the pin.
  required final PluginStatus status,

  /// The version the manifest records, or null when it records none.
  final String? installed,
}) {
  /// {@macro plugin_version}
  ///
  /// Compares [installed] with the version [plugin] is pinned to.
  factory of(PluginRef plugin, {required String? installed}) => PluginVersion._(
    plugin: plugin,
    installed: installed,
    status: _compare(installed, plugin.version),
  );

  static PluginStatus _compare(String? installed, String pinned) {
    if (installed == null) return PluginStatus.unrecorded;
    if (installed == pinned) return PluginStatus.current;
    try {
      return Version.parse(installed) > Version.parse(pinned)
          ? PluginStatus.newer
          : PluginStatus.older;
    } on FormatException {
      return PluginStatus.older;
    }
  }

  /// What the report says about this plugin.
  Finding get finding {
    final name = plugin.name;
    final pinned = plugin.version;
    return switch (status) {
      PluginStatus.current => Finding.current('$name $pinned'),
      PluginStatus.older => Finding.stale(
        '$name $installed installed, $pinned pinned',
      ),
      PluginStatus.newer => Finding.stale(
        '$name $installed installed, newer than the pinned $pinned',
      ),
      PluginStatus.unrecorded => Finding.suggestion(
        '$name $pinned not installed',
      ),
    };
  }
}
