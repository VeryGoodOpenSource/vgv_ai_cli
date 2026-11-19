import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/model/model.dart';

/// The section of an instructions file such as `AGENTS.md` that the brick's
/// rendered instructions are written to.
const instructionsSection = 'instructions';

/// Plans the change that writes one file the `user_config` brick rendered.
///
/// The brick renders each harness into a folder named after it, laid out the
/// way [scope]'s root for that harness is. So the first segment of [path]
/// names the harness, and the rest is where the file goes under
/// `scope.harnessRoot`.
///
/// A file within `scope.sharedDepth` of that root is a config file the user
/// may already have edited, so it is merged. Anything deeper is an agent,
/// command or prompt VGV owns, so it is written whole. A shared markdown file
/// is merged as the [instructionsSection] section, next to anything the user
/// wrote.
PlannedChange renderedChange(
  String path, {
  required String contents,
  required Scope scope,
}) {
  final [folder, ...segments] = p.posix.split(path);
  final harness = Harness.values.byName(folder);
  final root = scope.harnessRoot(harness);
  final file = root.fileSystem.file(p.joinAll([root.path, ...segments]));
  final shared = segments.length <= scope.sharedDepth;

  PlannedChange planned(ChangeMode mode) => PlannedChange.text(
    file: file,
    contents: contents,
    harness: harness,
    mode: mode,
  );

  return switch ((shared, p.extension(path))) {
    (true, '.json') => planned(ChangeMode.mergeJson),
    (true, '.toml') => planned(ChangeMode.mergeToml),
    (true, _) => PlannedChange.markdown(
      file: file,
      contents: contents,
      harness: harness,
      section: instructionsSection,
    ),
    (false, _) => planned(ChangeMode.own),
  };
}
