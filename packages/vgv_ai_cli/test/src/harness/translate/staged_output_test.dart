import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/templates/templates.dart';

/// The brick renders each config path inside a per-harness mustache section,
/// e.g. `{{#claude}}claude/settings.json{{/claude}}`.
final _section = RegExp(r'\{\{[#/][a-z]+\}\}');

String _stripSections(String path) => path.replaceAll(_section, '');

void main() {
  final claimed = StagedFragment.values.map((f) => f.path).toSet();

  group('StagedFragment', () {
    final rendered = agentsBundle.files
        .map((f) => _stripSections(f.path))
        .toSet();

    test('every fragment names a path the brick actually renders', () {
      // Nothing ties the enum to the brick at compile time, so this is what
      // catches a rename in bricks/agents/__brick__ before a harness silently
      // gets no settings.
      expect(rendered, containsAll(claimed));
    });

    test('every config path the brick renders is claimed by a translator', () {
      // The instruction files are deliberately unclaimed: no harness lets VGV
      // own its AGENTS.md without clobbering what the user wrote, so nothing
      // plans them. Anything else unclaimed is a gap.
      const instructionFiles = {
        'codex/AGENTS.md',
        'gemini/AGENTS.md',
        'opencode/AGENTS.md',
        // A mustache partial the per-harness AGENTS.md files include, not a
        // file the brick renders on its own.
        '{{~ agents.md }}',
      };

      expect(rendered.difference(claimed), instructionFiles);
    });
  });
}
