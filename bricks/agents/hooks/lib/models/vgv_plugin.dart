/// A plugin enabled on the harness.
///
/// [name] is the plugin identifier as published on the marketplace.
class const VGVPlugin(final String name) {
  /// The VGV Wingspan plugin.
  const new wingspan() : this('vgv-wingspan');

  /// The VGV AI Flutter plugin.
  const new aiFlutter() : this('vgv-ai-flutter-plugin');
}
