import 'package:file/file.dart';
import 'package:file/local.dart';

/// The home directory [environment] names, or null when it names none.
Directory? userHome(Map<String, String> environment) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  return home == null ? null : const LocalFileSystem().directory(home);
}
