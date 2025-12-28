import 'package:echotrace/services/config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ConfigService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = ConfigService();
  });

  test('save/get decrypt key and database path', () async {
    await service.saveDecryptKey('k1');
    await service.saveDatabasePath('/data/db.sqlite');
    expect(await service.getDecryptKey(), 'k1');
    expect(await service.getDatabasePath(), '/data/db.sqlite');
  });

  test('config flags and modes with defaults', () async {
    expect(await service.isConfigured(), isFalse);
    expect(await service.getDatabaseMode(), 'backup');
    await service.setConfigured(true);
    await service.saveDatabaseMode('realtime');
    expect(await service.isConfigured(), isTrue);
    expect(await service.getDatabaseMode(), 'realtime');
  });

  test('image keys, manual wxid, debug/launch flags', () async {
    await service.saveImageXorKey('xor');
    await service.saveImageAesKey('aes');
    await service.saveManualWxid('wxid_abc');
    await service.saveDebugMode(true);
    await service.markLaunchStarted();
    await service.markLaunchSuccessful();
    expect(await service.getImageXorKey(), 'xor');
    expect(await service.getImageAesKey(), 'aes');
    expect(await service.getManualWxid(), 'wxid_abc');
    expect(await service.getDebugMode(), isTrue);
    expect(await service.wasLastLaunchInterrupted(), isFalse);
    await service.markLaunchCrashed();
    expect(await service.wasLastLaunchInterrupted(), isTrue);
  });

  test('clearAll removes stored values', () async {
    await service.saveDecryptKey('k');
    await service.saveDatabasePath('p');
    await service.clearAll();
    expect(await service.getDecryptKey(), isNull);
    expect(await service.getDatabasePath(), isNull);
    expect(await service.isConfigured(), isFalse);
  });
}
