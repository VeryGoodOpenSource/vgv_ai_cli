import 'dart:convert';

import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  final fileSystem = MemoryFileSystem.test();

  group(PlannedChange, () {
    test('toString names the mode, the owner and the path', () {
      final change = PlannedChange.text(
        file: fileSystem.file('/home/user/.codex/config.toml'),
        contents: 'body',
        harness: Harness.codex,
        mode: ChangeMode.mergeToml,
      );

      expect(
        change.toString(),
        '[mergeToml] (codex) /home/user/.codex/config.toml',
      );
    });

    test('toString reports an ownerless change as shared', () {
      // `~/.agents/skills` is written once and read by four harnesses, so it
      // belongs to none of them.
      final change = PlannedChange.text(
        file: fileSystem.file('/home/user/.agents/skills/testing/SKILL.md'),
        contents: 'body',
        harness: null,
      );

      expect(
        change.toString(),
        '[own] (shared) /home/user/.agents/skills/testing/SKILL.md',
      );
    });

    test('requires an explicit null for a shared change', () {
      // Required rather than defaulted: a forgotten tag would otherwise be
      // indistinguishable from a deliberate shared write, which uninstall
      // treats differently.
      final change = PlannedChange.text(
        file: fileSystem.file('/home/user/.gemini/settings.json'),
        contents: '{}',
        harness: null,
        mode: ChangeMode.mergeJson,
      );

      expect(change.harness, isNull);
    });

    test('encodes text as UTF-8 and decodes it back', () {
      final change = PlannedChange.text(
        file: fileSystem.file('/home/user/.gemini/agents/a.md'),
        contents: 'café',
        harness: null,
      );

      expect(change.bytes, utf8.encode('café'));
      expect(change.contents, 'café');
      expect(change.source, isNull);
    });

    test('carries raw bytes and the file they were copied from', () {
      final source = fileSystem.file('/plugin/skills/a/run.sh');
      final change = PlannedChange(
        file: fileSystem.file('/home/user/.agents/skills/a/run.sh'),
        bytes: const [0xff],
        harness: null,
        source: source,
      );

      expect(change.bytes, [0xff]);
      expect(change.source, source);
    });

    test('names the section a markdown merge writes', () {
      final change = PlannedChange.markdown(
        file: fileSystem.file('/home/user/.gemini/AGENTS.md'),
        contents: '# VGV',
        harness: Harness.gemini,
        section: 'instructions',
      );

      expect(change.mode, ChangeMode.mergeMarkdown);
      expect(change.section, 'instructions');
      expect(change.contents, '# VGV');
      expect(change.source, isNull);
    });

    test('has no section for any other mode', () {
      final change = PlannedChange.text(
        file: fileSystem.file('/home/user/.gemini/settings.json'),
        contents: '{}',
        harness: null,
        mode: ChangeMode.mergeJson,
      );

      expect(change.section, isNull);
    });

    test('leaves a markdown merge to PlannedChange.markdown', () {
      expect(
        () => PlannedChange.text(
          file: fileSystem.file('/home/user/.gemini/AGENTS.md'),
          contents: '# VGV',
          harness: null,
          mode: ChangeMode.mergeMarkdown,
        ),
        throwsArgumentError,
      );
    });

    test('carries the harness it was given, and owns its file by default', () {
      final change = PlannedChange.text(
        file: fileSystem.file('/home/user/.gemini/agents/a.md'),
        contents: 'body',
        harness: Harness.gemini,
      );

      expect(change.harness, Harness.gemini);
      expect(change.mode, ChangeMode.own);
    });
  });

  group(ChangeMode, () {
    test('has the format of each document merge, and of nothing else', () {
      expect(ChangeMode.mergeJson.format, DocumentFormat.json);
      expect(ChangeMode.mergeToml.format, DocumentFormat.toml);
      expect(ChangeMode.own.format, isNull);
      expect(ChangeMode.mergeMarkdown.format, isNull);
    });
  });

  group(DocumentFormat, () {
    test('has the mode that merges into it', () {
      expect(DocumentFormat.json.mode, ChangeMode.mergeJson);
      expect(DocumentFormat.toml.mode, ChangeMode.mergeToml);
    });

    test('decodes and encodes its own format', () {
      expect(DocumentFormat.json.decode('{"a": [1]}'), {
        'a': [1],
      });
      expect(DocumentFormat.json.encode({'a': 1}), '{\n  "a": 1\n}\n');
      expect(DocumentFormat.toml.decode('[mcp.dart]\ncommand = "dart"\n'), {
        'mcp': {
          'dart': {'command': 'dart'},
        },
      });
      expect(DocumentFormat.toml.encode({'a': 1}), 'a = 1\n');
    });

    test('decodes null for malformed JSON or anything but an object', () {
      expect(DocumentFormat.json.decode('{ "a": 1, // mine\n}'), isNull);
      expect(DocumentFormat.json.decode('[1]'), isNull);
    });

    test('decodes null for TOML it cannot parse or that redefines a key', () {
      expect(DocumentFormat.toml.decode('[unclosed'), isNull);
      expect(DocumentFormat.toml.decode('a = 1\na = 2\n'), isNull);
    });

    test('encodes TOML with a single trailing newline', () {
      final encoded = DocumentFormat.toml.encode({'model': 'gpt'});

      expect(encoded, endsWith('\n'));
      expect(encoded, isNot(endsWith('\n\n')));
      expect(DocumentFormat.toml.decode(encoded), {'model': 'gpt'});
    });
  });
}
