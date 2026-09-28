import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/reconcile/toml_edits.dart';

void main() {
  String upsert(
    String text,
    String key,
    Object value, {
    List<String> table = const [],
  }) => upsertTomlKey(text, table: table, key: key, value: value);

  Map<String, dynamic> parse(String text) => TomlDocument.parse(text).toMap();

  group('upsertTomlKey', () {
    test('writes a new table into an empty document', () {
      expect(
        upsert('', 'command', 'dart', table: ['mcp_servers', 'dart']),
        "[mcp_servers.dart]\ncommand = 'dart'\n",
      );
    });

    test('appends a new table after the existing text', () {
      expect(
        upsert('# mine\nmodel = "gpt"\n', 'command', 'dart', table: ['mcp']),
        "# mine\nmodel = \"gpt\"\n\n[mcp]\ncommand = 'dart'\n",
      );
    });

    test('quotes a table name that is not a bare key', () {
      final edited = upsert('', 'command', 'x', table: ['mcp', 'my server']);

      expect(parse(edited), {
        'mcp': {
          'my server': {'command': 'x'},
        },
      });
    });

    test('replaces a key where it stands, comments and all around it', () {
      const original =
          '# top\n[mcp]\n# the command\ncommand = "old" # note\nargs = []\n';

      expect(
        upsert(original, 'command', 'new', table: ['mcp']),
        "# top\n[mcp]\n# the command\ncommand = 'new'\nargs = []\n",
      );
    });

    test("adds a key after the table's last key", () {
      const original = '[mcp]\ncommand = "dart"\n\n# next\n[other]\nx = 1\n';

      expect(
        upsert(original, 'args', ['a'], table: ['mcp']),
        "[mcp]\ncommand = \"dart\"\nargs = ['a']\n\n# next\n[other]\nx = 1\n",
      );
    });

    test('adds a key right after the header of an empty table', () {
      expect(
        upsert('[mcp]\n\n[other]\n', 'command', 'dart', table: ['mcp']),
        "[mcp]\ncommand = 'dart'\n\n[other]\n",
      );
    });

    test('adds a top-level key after the last top-level key', () {
      expect(
        upsert('model = "gpt"\n\n[mcp]\nx = 1\n', 'effort', 'high'),
        "model = \"gpt\"\neffort = 'high'\n\n[mcp]\nx = 1\n",
      );
    });

    test('adds a top-level key first when there is none', () {
      expect(
        upsert('[mcp]\nx = 1\n', 'model', 'gpt'),
        "model = 'gpt'\n[mcp]\nx = 1\n",
      );
    });

    test('replaces a key whose value spans several lines', () {
      const original = '[mcp]\nargs = [\n  "a",\n  "b",\n]\nkept = 1\n';

      expect(
        upsert(original, 'args', ['c'], table: ['mcp']),
        "[mcp]\nargs = ['c']\nkept = 1\n",
      );
    });

    test('never takes a header inside a multiline string for a table', () {
      const original =
          'prompt = """\n[mcp]\nnot = "a key"\n"""\n'
          "notes = '''\n[mcp]\n'''\n";

      final edited = upsert(original, 'command', 'dart', table: ['mcp']);

      expect(parse(edited)['mcp'], {'command': 'dart'});
      expect(edited, startsWith(original));
    });

    test('reads past escaped quotes in a multiline basic string', () {
      const original = 'prompt = """\nsay \\""" and [mcp]\n"""\nx = 1\n';

      expect(
        upsert(original, 'x', 2),
        'prompt = """\nsay \\""" and [mcp]\n"""\nx = 2\n',
      );
    });

    test('ignores brackets inside strings and comments', () {
      const original =
          '[mcp]\n'
          'a = "[not" # ] nor this [\n'
          "b = '{also not'\n"
          'c = "escaped \\" [quote"\n'
          'd = { inline = [1, 2] }\n';

      final edited = upsert(original, 'e', 5, table: ['mcp']);

      expect(edited, '${original}e = 5\n');
    });

    test('ends a table at an array of tables header', () {
      const original = '[mcp]\nx = 1\n\n[[server]]\nname = "a"\n';

      expect(
        upsert(original, 'y', 2, table: ['mcp']),
        '[mcp]\nx = 1\ny = 2\n\n[[server]]\nname = "a"\n',
      );
    });

    test('matches quoted table names and keys', () {
      const original = '["mcp".\'my.server\']\n"command" = "old"\n';

      expect(
        upsert(original, 'command', 'new', table: ['mcp', 'my.server']),
        "[\"mcp\".'my.server']\ncommand = 'new'\n",
      );
    });

    test('keeps going when a string never closes', () {
      // Malformed input: the caller's parse check rejects the result.
      expect(upsert('a = "open\n', 'b', 1), 'a = "open\nb = 1\n');
      expect(upsert("a = 'open\n", 'b', 1), "a = 'open\nb = 1\n");
      expect(upsert('a = "open\\\n', 'b', 1), 'a = "open\\\nb = 1\n');
    });

    test('ends the last statement at the end of the text', () {
      expect(upsert('a = [\n  1,', 'b', 1), 'a = [\n  1,\nb = 1');
    });
  });
}
