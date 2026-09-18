import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/cli/git_cli.dart';

Future<void> _git(List<String> args, {required String cwd}) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
}

void main() {
  group('Git', () {
    late Directory temp;
    late Directory origin;
    late Uri remote;

    setUp(() async {
      temp = Directory.systemTemp.createTempSync('git_cli_test_');
      origin = Directory(p.join(temp.path, 'origin'))..createSync();
      await _git(['init', '--initial-branch=main'], cwd: origin.path);
      await _git(['config', 'user.email', 'test@vgv.dev'], cwd: origin.path);
      await _git(['config', 'user.name', 'Test'], cwd: origin.path);
      File(p.join(origin.path, 'README.md')).writeAsStringSync('hello');
      await _git(['add', '.'], cwd: origin.path);
      await _git(['commit', '-m', 'initial'], cwd: origin.path);
      remote = Uri.file(origin.path);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    const git = Git();

    test('reachable succeeds for an existing remote', () async {
      await expectLater(git.reachable(remote), completes);
    });

    test('reachable throws UnreachableRemote for a missing remote', () async {
      final missing = Uri.file(p.join(temp.path, 'nope'));
      await expectLater(
        git.reachable(missing),
        throwsA(isA<UnreachableRemote>()),
      );
    });

    test('clone checks out the repo and returns the commit sha', () async {
      final dest = Directory(p.join(temp.path, 'clone'));

      final commit = await git.clone(remote: remote, destination: dest);

      expect(File(p.join(dest.path, 'README.md')).existsSync(), isTrue);
      expect(commit, matches(RegExp(r'^[0-9a-f]{40}$')));
    });

    test('clone throws GitCloneFailure for a bad remote', () async {
      final dest = Directory(p.join(temp.path, 'bad'));
      final missing = Uri.file(p.join(temp.path, 'missing'));
      await expectLater(
        git.clone(remote: missing, destination: dest),
        throwsA(isA<GitCloneFailure>()),
      );
    });
  });
}
