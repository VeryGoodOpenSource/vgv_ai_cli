import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/model/model.dart';

/// The section of an instructions file such as `AGENTS.md` that the brick's
/// rendered instructions are written to.
const instructionsSection = 'instructions';

/// Plans the change that writes one file the `agents` brick rendered.
///
/// The brick renders each harness into a folder named after it, laid out the
/// way that harness's config directory is. So the first segment of [path]
/// names the harness, and the rest is where the file goes under its config
/// directory.
///
/// A file at the root of the folder is a config file the user may already
/// have edited, so it is merged. Anything deeper is an agent, command or
/// prompt VGV owns, so it is written whole. A root markdown file is merged
/// as the [instructionsSection] section, next to anything the user wrote.
PlannedChange renderedChange(
  String path, {
  required String contents,
  required Directory home,
}) {
  final [folder, ...segments] = p.posix.split(path);
  final harness = Harness.values.byName(folder);
  final file = home.fileSystem.file(
    p.joinAll([harness.configDirectory(home).path, ...segments]),
  );

  PlannedChange planned(ChangeMode mode) => PlannedChange.text(
    file: file,
    contents: contents,
    harness: harness,
    mode: mode,
  );

  return switch ((segments.length, p.extension(path))) {
    (1, '.json') => planned(ChangeMode.mergeJson),
    (1, '.toml') => planned(ChangeMode.mergeToml),
    (1, _) => PlannedChange.markdown(
      file: file,
      contents: contents,
      harness: harness,
      section: instructionsSection,
    ),
    _ => planned(ChangeMode.own),
  };
}
