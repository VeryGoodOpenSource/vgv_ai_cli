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

    test('GitNotFound describes the missing executable', () {
      expect(
        const GitNotFound().toString(),
        'git is not installed or not on your PATH. Install git and try again.',
      );
    });

    test('GitCloneFailure describes the remote and the git output', () {
      final failedRemote = Uri.parse('https://example.com/repo.git');
      expect(
        GitCloneFailure(failedRemote, 'fatal: boom').toString(),
        'Failed to clone $failedRemote: fatal: boom',
      );
    });

    test('clone checks out the repo and returns the commit sha', () async {
      final dest = Directory(p.join(temp.path, 'clone'));

      final commit = await git.clone(remote: remote, destination: dest);

      expect(File(p.join(dest.path, 'README.md')).existsSync(), isTrue);
      expect(commit, matches(RegExp(r'^[0-9a-f]{40}$')));
    });

    test('clone checks out an exact commit when one is pinned', () async {
      // A second commit becomes HEAD; pinning must still land on the first.
      final first = await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: origin.path);
      final firstSha = '${first.stdout}'.trim();
      File(p.join(origin.path, 'SECOND.md')).writeAsStringSync('second');
      await _git(['add', '.'], cwd: origin.path);
      await _git(['commit', '-m', 'second'], cwd: origin.path);

      final dest = Directory(p.join(temp.path, 'pinned'));
      final commit = await git.clone(
        remote: remote,
        destination: dest,
        commit: firstSha,
      );

      expect(commit, firstSha);
      expect(File(p.join(dest.path, 'README.md')).existsSync(), isTrue);
      expect(File(p.join(dest.path, 'SECOND.md')).existsSync(), isFalse);
    });

    test('clone throws GitCloneFailure for a bad remote', () async {
      final dest = Directory(p.join(temp.path, 'bad'));
      final missing = Uri.file(p.join(temp.path, 'missing'));
      await expectLater(
        git.clone(remote: missing, destination: dest),
        throwsA(isA<GitCloneFailure>()),
      );
    });

    test('clone checks out the given ref', () async {
      await _git(['checkout', '-b', 'feature'], cwd: origin.path);
      File(p.join(origin.path, 'FEATURE.md')).writeAsStringSync('feature');
      await _git(['add', '.'], cwd: origin.path);
      await _git(['commit', '-m', 'feature'], cwd: origin.path);
      await _git(['checkout', 'main'], cwd: origin.path);

      final dest = Directory(p.join(temp.path, 'ref-clone'));
      await git.clone(remote: remote, destination: dest, ref: 'feature');

      expect(File(p.join(dest.path, 'FEATURE.md')).existsSync(), isTrue);
    });

    test(
      'clone throws GitCloneFailure when pinning an unknown commit',
      () async {
        final dest = Directory(p.join(temp.path, 'bad-commit'));
        await expectLater(
          git.clone(remote: remote, destination: dest, commit: '0' * 40),
          throwsA(isA<GitCloneFailure>()),
        );
      },
    );

    test('throws GitNotFound when the git executable is missing', () async {
      final missingGit = Git(
        processRunner: (executable, arguments, {workingDirectory}) async =>
            throw const ProcessException('git', []),
      );
      final dest = Directory(p.join(temp.path, 'no-git'));

      await expectLater(
        missingGit.clone(remote: remote, destination: dest),
        throwsA(isA<GitNotFound>()),
      );
    });
  });
}
