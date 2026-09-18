import 'dart:io';

import 'package:vgv_ai_cli/src/plugins/plugin_fetcher.dart';

/// A [PluginFetcher] backed by local directories.
///
/// Lets tests exercise the resolution pipeline without touching the network.
/// The marketplace directory is returned by `fetchMarketplace` and the plugins
/// map keys a plugin repo slug to the directory returned by `fetchPlugin`.
class FakePluginFetcher implements PluginFetcher {
  new({
    required this._marketplace,
    this._plugins = const {},
    this._commit = 'fixturecommit',
  });

  final Directory _marketplace;
  final Map<String, Directory> _plugins;
  final String _commit;

  @override
  Future<FetchedRepo> fetchMarketplace() async =>
      FetchedRepo(directory: _marketplace, commit: _commit);

  @override
  Future<FetchedRepo> fetchPlugin(String repo, {String? ref}) async {
    final directory = _plugins[repo];
    if (directory == null) {
      throw ArgumentError.value(repo, 'repo', 'No fake plugin registered');
    }
    return FetchedRepo(directory: directory, commit: '$_commit-$repo');
  }
}
