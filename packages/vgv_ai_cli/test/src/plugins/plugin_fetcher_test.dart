import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/cli/git_cli.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_fetcher.dart';

import 'fake_plugin_fetcher.dart';

class _MockGit extends Mock implements Git;

class _FakeDirectory extends Fake implements Directory;

String _slug(String repo) => repo.replaceAll('/', '__');

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDirectory());
    registerFallbackValue(Uri.parse('https://github.com/x/y.git'));
  });

  group('GitPluginFetcher', () {
    late Directory temp;
    late Git git;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('fetcher_test_');
      git = _MockGit();
      when(
        () => git.clone(
          remote: any(named: 'remote'),
          destination: any(named: 'destination'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => 'abc123');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('fetchMarketplace clones the marketplace repo', () async {
      final fetcher = GitPluginFetcher(workingDirectory: temp, git: git);

      final result = await fetcher.fetchMarketplace();

      expect(result.commit, 'abc123');
      final captured =
          verify(
                () => git.clone(
                  remote: captureAny(named: 'remote'),
                  destination: any(named: 'destination'),
                  ref: any(named: 'ref'),
                ),
              ).captured.single
              as Uri;
      expect('$captured', 'https://github.com/$vgvMarketplaceRepo.git');
    });

    test('fetchPlugin clones into a slug-safe subdirectory', () async {
      final fetcher = GitPluginFetcher(workingDirectory: temp, git: git);

      const repo = 'VeryGoodOpenSource/vgv-wingspan';
      final result = await fetcher.fetchPlugin(repo);

      expect(result.directory.path, p.join(temp.path, _slug(repo)));
      expect(result.directory.existsSync(), isTrue);
    });

    test('propagates git failures', () async {
      when(
        () => git.clone(
          remote: any(named: 'remote'),
          destination: any(named: 'destination'),
          ref: any(named: 'ref'),
        ),
      ).thenThrow(const GitNotFound());
      final fetcher = GitPluginFetcher(workingDirectory: temp, git: git);

      await expectLater(
        fetcher.fetchPlugin('a/b'),
        throwsA(isA<GitNotFound>()),
      );
    });
  });

  group('FakePluginFetcher', () {
    test('returns registered marketplace and plugin directories', () async {
      final market = Directory.systemTemp.createTempSync('market_');
      final plugin = Directory.systemTemp.createTempSync('plugin_');
      addTearDown(() {
        market.deleteSync(recursive: true);
        plugin.deleteSync(recursive: true);
      });
      final fetcher = FakePluginFetcher(
        marketplace: market,
        plugins: {'owner/plugin': plugin},
      );

      expect((await fetcher.fetchMarketplace()).directory.path, market.path);
      expect(
        (await fetcher.fetchPlugin('owner/plugin')).directory.path,
        plugin.path,
      );
    });

    test('throws for an unregistered plugin', () async {
      final market = Directory.systemTemp.createTempSync('market_');
      addTearDown(() => market.deleteSync(recursive: true));
      final fetcher = FakePluginFetcher(marketplace: market);

      await expectLater(
        fetcher.fetchPlugin('missing/plugin'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
