import 'dart:io';

import 'package:echotrace/utils/cpu_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logicalProcessors returns positive value', () {
    final count = CpuInfo.logicalProcessors;
    expect(count, greaterThan(0));

    // Windows下优先使用 WinAPI，非 Windows 则退回 Platform.numberOfProcessors
    if (!Platform.isWindows) {
      expect(count, equals(Platform.numberOfProcessors));
    }
  });
}
