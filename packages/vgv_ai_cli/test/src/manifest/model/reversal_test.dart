import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group('Reversal', () {
    const entry = OwnedFile(path: '/a', owner: null, sha256: 'hash');

    test('carries its entries and the manifest they left', () {
      const reversed = ReversedEntry.removed(entry);
      final manifest = InstallManifest();

      final reversal = Reversal(entries: const [reversed], manifest: manifest);

      expect(reversal.entries, [reversed]);
      expect(reversal.manifest, manifest);
    });
  });
}
