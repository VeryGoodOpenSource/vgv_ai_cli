import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/reconcile/json_reconciler.dart';

void main() {
  group('JsonReconciler', () {
    const reconciler = JsonReconciler();
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('json_reconciler_test_');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    File file(String name, [String? contents]) {
      final f = File(p.join(temp.path, name));
      if (contents != null) f.writeAsStringSync(contents);
      return f;
    }

    Map<String, dynamic> read(File f) =>
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

    test('creates the destination when it does not exist', () async {
      final staged = file('staged.json', '{"vgv": true}');
      final destination = File(p.join(temp.path, 'nested', 'dest.json'));

      await reconciler.reconcile(staged: staged, destination: destination);

      expect(destination.existsSync(), isTrue);
      expect(read(destination), {'vgv': true});
    });

    test('preserves user keys while adding and overriding VGV keys', () async {
      final staged = file('staged.json', '''
{"mcpServers": {"dart": {"command": "dart"}}, "shared": "vgv"}
''');
      final destination = file('dest.json', '''
{"mcpServers": {"mine": {"command": "mine"}}, "shared": "user", "keep": 1}
''');

      await reconciler.reconcile(staged: staged, destination: destination);

      expect(read(destination), {
        'mcpServers': {
          'mine': {'command': 'mine'},
          'dart': {'command': 'dart'},
        },
        'shared': 'vgv',
        'keep': 1,
      });
    });

    test('writes indented JSON with a trailing newline', () async {
      final staged = file('staged.json', '{"a": 1}');
      final destination = file('dest.json');

      await reconciler.reconcile(staged: staged, destination: destination);

      expect(destination.readAsStringSync(), '{\n  "a": 1\n}\n');
    });
  });
}
