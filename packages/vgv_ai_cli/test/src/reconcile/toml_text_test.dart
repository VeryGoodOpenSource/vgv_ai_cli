import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/reconcile/toml_text.dart';

void main() {
  String upsert(
    String text, {
    required String key,
    required Object value,
    List<String> table = const [],
  }) => TomlText(text).upsert(table: table, key: key, value: value).source;

  Map<String, dynamic> parse(String text) => TomlDocument.parse(text).toMap();

  group('TomlText.upsert', () {
    test('writes a new table into an empty document', () {
      expect(
        upsert(
          '',
          key: 'command',
          value: 'dart',
          table: ['mcp_servers', 'dart'],
        ),
        "[mcp_servers.dart]\ncommand = 'dart'\n",
      );
    });

    test('appends a new table after the existing text', () {
      expect(
        upsert(
          '# mine\nmodel = "gpt"\n',
          key: 'command',
          value: 'dart',
          table: ['mcp'],
        ),
        "# mine\nmodel = \"gpt\"\n\n[mcp]\ncommand = 'dart'\n",
      );
    });

    test('quotes a table name that is not a bare key', () {
      final edited = upsert(
        '',
        key: 'command',
        value: 'x',
        table: ['mcp', 'my server'],
      );

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
        upsert(original, key: 'command', value: 'new', table: ['mcp']),
        "# top\n[mcp]\n# the command\ncommand = 'new' # note\nargs = []\n",
      );
    });

    test("adds a key after the table's last key", () {
      const original = '[mcp]\ncommand = "dart"\n\n# next\n[other]\nx = 1\n';

      expect(
        upsert(original, key: 'args', value: ['a'], table: ['mcp']),
        "[mcp]\ncommand = \"dart\"\nargs = ['a']\n\n# next\n[other]\nx = 1\n",
      );
    });

    test('adds a key right after the header of an empty table', () {
      expect(
        upsert(
          '[mcp]\n\n[other]\n',
          key: 'command',
          value: 'dart',
          table: ['mcp'],
        ),
        "[mcp]\ncommand = 'dart'\n\n[other]\n",
      );
    });

    test('adds a top-level key after the last top-level key', () {
      expect(
        upsert('model = "gpt"\n\n[mcp]\nx = 1\n', key: 'effort', value: 'high'),
        "model = \"gpt\"\neffort = 'high'\n\n[mcp]\nx = 1\n",
      );
    });

    test('adds a top-level key first when there is none', () {
      expect(
        upsert('[mcp]\nx = 1\n', key: 'model', value: 'gpt'),
        "model = 'gpt'\n[mcp]\nx = 1\n",
      );
    });

    test('replaces a key whose value spans several lines', () {
      const original = '[mcp]\nargs = [\n  "a",\n  "b",\n]\nkept = 1\n';

      expect(
        upsert(original, key: 'args', value: ['c'], table: ['mcp']),
        "[mcp]\nargs = ['c']\nkept = 1\n",
      );
    });

    test('never takes a header inside a multiline string for a table', () {
      const original =
          'prompt = """\n[mcp]\nnot = "a key"\n"""\n'
          "notes = '''\n[mcp]\n'''\n";

      final edited = upsert(
        original,
        key: 'command',
        value: 'dart',
        table: ['mcp'],
      );

      expect(parse(edited)['mcp'], {'command': 'dart'});
      expect(edited, startsWith(original));
    });

    test('reads past escaped quotes in a multiline basic string', () {
      const original = 'prompt = """\nsay \\""" and [mcp]\n"""\nx = 1\n';

      expect(
        upsert(original, key: 'x', value: 2),
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

      final edited = upsert(original, key: 'e', value: 5, table: ['mcp']);

      expect(edited, '${original}e = 5\n');
    });

    test('ends a table at an array of tables header', () {
      const original = '[mcp]\nx = 1\n\n[[server]]\nname = "a"\n';

      expect(
        upsert(original, key: 'y', value: 2, table: ['mcp']),
        '[mcp]\nx = 1\ny = 2\n\n[[server]]\nname = "a"\n',
      );
    });

    test('matches quoted table names and keys', () {
      const original = '["mcp".\'my.server\']\n"command" = "old"\n';

      expect(
        upsert(
          original,
          key: 'command',
          value: 'new',
          table: ['mcp', 'my.server'],
        ),
        "[\"mcp\".'my.server']\ncommand = 'new'\n",
      );
    });

    test('keeps going when a string never closes', () {
      // Malformed input: the caller's parse check rejects the result.
      expect(upsert('a = "open\n', key: 'b', value: 1), 'a = "open\nb = 1\n');
      expect(upsert("a = 'open\n", key: 'b', value: 1), "a = 'open\nb = 1\n");
      expect(
        upsert('a = "open\\\n', key: 'b', value: 1),
        'a = "open\\\nb = 1\n',
      );
    });

    test('ends the last statement at the end of the text', () {
      expect(upsert('a = [\n  1,', key: 'b', value: 1), 'a = [\n  1,\nb = 1');
    });

    test('keeps the comment after a value that spans several lines', () {
      const original = 'args = [\n  "a",\n]  # kept\n';

      expect(
        upsert(original, key: 'args', value: ['b']),
        "args = ['b']  # kept\n",
      );
    });

    test('leaves a value with a comment inside it as it is', () {
      const original = 'args = [\n  "a", # mine\n]\n';

      expect(upsert(original, key: 'args', value: ['b']), original);
    });

    test('reads a comment inside a multiline string as the value', () {
      const original = 'a = """\n# text\n"""\n';

      expect(upsert(original, key: 'a', value: 'b'), "a = 'b'\n");
    });

    test('decodes keys the way TOML does, keeping quoted whitespace', () {
      final edited = upsert(
        '[" a "]\nx = 1\n',
        key: 'y',
        value: 2,
        table: ['a'],
      );

      expect(parse(edited), {
        ' a ': {'x': 1},
        'a': {'y': 2},
      });
    });

    test('matches nothing on a line that does not start with a key', () {
      // Malformed input: the caller's parse check rejects the result.
      expect(upsert('= 1\n', key: 'b', value: 1), '= 1\nb = 1\n');
    });
  });

  group('TomlText.edit', () {
    String? edit(String original, {required Map<String, dynamic> merged}) {
      final existing = parse(original);
      return TomlText(original)
          .edit(
            existing: existing,
            merged: merged,
            added: {
              for (final MapEntry(:key, :value) in merged.entries)
                if (!existing.containsKey(key)) key: value,
            },
          )
          ?.source;
    }

    test('appends a new table after the existing text', () {
      expect(
        edit(
          '# mine\nmodel = "gpt"\n',
          merged: {
            'model': 'gpt',
            'mcp': {'command': 'dart'},
          },
        ),
        "# mine\nmodel = \"gpt\"\n\n[mcp]\ncommand = 'dart'\n",
      );
    });

    test('upserts a key when appending would repeat a table', () {
      expect(
        edit(
          '[mcp] # mine\ncommand = "dart"\n',
          merged: {
            'mcp': {
              'command': 'dart',
              'args': ['x'],
            },
          },
        ),
        "[mcp] # mine\ncommand = \"dart\"\nargs = ['x']\n",
      );
    });

    test('keeps CRLF line endings', () {
      expect(
        edit(
          '# mine\r\n[mcp]\r\ncommand = "old" # pinned\r\n',
          merged: {
            'mcp': {'command': 'new'},
          },
        ),
        "# mine\r\n[mcp]\r\ncommand = 'new' # pinned\r\n",
      );
    });

    test('is null when an edit would drop a comment inside a value', () {
      expect(
        edit(
          '[mcp]\nargs = [\n  "a", # mine\n]\n',
          merged: {
            'mcp': {
              'args': ['a', 'b'],
            },
          },
        ),
        isNull,
      );
    });

    test('is null when no edit decodes to the merge', () {
      expect(
        edit(
          'mcp.args = ["a"]\n',
          merged: {
            'mcp': {
              'args': ['a', 'b'],
            },
          },
        ),
        isNull,
      );
    });
  });

  group('TomlText.decode', () {
    test('is null for a malformed document', () {
      expect(const TomlText('[unterminated').decode(), isNull);
    });
  });
}
