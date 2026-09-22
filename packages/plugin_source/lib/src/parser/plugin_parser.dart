import 'package:file/file.dart';
import 'package:plugin_source/src/model/plugin_assets.dart';

/// {@template plugin_parser}
/// Reads one harness's plugin files and produces the harness-neutral model.
///
/// This is the spoke of the hub-and-spoke design: each input harness has one
/// parser, and it is the single place that knows that harness's conventions.
/// Output translators depend only on the neutral [PluginAssets] a parser
/// returns, never on a parser itself, so adding an input harness is one new
/// implementation of this interface.
/// {@endtemplate}
abstract interface class PluginParser {
  /// Reads every asset under [root].
  PluginAssets parse(Directory root);
}
