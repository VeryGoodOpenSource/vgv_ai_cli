import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/reconcile/toml_reconciler.dart';

void main() {
  group('TomlReconciler', () {
    const reconciler = TomlReconciler();
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('toml_reconciler_test_');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    File file(String name, [String? contents]) {
      final f = File(p.join(temp.path, name));
      if (contents != null) f.writeAsStringSync(contents);
      return f;
    }

    Map<String, dynamic> read(File f) =>
        TomlDocument.parse(f.readAsStringSync()).toMap();

    test('creates the destination when it does not exist', () async {
      final staged = file('staged.toml', '''
[mcp_servers.dart]
command = "dart"
''');
      final destination = File(p.join(temp.path, 'nested', 'config.toml'));

      await reconciler.reconcile(staged: staged, destination: destination);

      expect(read(destination), {
        'mcp_servers': {
          'dart': {'command': 'dart'},
        },
      });
    });

    test('preserves user tables while merging VGV servers', () async {
      final staged = file('staged.toml', '''
[mcp_servers.dart]
command = "dart"
''');
      final destination = file('config.toml', '''
model = "gpt-5"

[mcp_servers.mine]
command = "mine"
''');

      await reconciler.reconcile(staged: staged, destination: destination);

      expect(read(destination), {
        'model': 'gpt-5',
        'mcp_servers': {
          'mine': {'command': 'mine'},
          'dart': {'command': 'dart'},
        },
      });
    });

    test('round-trips a staged server through re-serialization', () async {
      final staged = file('staged.toml', '''
[mcp_servers.very-good-cli]
command = "very_good"
args = ["mcp"]

[mcp_servers.very-good-cli.env]
VGV_TOKEN = "abc123"
''');
      final destination = file('config.toml');

      await reconciler.reconcile(staged: staged, destination: destination);

      expect(read(destination), {
        'mcp_servers': {
          'very-good-cli': {
            'command': 'very_good',
            'args': ['mcp'],
            'env': {'VGV_TOKEN': 'abc123'},
          },
        },
      });
    });
  });
}
