import 'package:echotrace/services/image_decrypt_service.dart';
import 'package:echotrace/services/voice_message_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeImageDecryptService extends ImageDecryptService {
  @override
  Future<String?> decryptImage(
    String imagePath, {
    required String outputDir,
    required String? aesKey,
    required String? xorKey,
  }) async {
    if (imagePath.contains('bad')) return null;
    return '$outputDir/dec.png';
  }
}

class _FakeVoiceService extends VoiceMessageService {
  @override
  Future<String?> convertSilkToWav(
    String silkPath, {
    required String outputDir,
  }) async {
    if (silkPath.contains('bad')) return null;
    return '$outputDir/out.wav';
  }
}

void main() {
  test('image decrypt success/fail', () async {
    final svc = _FakeImageDecryptService();
    expect(
      await svc.decryptImage('image_good.dat', outputDir: '/tmp', aesKey: null, xorKey: null),
      '/tmp/dec.png',
    );
    expect(
      await svc.decryptImage('bad.dat', outputDir: '/tmp', aesKey: null, xorKey: null),
      isNull,
    );
  });

  test('voice convert success/fail', () async {
    final svc = _FakeVoiceService();
    expect(
      await svc.convertSilkToWav('voice.silk', outputDir: '/tmp'),
      '/tmp/out.wav',
    );
    expect(
      await svc.convertSilkToWav('bad.silk', outputDir: '/tmp'),
      isNull,
    );
  });
}
