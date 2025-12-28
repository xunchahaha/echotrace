import 'dart:io';

import 'package:echotrace/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('connectDecryptedDatabase throws when file is missing', () async {
    final service = DatabaseService();
    await service.initialize(databaseFactory: databaseFactoryFfi);
    expect(
      () => service.connectDecryptedDatabase('C:\\no_such_file.db'),
      throwsException,
    );
  });

  test('initialize with in-memory sqlite does not throw', () async {
    final service = DatabaseService();
    await service.initialize(databaseFactory: databaseFactoryFfi);
    // 创建一个临时空数据库文件，再尝试连接，验证路径规范处理逻辑
    final tmpDir = await Directory.systemTemp.createTemp('db_service_test');
    final dbPath = '${tmpDir.path}${Platform.pathSeparator}session.db';
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    await db.close();

    await expectLater(
      service.connectDecryptedDatabase(dbPath, factory: databaseFactoryFfi),
      completes,
    );
    await service.close();
  });
}
