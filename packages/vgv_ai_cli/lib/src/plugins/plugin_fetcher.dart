import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/cli/git_cli.dart';

/// The `owner/name` slug of the Very Good Claude marketplace repository.
const vgvMarketplaceRepo = 'VeryGoodOpenSource/very_good_claude_marketplace';

/// {@template fetched_repo}
/// A repository checked out on disk together with its resolved commit.
/// {@endtemplate}
class const FetchedRepo({
  required final Directory directory,
  required final String commit,
});

/// {@template plugin_fetcher}
/// Fetches the marketplace and plugin repositories the resolver reads from.
///
/// Kept behind an interface so tests inject a fake backed by local fixtures and
/// never touch the network.
/// {@endtemplate}
abstract interface class PluginFetcher {
  /// Fetches the Very Good Claude marketplace repository.
  Future<FetchedRepo> fetchMarketplace();

  /// Fetches the plugin repository identified by its `owner/name` [repo] slug.
  ///
  /// When [commit] is provided the repository is checked out at that exact
  /// commit, reproducing a locked install.
  Future<FetchedRepo> fetchPlugin(String repo, {String? ref, String? commit});
}

/// {@template git_plugin_fetcher}
/// A [PluginFetcher] that clones repositories from GitHub with [Git].
///
/// Each repository is cloned into a subdirectory of the working directory,
/// named after the repository so repeated fetches are isolated.
/// {@endtemplate}
class GitPluginFetcher implements PluginFetcher {
  /// {@macro git_plugin_fetcher}
  const new({required this._workingDirectory, this._git = const Git()});

  final Directory _workingDirectory;
  final Git _git;

  @override
  Future<FetchedRepo> fetchMarketplace() => fetchPlugin(vgvMarketplaceRepo);

  @override
  Future<FetchedRepo> fetchPlugin(
    String repo, {
    String? ref,
    String? commit,
  }) async {
    final destination = Directory(
      p.join(_workingDirectory.path, repo.replaceAll('/', '__')),
    );
    if (destination.existsSync()) destination.deleteSync(recursive: true);
    destination.createSync(recursive: true);

    final remote = Uri.parse('https://github.com/$repo.git');
    final resolved = await _git.clone(
      remote: remote,
      destination: destination,
      ref: ref,
      commit: commit,
    );

    return FetchedRepo(directory: destination, commit: resolved);
  }
}
