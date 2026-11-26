import 'dart:io' show ProcessResult;

import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// A [RunProcess] whose `git clone` of a pinned plugin succeeds by writing the
/// plugin manifest into [fs], under the pin's path as a real clone has it.
RunProcess clonesPlugins(FileSystem fs) =>
    (executable, arguments, {runInShell = false}) async {
      final plugin = vgvPlugins.firstWhere(
        (plugin) => arguments.contains('https://github.com/${plugin.repo}.git'),
      );
      fs
          .file(
            fs.path.joinAll([
              arguments.last,
              ?plugin.path,
              '.claude-plugin',
              'plugin.json',
            ]),
          )
          .createSync(recursive: true);
      return ProcessResult(0, 0, '', '');
    };
