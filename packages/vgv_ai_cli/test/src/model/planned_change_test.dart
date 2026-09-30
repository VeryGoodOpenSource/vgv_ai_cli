import 'dart:convert';

import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/model/planned_change.dart';

void main() {
  final fileSystem = MemoryFileSystem.test();

  group('PlannedChange', () {
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
}
