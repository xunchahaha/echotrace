import 'package:echotrace/services/decrypt_service.dart';
import 'package:echotrace/services/decrypt_service_dart_backup.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDecrypt extends DecryptService {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> decryptDatabase(
    String dbPath,
    String key, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (key == 'bad') return false;
    return true;
  }
}

void main() {
  test('decrypt service base class throws by default', () async {
    final base = DecryptService();
    expect(
      () => base.decryptDatabase('db', 'k'),
      throwsA(isA<UnimplementedError>()),
    );
  });

  test('dart backup service accepts any key', () async {
    final svc = DecryptServiceDartBackup();
    await svc.initialize();
    expect(await svc.decryptDatabase('db', 'key'), isFalse,
        reason: 'without real DB should fail gracefully');
  });

  test('fake decrypt service success/fail by key', () async {
    final svc = _FakeDecrypt();
    expect(await svc.decryptDatabase('db', 'good'), isTrue);
    expect(await svc.decryptDatabase('db', 'bad'), isFalse);
  });
}
