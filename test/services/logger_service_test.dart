import 'package:echotrace/services/logger_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enableIsolateMode marks logger as initialized without file IO', () {
    final logger = LoggerService();
    logger.enableIsolateMode();
    expect(logger.isInIsolateMode, isTrue);
  });
}
