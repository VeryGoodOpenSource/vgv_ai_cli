import 'dart:io' show Platform;

import 'package:file/file.dart';
import 'package:file/local.dart';

/// The home directory [environment] names, or null when it names none.
Directory? userHome(Map<String, String> environment) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  return home == null ? null : const LocalFileSystem().directory(home);
}

/// The directory a command works on: [override] when one was injected, and
/// otherwise the home directory [environment], or the real one, names.
Directory? commandHome(Directory? override, Map<String, String>? environment) =>
    override ?? userHome(environment ?? Platform.environment);
