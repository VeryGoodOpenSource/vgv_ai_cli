import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/user_home.dart';

void main() {
  group('userHome', () {
    test('is HOME', () {
      expect(
        userHome(const {'HOME': '/Users/dev', 'USERPROFILE': 'other'})?.path,
        '/Users/dev',
      );
    });

    test('falls back to USERPROFILE', () {
      expect(
        userHome(const {'USERPROFILE': r'C:\Users\dev'})?.path,
        r'C:\Users\dev',
      );
    });

    test('is null when neither is set', () {
      expect(userHome(const {}), isNull);
    });
  });
}
