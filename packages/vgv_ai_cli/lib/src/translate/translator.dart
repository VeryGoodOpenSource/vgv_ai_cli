import 'package:collection/collection.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/agents_brick.dart';
import 'package:vgv_ai_cli/src/translate/agents_vars.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';
import 'package:vgv_ai_cli/src/translate/rendered_change.dart';
import 'package:vgv_ai_cli/src/translate/translators/translators.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template translator}
/// Plans every change that installs the plugins into the selected harnesses.
/// {@endtemplate}
class const Translator({
  /// The translator for each harness.
  final List<HarnessTranslator> translators = harnessTranslators,

  /// The brick that renders the harnesses' agent files.
  final AgentsBrick brick = const AgentsBrick(),

  /// The translator for the skills the harnesses share.
  final SkillsTranslator skills = const SkillsTranslator(),

  /// The translator that copies the plugin files a project install reads.
  final PluginFilesTranslator pluginFiles = const PluginFilesTranslator(),
}) {
  /// {@macro translator}
  this;

  /// The changes and notes for each of [selected] in [scope], plus the
  /// shared skills when any of them reads them.
  ///
  /// A project install configures no hooks yet, so it never asks for them.
  /// It copies the files [plugins] reference beside the skills instead,
  /// since the bodies read them from the project.
  Future<TranslationPlan> translate({
    required PluginAssets assets,
    required Scope scope,
    required Set<Harness> selected,
    List<PluginDirectory> plugins = const [],
  }) async {
    final chosen = [
      for (final translator in translators)
        if (selected.contains(translator.harness)) translator,
    ];
    final hooks = {
      for (final translator in chosen)
        translator.harness: switch (scope) {
          UserScope(:final root) => translator.hooks(
            assets,
            hooksRoot: translator.hooksRoot(root),
          ),
          ProjectScope() => null,
        },
    };
    final vars = AgentsVars(
      translators: chosen,
      assets: assets,
      scope: scope,
      hooks: {
        for (final MapEntry(key: harness, value: translation) in hooks.entries)
          harness: ?translation?.fragment,
      },
    );
    final rendered = await brick.render(vars.toMap(), scope: scope);
    final changes = [
      for (final MapEntry(key: path, value: contents) in rendered.entries)
        renderedChange(path, contents: contents, scope: scope),
    ].groupListsBy((change) => change.harness);

    return TranslationPlan(
      shared: _shared(chosen, assets: assets, scope: scope, plugins: plugins),
      harnesses: {
        for (final translator in chosen)
          translator.harness: _result(
            translator,
            rendered: changes[translator.harness],
            hooks: hooks[translator.harness],
            assets: assets,
            scope: scope,
          ),
      },
    );
  }

  /// The files no harness owns: the shared skills when any of [chosen] reads
  /// them, and in a project, the files [plugins] reference when any of
  /// [chosen] reads the bodies naming them. Null when there are none.
  TranslationResult? _shared(
    List<HarnessTranslator> chosen, {
    required PluginAssets assets,
    required Scope scope,
    required List<PluginDirectory> plugins,
  }) {
    final shared =
        chosen.any((translator) => translator.readsSharedSkills(scope))
        ? skills.translate(assets: assets, root: scope.skillsRoot, scope: scope)
        : null;
    final copies = switch (scope) {
      final ProjectScope project
          when chosen.any((t) => !t.installsPluginsNatively) =>
        pluginFiles.translate(plugins: plugins, scope: project),
      _ => null,
    };
    if (shared == null && copies == null) return null;
    return TranslationResult(
      changes: [...?shared?.changes, ...?copies?.changes],
      notes: [...?shared?.notes, ...?copies?.notes],
    );
  }

  /// [translator]'s [rendered] files, the ones beside its [hooks], and its
  /// own copy of the skills when it keeps one, with its notes. What a
  /// harness misses is told here, since every translator would otherwise say
  /// it the same way.
  TranslationResult _result(
    HarnessTranslator translator, {
    required List<PlannedChange>? rendered,
    required HookTranslation? hooks,
    required PluginAssets assets,
    required Scope scope,
  }) {
    final own = switch (translator.skillsRoot(scope)) {
      final root? => skills.translate(
        assets: assets,
        root: root,
        scope: scope,
        harness: translator.harness,
      ),
      _ => null,
    };
    final shared = translator.readsSharedSkills(scope)
        ? translator.sharedSkillFiles(assets, root: scope.skillsRoot)
        : null;
    return TranslationResult(
      changes: [
        ...?rendered,
        ...?hooks?.files,
        ...?own?.changes,
        ...?shared?.changes,
      ],
      notes: [
        ...translator.notes(assets),
        if (scope is ProjectScope) ...translator.projectNotes(assets),
        ...?hooks?.notes,
        ...?own?.notes,
        ...?shared?.notes,
        ..._missedNotes(translator, hooks: hooks, assets: assets, scope: scope),
        if (!translator.honorsModelInvocation)
          ..._userOnlyNotes(translator.harness, assets),
      ],
    );
  }

  /// What [translator]'s harness will not get from [assets] in [scope]: the
  /// hooks its config cannot run, and in a project, until #140, the hooks it
  /// can and the MCP servers, unless it installs the plugins itself or its
  /// own notes already say why it gets none.
  List<TranslationNote> _missedNotes(
    HarnessTranslator translator, {
    required HookTranslation? hooks,
    required PluginAssets assets,
    required Scope scope,
  }) {
    final name = translator.harness.displayName;
    final runsNoHooks = TranslationNote(
      subject: '${assets.hooks.length} hook(s)',
      reason:
          'the plugins ship them as shell commands, and nothing in '
          "$name's config runs one",
    );
    return switch (scope) {
      UserScope() => [
        if (hooks == null && assets.hooks.isNotEmpty) runsNoHooks,
      ],
      ProjectScope() when translator.installsPluginsNatively => const [],
      ProjectScope() => _withoutOwnSubjects(translator, assets, [
        if (assets.hooks.isNotEmpty && translator.scripts == null)
          runsNoHooks
        else if (assets.hooks.isNotEmpty)
          TranslationNote(
            subject: '${assets.hooks.length} hook(s)',
            reason:
                'a project install does not configure $name hooks yet; '
                'see $_projectHooksAndMcpIssue',
          ),
        if (assets.mcpServers.isNotEmpty)
          TranslationNote(
            subject: '${assets.mcpServers.length} MCP server(s)',
            reason:
                'a project install does not configure $name MCP servers '
                'yet; see $_projectHooksAndMcpIssue',
          ),
      ]),
    };
  }

  /// [notes] without the ones whose subject [translator]'s own notes on
  /// [assets] already explain, such as Pi's MCP servers.
  List<TranslationNote> _withoutOwnSubjects(
    HarnessTranslator translator,
    PluginAssets assets,
    List<TranslationNote> notes,
  ) {
    final explained = {
      for (final note in translator.notes(assets)) note.subject,
    };
    return [
      for (final note in notes)
        if (!explained.contains(note.subject)) note,
    ];
  }

  /// The issue tracking hooks and MCP servers in a project install.
  static const _projectHooksAndMcpIssue =
      'https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/140';

  /// One note per skill only the user should start, for a [harness] whose
  /// model can start any skill it reads.
  List<TranslationNote> _userOnlyNotes(
    Harness harness,
    PluginAssets assets,
  ) => [
    for (final skill in assets.skills)
      if (skill.disableModelInvocation)
        TranslationNote(
          subject: 'the ${skill.name} skill',
          reason:
              'it is meant for the user alone, but nothing in '
              "${harness.displayName}'s config stops the model starting it, "
              'so it may start it on its own',
        ),
  ];
}
