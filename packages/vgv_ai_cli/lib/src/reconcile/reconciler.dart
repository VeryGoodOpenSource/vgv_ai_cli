import 'dart:convert';

import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/model/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/planned_change.dart';
import 'package:vgv_ai_cli/src/reconcile/applied_change.dart';
import 'package:vgv_ai_cli/src/reconcile/model/model.dart';

/// {@template reconciler}
/// Applies [PlannedChange]s to disk according to their [ChangeMode].
///
/// Without `force`, a merge never replaces a value the user set, a TOML
/// merge never re-serializes the user's file, and an owned file is never
/// written over a file VGV did not write or the user has since edited. What
/// VGV wrote before and the user left alone is VGV's, so it is updated
/// freely. With `dryRun`, nothing is written, but the outcomes are the same.
/// {@endtemplate}
class const Reconciler() {
  /// Applies every one of [changes] against [manifest], and returns what
  /// each did and the manifest updated with what they wrote.
  ///
  /// [manifest] is how this tells VGV's files and keys from the user's.
  /// Keeping it is the caller's job. A change that fails to read or write is
  /// reported as [ChangeOutcome.failed] and the rest still apply.
  Reconciliation apply(
    List<PlannedChange> changes, {
    required InstallManifest manifest,
    bool force = false,
    bool dryRun = false,
  }) {
    final run = _Run(force: force, dryRun: dryRun, manifest: manifest);
    return Reconciliation(
      changes: [for (final change in changes) run.guarded(change)],
      manifest: run.manifest,
    );
  }
}

/// One [Reconciler.apply] call's settings, and the manifest it updates.
class _Run {
  new({required this.force, required this.dryRun, required this.manifest});

  final bool force;
  final bool dryRun;

  /// What VGV has written, updated as each change lands.
  InstallManifest manifest;

  /// Applies [change], reporting a filesystem error rather than throwing it.
  AppliedChange guarded(PlannedChange change) {
    try {
      return _apply(change);
    } on FileSystemException catch (error) {
      return _failed(change, error);
    }
  }

  AppliedChange _apply(PlannedChange change) {
    final file = change.file;
    final existed = file.existsSync();
    final original = existed ? file.readAsBytesSync() : const <int>[];

    final WriteDecision(:bytes, :held, :entry) = switch (change.mode) {
      ChangeMode.own => _own(change, existed ? original : null),
      _ => _mergeText(change, original),
    };

    final changed = !bytesEquality.equals(bytes, original);
    if (changed && !dryRun) {
      writeAtomically(file, bytes, existed: existed, source: change.source);
    }
    manifest = switch (entry) {
      null => manifest,
      MergedDocument(contribution: Map(isEmpty: true)) => manifest.without([
        entry.path,
      ]),
      _ => manifest.record(entry),
    };

    return AppliedChange(
      change: change,
      outcome: switch ((changed, existed, held)) {
        (false, _, HeldBack.userValue) => ChangeOutcome.skipped,
        (false, _, HeldBack.unparseable) => ChangeOutcome.unparseable,
        (false, _, HeldBack.nothing) => ChangeOutcome.unchanged,
        (true, false, _) => ChangeOutcome.created,
        (true, true, HeldBack.nothing) => ChangeOutcome.updated,
        // Only a kept user value gets here: an unparseable file is returned
        // as it was, so it never changes.
        (true, true, _) => ChangeOutcome.partial,
      },
    );
  }

  /// Decides whether VGV may write its owned file over [original].
  ///
  /// It may when there is nothing there, when what is there already matches,
  /// when it is exactly what VGV last wrote, or when forced. Anything else is
  /// the user's.
  WriteDecision _own(PlannedChange change, List<int>? original) {
    final ours =
        original == null ||
        force ||
        bytesEquality.equals(original, change.bytes) ||
        (manifest.entryOf<OwnedFile>(change.file.path)?.isUntouched(original) ??
            false);
    if (!ours) return WriteDecision(bytes: original, held: HeldBack.userValue);

    return WriteDecision(
      bytes: change.bytes,
      held: HeldBack.nothing,
      entry: OwnedFile(
        path: change.file.path,
        owner: change.harness,
        sha256: hashBytes(change.bytes),
      ),
    );
  }

  /// Merges [change] into the text of [original] in its mode's format.
  WriteDecision _mergeText(PlannedChange change, List<int> original) {
    return switch ((decodeUtf8(original), change.mode.format)) {
      (null, _) => WriteDecision(bytes: original, held: HeldBack.unparseable),
      (final text?, final format?) => _mergeInto(format, change, text),
      (final text?, null) => _mergeSection(change, text, original),
    };
  }

  /// Writes [change]'s section into [text], the file's [original] contents.
  ///
  /// A section VGV recorded and the user has edited since is theirs, as it
  /// is on reverse, so it is kept unless forced.
  WriteDecision _mergeSection(
    PlannedChange change,
    String text,
    List<int> original,
  ) {
    final path = change.file.path;
    final recorded = manifest.entryOf<MarkdownSections>(path);
    final sections = recorded?.sections ?? const <String, String>{};
    // Only a markdown merge has no document format, and PlannedChange makes
    // every markdown merge name its section.
    final section = change.section!;
    final body = change.contents.trimRight();

    final edited = switch (sectionBody(text, section)) {
      final current? when sections.containsKey(section) =>
        current != body && !recorded!.isUntouched(section, current),
      _ => false,
    };
    if (edited && !force) {
      return WriteDecision(bytes: original, held: HeldBack.userValue);
    }

    return WriteDecision(
      bytes: utf8.encode(upsertSection(text, section, body)),
      held: HeldBack.nothing,
      entry: MarkdownSections(
        path: path,
        owner: change.harness,
        sections: {...sections, section: hashText(body)},
      ),
    );
  }

  /// Merges [change] into [text], a document in [format].
  WriteDecision _mergeInto(
    DocumentFormat format,
    PlannedChange change,
    String text,
  ) {
    final path = change.file.path;
    final merge = _mergeDocument(
      text,
      change.contents,
      format: format,
      managed:
          manifest.entryOf<MergedDocument>(path)?.contribution ??
          const <String, dynamic>{},
    );

    return WriteDecision(
      bytes: utf8.encode(merge.contents),
      held: merge.held,
      entry: switch (merge.contribution) {
        final contribution? => MergedDocument(
          path: path,
          owner: change.harness,
          format: format,
          contribution: contribution,
        ),
        null => null,
      },
    );
  }

  /// Merges [incoming] into [original], both documents in [format].
  ///
  /// [managed] is what VGV contributed last time. The merged document is
  /// kept as [original] when it cannot be written back without losing what
  /// the user wrote. The contribution returned is what of the written
  /// document is VGV's, and null when nothing could be parsed.
  TextMerge _mergeDocument(
    String original,
    String incoming, {
    required DocumentFormat format,
    required Map<String, dynamic> managed,
  }) {
    final addition = format.decode(incoming);
    if (addition == null) {
      return TextMerge(contents: original, held: HeldBack.unparseable);
    }

    if (original.trim().isEmpty) {
      return TextMerge(
        contents: format.encode(addition),
        held: HeldBack.nothing,
        contribution: addition,
      );
    }

    final existing = format.decode(original);
    if (existing == null) {
      return TextMerge(contents: original, held: HeldBack.unparseable);
    }

    final deepMerged = _deepMerge(existing, addition, managed);
    final merged = deepMerged.merged;
    final kept = contributionOf(existing, existing, managed);
    final held = deepMerged.declined ? HeldBack.userValue : HeldBack.nothing;

    if (deepEquality.equals(existing, merged)) {
      return TextMerge(contents: original, held: held, contribution: kept);
    }

    final rewritten = switch (format) {
      DocumentFormat.json => encodeJson(merged),
      DocumentFormat.toml => _rewriteToml(
        original,
        existing: existing,
        merge: deepMerged,
      ),
    };
    if (rewritten == null) {
      return TextMerge(
        contents: original,
        held: HeldBack.userValue,
        contribution: kept,
      );
    }

    return TextMerge(
      contents: rewritten,
      held: held,
      contribution: contributionOf(existing, merged, managed),
    );
  }

  /// Writes [merge] into [original] as TOML text, so the user's comments,
  /// layout and unrelated keys survive. Re-serializing drops every comment,
  /// so it happens only when forced and no edit in place works.
  String? _rewriteToml(
    String original, {
    required Map<String, dynamic> existing,
    required DeepMerge merge,
  }) {
    final edited = TomlText(original)
        .edit(existing: existing, merged: merge.merged, added: merge.added);
    return (edited ?? (force ? TomlText.encode(merge.merged) : null))?.source;
  }

  /// Merges [addition] into [base], where [managed] is what VGV contributed
  /// last time, and collects what the merge added: every key [base] lacks,
  /// and the entries a list gained.
  DeepMerge _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> addition,
    Map<String, dynamic> managed,
  ) {
    final result = Map<String, dynamic>.from(base);
    final added = <String, dynamic>{};
    var declined = false;

    for (final MapEntry(:key, :value) in addition.entries) {
      final existing = result[key];

      // A table is merged key by key even when VGV wrote all of it, so a
      // key a plugin stops writing stays until uninstall, whether or not
      // the user has added keys beside it.
      if (existing is Map && value is Map) {
        final mine = managed[key];
        final merged = _deepMerge(
          existing.cast<String, dynamic>(),
          value.cast<String, dynamic>(),
          mine is Map<String, dynamic> ? mine : const {},
        );
        result[key] = merged.merged;
        if (merged.added.isNotEmpty) added[key] = merged.added;
        declined = declined || merged.declined;
        continue;
      }

      if (!result.containsKey(key)) {
        result[key] = added[key] = value;
        continue;
      }

      // VGV's own and untouched since: VGV's to write.
      if (isManaged(managed, key, existing)) {
        result[key] = value;
        continue;
      }

      if (existing is List && value is List) {
        final gained = value.where((v) => !listContains(existing, v)).toList();
        result[key] = <dynamic>[...existing, ...gained];
        if (gained.isNotEmpty) added[key] = gained;
        continue;
      }

      if (force) {
        result[key] = value;
        continue;
      }

      declined = declined || existing != value;
    }

    return DeepMerge(merged: result, added: added, declined: declined);
  }
}

/// Reports [change] as failed with [error], rather than throwing it.
AppliedChange _failed(PlannedChange change, FileSystemException error) =>
    AppliedChange(
      change: change,
      outcome: ChangeOutcome.failed,
      error: describeError(error),
    );
