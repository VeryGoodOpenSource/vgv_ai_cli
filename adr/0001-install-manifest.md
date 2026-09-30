# 1. Persist an install manifest as the ownership contract

- Status: accepted
- Date: 2026-09-28
- Issue: [#21](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/21)

## Context

`vgv_ai install` writes into files the user also owns. It writes whole files VGV owns, merges keys into the user's JSON and TOML settings, and writes named sections into markdown instruction files. `vgv_ai doctor` has to tell whether that work is still intact, and `vgv_ai uninstall` has to take it back without touching anything the user wrote.

Both need the same answer to one question: what did VGV write, where, for which harness, and how. If each command worked that out for itself, the two would drift apart and one of them would eventually delete something of the user's.

There were two ways to answer it:

1. **Recompute the plan.** Run the translator against the current plugins and treat whatever it would write as VGV's.
2. **Persist a manifest.** Record what install actually wrote, as it writes it, and read that back.

Recomputing fails in two ways that matter. A plan cannot tell a key VGV added from the same key the user already had, so uninstall would remove the user's own settings. A plan also only knows what the current plugins write. Anything an older plugin version wrote and the current one no longer plans would be left behind for good.

## Decision

Install persists a manifest at `~/.vgv_ai/manifest.json`, and the manifest is the ownership contract. `InstallManifest` in `lib/src/model/manifest/install_manifest.dart` defines it as a plain value. `ManifestStore` in `lib/src/manifest/manifest_store.dart` is the one place that reads and writes it, and `ManifestAuditor` beside it is the one place that verifies and reverses it. The reconciler takes the manifest and returns it with what it wrote, and `install` saves it through the store, so the reconciler never touches the manifest file. The rules both follow for what of a merged document is VGV's live in `lib/src/document/contribution.dart`. No command decides for itself what is VGV's.

The manifest answers ownership and the plan answers currency. Whether VGV's files match what the current plugins would write is still `doctor`'s question for the translator, and it is not stored.

### Format

```json
{
  "version": 1,
  "entries": [
    {"path": ".codex/prompts/plan.md", "owner": "codex", "mode": "own", "sha256": "…"},
    {"path": ".codex/config.toml", "owner": "codex", "mode": "mergeToml",
     "contribution": {"mcp_servers": {"dart": {"command": "dart", "args": ["mcp-server"]}}}},
    {"path": ".gemini/AGENTS.md", "owner": "gemini", "mode": "mergeMarkdown",
     "sections": {"instructions": "…"}},
    {"path": ".agents/skills/testing/SKILL.md", "owner": null, "mode": "own", "sha256": "…"}
  ]
}
```

`path` is relative to the home directory, so the manifest still works after the home directory moves. An entry whose path is absolute or leads out of home is skipped when the manifest is read, so a damaged manifest cannot point `uninstall` at a file outside home. `owner` is the harness a file configures, and null for the shared skills under `~/.agents/skills`. A malformed manifest loads as empty. An unrecorded file counts as the user's, which is the safe way to be wrong. A manifest that carries another `version` is never written over, since that would lose everything it records. Install reports it and applies nothing, and reversing reports it and reverses nothing.

`contribution` has the same shape as the document. It holds the keys VGV added, with the values it wrote, and the entries it appended to lists the user already had. Nothing the user wrote first is in it.

### Managed values

A value in the contribution that still equals what VGV recorded is VGV's. The next install replaces it freely, with no `--force`, so a plugin upgrade that changes an MCP server's `args` updates it in place. A value the user has changed since is theirs from then on. Install keeps it unless forced, and it drops out of the contribution. A document with nothing of VGV's left in its contribution drops out of the manifest. The same rule applies to owned files through their hash, and to markdown sections through the hash of each body.

A table is merged key by key even when VGV wrote all of it. A key a plugin stops writing therefore stays in the file and in the contribution until uninstall, whether or not the user has added keys beside it.

### Verify and reverse per mode

| Mode | Recorded | Verify | Reverse |
|---|---|---|---|
| `own` | SHA-256 of the file | `missing` if the file is gone, `drifted` if the hash differs | Delete it if the hash matches. An edited file is skipped unless forced |
| `mergeJson` | The contribution | Each key path that is gone is `missing`, and each changed value is `drifted` | Remove each contributed key that still holds VGV's value, and each list entry VGV appended. Prune the maps that leaves empty. Delete a document with nothing left |
| `mergeToml` | The contribution | Same as JSON | Same as JSON, done as text edits so comments survive. If an edit cannot be made in place, the file is skipped unless forced, because re-serializing drops comments |
| `mergeMarkdown` | SHA-256 of each named section's body | A section whose markers are gone is `missing`, and one whose body changed is `drifted` | Remove each section that still matches, and the blank line install put before it. An edited section is skipped unless forced. Delete a file with nothing left |

An entry that is fully reversed, or partly reversed with the rest now the user's, leaves the manifest. An entry that was skipped, could not be parsed or failed stays, so a later run can retry it. Once the manifest is empty it is deleted.

### How writes stay scoped

Markdown sections are wrapped in `<!-- vgv-ai-cli:NAME -->` and `<!-- /vgv-ai-cli:NAME -->`. Each section is rewritten on its own and the text around it is left alone. TOML is edited line by line with `upsertTomlKey`, `removeTomlKey` and `removeTomlTable`. Every edit is parsed back and checked against the intended document before it is kept. Writes and deletes both go through symlinks, so a config kept in a dotfiles repository is edited where it lives. A file left empty is deleted together with the link that points to it. Install is idempotent, and an end-to-end test proves it by comparing file hashes across two runs and across an install, reverse and install cycle.

## Consequences

- `doctor` and `uninstall` become thin commands over `ManifestAuditor.verify` and `ManifestAuditor.reverse`.
- A user scalar that `--force` replaced was not VGV's to begin with, so it is not recorded, and uninstall leaves VGV's value there. With no backups, the user's original value is gone once they force.
- A key the user had with an empty value, such as `"mcpServers": {}`, is indistinguishable from one VGV created. Reversal removes it once VGV's entries are gone.
- A TOML statement VGV rewrites, for example a list it grows, is written in the `toml` package's formatting, and a trailing comment on that one line is lost.
- Reversal leaves empty directories behind. Removing directories VGV created is left to `uninstall` (#23).
- A key a plugin stops writing stays in the user's file and in the manifest until uninstall. `doctor` can report these entries by comparing the manifest with the plan.
