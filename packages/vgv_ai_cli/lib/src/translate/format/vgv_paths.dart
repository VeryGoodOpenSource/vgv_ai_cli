import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/model/model.dart';

/// Where [harness] keeps the files its hooks file points at.
Directory harnessHooksRoot(Harness harness, {required Directory home}) {
  final config = harness.configDirectory(home);
  return config.fileSystem.directory(p.join(config.path, 'hooks'));
}
