import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/translate.dart';

import '_assets.dart';

const StagedOutput _staged = {
  StagedPaths.claudeSettings: '{}',
  StagedPaths.geminiSettings: '{}',
  StagedPaths.codexConfig: 'model = "gpt"\n',
  StagedPaths.openCodeConfig: '{}',
  StagedPaths.piSettings: '{}',
};

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);
  });

  TranslationResult translate(
    HarnessTranslator translator,
    List<HookAsset> hooks,
  ) => translator.translate(
    assets: pluginAssets(hooks: hooks),
    home: home,
    staged: _staged,
  );

  Map<String, dynamic> jsonAt(TranslationResult result, String suffix) =>
      jsonDecode(
        result.changes.lastWhere((c) => c.file.path.endsWith(suffix)).contents,
      ) as Map<String, dynamic>;

  group('Gemini hooks', () {
    test('renames the events to Gemini lifecycle points', () {
      final result = translate(const GeminiTranslator(), [
        hookAsset(fs, event: 'PreToolUse', matcher: 'Read'),
        hookAsset(fs),
      ]);

      final hooks = jsonAt(result, 'settings.json')['hooks'] as Map;

      expect(hooks.keys, containsAll(['BeforeTool', 'AfterTool']));
    });

    test('renames the tools a matcher names', () {
      final result = translate(const GeminiTranslator(), [
        hookAsset(fs, event: 'PreToolUse', matcher: 'Read|Glob|Bash'),
      ]);

      final hooks = jsonAt(result, 'settings.json')['hooks'] as Map;
      final registration = (hooks['BeforeTool'] as List).single as Map;

      expect(registration['matcher'], 'read_file|glob|run_shell_command');
    });

    test('keeps an unmappable matcher and says it may not fire', () {
      // Dropping it would silently widen the matcher to every tool.
      final result = translate(const GeminiTranslator(), [
        hookAsset(fs, event: 'PreToolUse', matcher: 'mcp__.*very-good-cli__.*'),
      ]);

      expect(
        result.notes.map((n) => n.reason),
        contains(contains('may not fire')),
      );
    });

    test('converts the timeout from seconds to milliseconds', () {
      final result = translate(const GeminiTranslator(), [hookAsset(fs)]);

      final hooks = jsonAt(result, 'settings.json')['hooks'] as Map;
      final registration = (hooks['AfterTool'] as List).single as Map;
      final command = (registration['hooks'] as List).single as Map;

      expect(command['timeout'], 30000);
    });

    test('points the command at the copied script', () {
      final result = translate(const GeminiTranslator(), [hookAsset(fs)]);

      final hooks = jsonAt(result, 'settings.json')['hooks'] as Map;
      final registration = (hooks['AfterTool'] as List).single as Map;
      final command = (registration['hooks'] as List).single as Map;

      expect(
        command['command'],
        contains('/home/dev/.agents/vgv/plugins/vgv-wingspan/hooks/'),
      );
    });

    test('reports an event Gemini has no equivalent for', () {
      final result = translate(const GeminiTranslator(), [
        hookAsset(fs, event: 'Notification'),
      ]);

      expect(
        result.notes.single.reason,
        'Gemini has no equivalent lifecycle event',
      );
    });

    test('reports a non-command hook rather than running its text', () {
      final result = translate(const GeminiTranslator(), [
        hookAsset(
          fs,
          commands: const [
            HookCommand(type: 'prompt', command: 'Summarize the session.'),
          ],
        ),
      ]);

      expect(result.notes.single.reason, contains('prompt command'));
      expect(
        result.changes.where((c) => c.contents.contains('hooks')),
        isEmpty,
      );
    });
  });

  group('Codex hooks', () {
    test('keeps Claude event and tool names, which Codex shares', () {
      final result = translate(const CodexTranslator(), [
        hookAsset(fs, event: 'PreToolUse', matcher: 'Read|Bash'),
      ]);

      final hooks = jsonAt(result, 'hooks.json')['hooks'] as Map;
      final registration = (hooks['PreToolUse'] as List).single as Map;

      expect(registration['matcher'], 'Read|Bash');
    });

    test('passes a regex matcher through without a false rename note', () {
      // Codex uses Claude's tool names, so mapping through an identity table
      // would report every matcher the table forgot, this one included.
      final result = translate(const CodexTranslator(), [
        hookAsset(fs, matcher: 'mcp__.*very-good-cli__.*'),
      ]);

      final hooks = jsonAt(result, 'hooks.json')['hooks'] as Map;
      final registration = (hooks['PostToolUse'] as List).single as Map;

      expect(registration['matcher'], 'mcp__.*very-good-cli__.*');
      expect(result.notes, isEmpty);
    });

    test('writes them to hooks.json, leaving config.toml a single change', () {
      final result = translate(const CodexTranslator(), [hookAsset(fs)]);

      expect(
        result.changes.where((c) => c.file.path.endsWith('config.toml')),
        hasLength(1),
      );
      expect(
        result.changes.map((c) => c.file.path),
        contains('/home/dev/.codex/hooks.json'),
      );
    });

    test('keeps the timeout in seconds', () {
      final result = translate(const CodexTranslator(), [hookAsset(fs)]);

      final hooks = jsonAt(result, 'hooks.json')['hooks'] as Map;
      final registration = (hooks['PostToolUse'] as List).single as Map;
      final command = (registration['hooks'] as List).single as Map;

      expect(command['timeout'], 30);
    });

    test('omits the matcher when the hook declares none', () {
      final result = translate(const CodexTranslator(), [
        hookAsset(fs, event: 'SessionStart', matcher: null),
      ]);

      final hooks = jsonAt(result, 'hooks.json')['hooks'] as Map;
      final registration = (hooks['SessionStart'] as List).single as Map;

      expect(registration.containsKey('matcher'), isFalse);
    });

    test('plans no hooks file when nothing translated', () {
      final result = translate(const CodexTranslator(), []);

      expect(
        result.changes.map((c) => c.file.path),
        isNot(contains(endsWith('hooks.json'))),
      );
    });
  });

  group('OpenCode hooks', () {
    test('maps a post-edit hook onto file_edited', () {
      final result = translate(const OpenCodeTranslator(), [hookAsset(fs)]);

      final experimental =
          jsonAt(result, 'opencode.json')['experimental'] as Map;
      final hook = experimental['hook'] as Map;

      expect((hook['file_edited'] as Map).keys, ['*']);
    });

    test('reports a pre-tool hook, which config hooks cannot express', () {
      final result = translate(const OpenCodeTranslator(), [
        hookAsset(fs, event: 'PreToolUse'),
      ]);

      expect(
        result.notes.single.reason,
        contains('file_edited and session_completed'),
      );
    });

    test('reports the timeout it has to drop', () {
      final result = translate(const OpenCodeTranslator(), [hookAsset(fs)]);

      expect(
        result.notes.map((n) => n.reason),
        contains(contains('take no timeout')),
      );
    });

    test('reports a non-command hook', () {
      final result = translate(const OpenCodeTranslator(), [
        hookAsset(
          fs,
          commands: const [HookCommand(type: 'prompt', command: 'Summarize.')],
        ),
      ]);

      expect(result.notes.single.reason, contains('prompt command'));
    });
  });

  group('Pi hooks', () {
    test('translates none, and says why', () {
      final result = translate(const PiTranslator(), [hookAsset(fs)]);

      expect(result.notes.single.reason, contains('TypeScript'));
      expect(
        result.changes.every((c) => c.file.path.endsWith('settings.json')),
        isTrue,
      );
    });
  });

  group('Claude hooks', () {
    test('translates none, because the marketplace supplies them', () {
      final result = translate(const ClaudeTranslator(), [hookAsset(fs)]);

      expect(
        result.changes.single.file.path,
        endsWith('.claude/settings.json'),
      );
      expect(result.notes, isEmpty);
    });
  });

  group('MCP rewriting reaches every copy, not just the shared skills', () {
    // Pi has no MCP at all, so a per-harness copy still naming mcp__* would
    // hand it a tool it cannot invoke.
    PluginAssets withMcp() => pluginAssets(
      skills: [
        skillAsset(fs, 'green-gate', body: 'Run mcp__dart__analyze_files.\n'),
      ],
      agents: [
        agentAsset('reviewer', body: 'Call mcp__dart__analyze_files first.\n'),
      ],
    );

    for (final translator in translators) {
      test('${translator.harness.name} writes no raw mcp__ reference', () {
        final result = translator.translate(
          assets: withMcp(),
          home: home,
          staged: _staged,
        );

        for (final change in result.changes) {
          expect(
            change.contents,
            isNot(contains('mcp__')),
            reason: '${change.file.path} still names an MCP tool',
          );
        }
      });
    }
  });
}
