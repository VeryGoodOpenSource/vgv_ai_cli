import 'dart:convert';

import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/model/model.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template manifest_auditor}
/// Checks and takes back what an [InstallManifest] says VGV wrote.
///
/// `doctor` verifies with it and `uninstall` reverses with it, so neither
/// decides for itself what is VGV's. Reversing only removes what the
/// manifest proves VGV wrote and nobody has changed since, so the user's
/// files, keys and text survive. Forcing removes what VGV wrote even when
/// the user has changed it.
/// {@endtemplate}
class const ManifestAuditor({
  /// Decodes and compares what is on disk with what VGV recorded.
  final DocumentCodec codec = const DocumentCodec(),
}) {
  /// Checks that what [entry] records is still on disk, as VGV wrote it.
  ///
  /// Never writes, and reports a file it cannot read rather than throwing.
  /// Whether it is also what the current plugins would write is a question
  /// for the plan, not the manifest.
  EntryHealth verify(ManifestEntry entry, FileSystem fileSystem) {
    final file = fileSystem.file(entry.path);
    try {
      if (!file.existsSync()) return EntryHealth.missing(entry);

      final bytes = file.readAsBytesSync();
      return switch (entry) {
        OwnedFile() =>
          entry.isUntouched(bytes)
              ? EntryHealth.intact(entry)
              : EntryHealth.drifted(entry),
        MergedDocument() => _verifyDocument(entry, bytes),
        MarkdownSections() => _verifySections(entry, bytes),
      };
    } on FileSystemException catch (error) {
      return EntryHealth.unreadable(entry, error: error.description);
    }
  }

  /// Takes back every entry of [manifest] that [owners] holds, or every
  /// entry when [owners] is null, and returns what each did and the
  /// manifest without what was settled.
  ///
  /// [manifest] is how this tells VGV's files and keys from the user's.
  /// Keeping it is the caller's job. An entry that is fully taken back, or
  /// partly and the rest is the user's now, leaves the manifest. A markdown
  /// file partly taken back keeps a record of the sections the user
  /// edited, since an unrecorded section is VGV's to overwrite on the next
  /// install. An entry that was skipped, could not be parsed or failed
  /// stays, so a later run can try again. With [dryRun], nothing is
  /// written, but the outcomes and the manifest returned are the same.
  Reversal reverse(
    InstallManifest manifest,
    FileSystem fileSystem, {
    Set<Harness?>? owners,
    bool force = false,
    bool dryRun = false,
  }) {
    final reversed = [
      for (final entry in manifest.entries)
        if (owners?.contains(entry.owner) ?? true)
          _reverse(entry, fileSystem, force: force, dryRun: dryRun),
    ];
    final settled = [
      for (final ReversedEntry(:entry, :outcome, :retained) in reversed)
        if (_settled.contains(outcome) && retained == null) entry.path,
    ];
    final narrowed = [
      for (final ReversedEntry(:retained) in reversed) ?retained,
    ];
    return Reversal(
      entries: reversed,
      manifest: InstallManifest([
        ...manifest.without(settled).entries,
        ...narrowed,
      ]),
    );
  }

  /// The outcomes after which nothing of an entry is VGV's any more.
  static const Set<ReverseOutcome> _settled = {
    ReverseOutcome.removed,
    ReverseOutcome.partial,
    ReverseOutcome.missing,
  };

  EntryHealth _verifyDocument(MergedDocument entry, List<int> bytes) =>
      switch (_decode(entry.format, bytes)) {
        final current? => EntryHealth.of(
          entry,
          entry.contribution.compare(current),
        ),
        null => EntryHealth.unparseable(entry),
      };

  EntryHealth _verifySections(MarkdownSections entry, List<int> bytes) {
    final text = codec.decodeUtf8(bytes);
    if (text == null) return EntryHealth.unparseable(entry);
    final markdown = MarkdownText(text);

    final missing = <String>[];
    final drifted = <String>[];
    for (final name in entry.sections.keys) {
      final body = markdown.sectionBody(name);
      if (body == null) {
        missing.add(name);
      } else if (!entry.isUntouched(name, body)) {
        drifted.add(name);
      }
    }
    return EntryHealth.of(entry, Drift(missing: missing, drifted: drifted));
  }

  /// Takes back [entry], reporting a filesystem error rather than throwing.
  ReversedEntry _reverse(
    ManifestEntry entry,
    FileSystem fileSystem, {
    required bool force,
    required bool dryRun,
  }) {
    final file = fileSystem.file(entry.path);
    try {
      if (!file.existsSync()) return ReversedEntry.missing(entry);

      final original = file.readAsBytesSync();
      final decision = switch (entry) {
        OwnedFile() when entry.isUntouched(original) => const ReverseDecision(
          bytes: null,
          kept: false,
        ),
        OwnedFile() when force => const ReverseDecision(
          bytes: null,
          kept: false,
          throughLink: false,
        ),
        OwnedFile() => ReverseDecision(bytes: original, kept: true),
        MergedDocument() => _reverseDocument(entry, original, force: force),
        MarkdownSections() => _reverseSections(entry, original, force: force),
      };
      if (decision == null) return ReversedEntry.unparseable(entry);

      final ReverseDecision(:bytes, :kept, :retained, :throughLink) = decision;
      final changed =
          bytes == null || !codec.bytesEquality.equals(bytes, original);
      if (changed && !dryRun) {
        switch (bytes) {
          case null when throughLink:
            file.deleteThrough();
          case null:
            file.deleteHere();
          case final bytes:
            file.writeAtomically(bytes, existed: true);
        }
      }

      return switch ((changed, kept)) {
        (_, false) => ReversedEntry.removed(entry),
        (true, true) => ReversedEntry.partial(entry, retained: retained),
        (false, true) => ReversedEntry.skipped(entry),
      };
    } on FileSystemException catch (error) {
      return ReversedEntry.failed(entry, error: error.description);
    }
  }

  /// [original] without VGV's keys, or null when it cannot be parsed.
  ///
  /// A document with nothing left in it is deleted.
  ReverseDecision? _reverseDocument(
    MergedDocument entry,
    List<int> original, {
    required bool force,
  }) {
    final current = _decode(entry.format, original);
    if (current == null) return null;

    final Subtraction(:remaining, :kept) = entry.contribution.subtract(
      current,
      force: force,
    );
    if (codec.deepEquality.equals(remaining, current)) {
      return ReverseDecision(bytes: original, kept: kept);
    }

    final contents = switch (entry.format) {
      DocumentFormat.json =>
        remaining.isEmpty ? '' : DocumentFormat.json.encode(remaining),
      DocumentFormat.toml => _reverseToml(
        utf8.decode(original),
        from: current,
        to: remaining,
        force: force,
      ),
    };
    if (contents == null) return ReverseDecision(bytes: original, kept: true);

    return ReverseDecision(
      bytes: contents.trim().isEmpty ? null : utf8.encode(contents),
      kept: kept,
    );
  }

  /// [original] edited from [from] to [to] as TOML text, so the user's
  /// comments survive, or null when that cannot be done in place and is
  /// not forced.
  String? _reverseToml(
    String original, {
    required Map<String, dynamic> from,
    required Map<String, dynamic> to,
    required bool force,
  }) {
    final withdrawn = TomlText(original)
        .withdraw(existing: from, remaining: to);
    return (withdrawn ?? (force ? TomlText.encode(to) : null))?.source;
  }

  ReverseDecision? _reverseSections(
    MarkdownSections entry,
    List<int> original, {
    required bool force,
  }) {
    final text = codec.decodeUtf8(original);
    if (text == null) return null;

    var edited = MarkdownText(text);
    final kept = <String, String>{};
    for (final MapEntry(key: name, value: hash) in entry.sections.entries) {
      final body = edited.sectionBody(name);
      if (body == null) continue;

      if (force || entry.isUntouched(name, body)) {
        edited = edited.removeSection(name);
      } else {
        kept[name] = hash;
      }
    }
    return ReverseDecision(
      bytes: edited.source.trim().isEmpty ? null : utf8.encode(edited.source),
      kept: kept.isNotEmpty,
      retained: MarkdownSections(
        path: entry.path,
        owner: entry.owner,
        sections: kept,
      ),
    );
  }

  /// [bytes] decoded as [format], or null when they cannot be.
  Map<String, dynamic>? _decode(DocumentFormat format, List<int> bytes) =>
      switch (codec.decodeUtf8(bytes)) {
        final text? => format.decode(text),
        null => null,
      };
}
