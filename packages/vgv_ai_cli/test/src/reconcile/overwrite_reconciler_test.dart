import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/reconcile/overwrite_reconciler.dart';

void main() {
  group('OverwriteReconciler', () {
    const reconciler = OverwriteReconciler();
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('overwrite_reconciler_test_');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('creates the destination when it does not exist', () async {
      final staged = File(p.join(temp.path, 'staged.md'))
        ..writeAsStringSync('# Managed');
      final destination = File(p.join(temp.path, 'nested', 'AGENTS.md'));

      await reconciler.reconcile(staged: staged, destination: destination);

      expect(destination.readAsStringSync(), '# Managed');
    });

    test('overwrites existing content wholesale', () async {
      final staged = File(p.join(temp.path, 'staged.md'))
        ..writeAsStringSync('# New');
      final destination = File(p.join(temp.path, 'AGENTS.md'))
        ..writeAsStringSync('# Old user content');

      await reconciler.reconcile(staged: staged, destination: destination);

      expect(destination.readAsStringSync(), '# New');
    });
  });
}
