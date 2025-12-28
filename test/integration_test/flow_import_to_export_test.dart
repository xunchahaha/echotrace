import 'dart:io';

import 'package:echotrace/cli/cli_export_runner.dart';
import 'package:echotrace/models/chat_session.dart';
import 'package:echotrace/models/message.dart';
import 'package:echotrace/services/chat_export_service.dart';
import 'package:echotrace/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 集成流占位：使用临时 SQLite + 假数据跑“导出”链路，避免依赖真实微信数据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  test('fake flow: database -> export json via service', () async {
    // 构造临时联系人库
    final contactDir = await Directory.systemTemp.createTemp('it_contact_db');
    final contactPath = p.join(contactDir.path, 'contact.db');
    final contactDb = await databaseFactoryFfi.openDatabase(
      contactPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE contact(
              username TEXT PRIMARY KEY,
              nick_name TEXT,
              remark TEXT,
              alias TEXT
            );
          ''');
          await db.insert('contact', {
            'username': 'wxid_friend',
            'nick_name': '好友昵称',
            'remark': '好友备注',
            'alias': 'friend_alias',
          });
        },
      ),
    );
    await contactDb.close();

    // 伪造 DatabaseService，只实现联系人路径与显示名
    final fakeDb = _FakeDatabaseService(
      contactDbPath: contactPath,
      displayNames: {'wxid_friend': '好友昵称', 'wxid_me': '我自己'},
      currentWxid: 'wxid_me',
    );

    final exportService = ChatExportService(fakeDb);
    final session = ChatSession(
      username: 'wxid_friend',
      type: 1,
      unreadCount: 0,
      unreadFirstMsgSrvId: 0,
      isHidden: 0,
      summary: 'hi',
      draft: '',
      status: 0,
      lastTimestamp: 1,
      sortTimestamp: 1,
      lastClearUnreadTimestamp: 0,
      lastMsgLocalId: 1,
      lastMsgType: 1,
      lastMsgSubType: 0,
      lastMsgSender: 'wxid_friend',
      lastSenderDisplayName: '好友',
    );
    final messages = [
      Message.fromMap({
        'local_id': 1,
        'server_id': 1,
        'local_type': 1,
        'sort_seq': 0,
        'real_sender_id': 0,
        'create_time': 1,
        'status': 0,
        'upload_status': 0,
        'download_status': 0,
        'server_seq': 0,
        'origin_source': 0,
        'source': '',
        'message_content': 'hello',
        'compress_content': '',
        'packed_info_data': <int>[],
        'is_send': 0,
        'sender_username': 'wxid_friend',
      }, myWxid: 'wxid_me'),
    ];

    final outDir = await Directory.systemTemp.createTemp('it_export');
    final outPath = p.join(outDir.path, 'out.json');

    final ok = await exportService.exportToJson(session, messages, filePath: outPath);
    expect(ok, isTrue);
    expect(File(outPath).existsSync(), isTrue);
  });

  test('cli arg parse still works in integration layer', () async {
    final runner = CliExportRunner();
    final code = await runner.tryHandle(['-h']);
    expect(code, 0);
  });
}

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService({
    required this.contactDbPath,
    required this.displayNames,
    required this.currentWxid,
  });

  final String contactDbPath;
  final Map<String, String> displayNames;
  final String currentWxid;

  @override
  String? get currentAccountWxid => currentWxid;

  @override
  Future<Map<String, String>> getDisplayNames(List<String> usernames) async {
    final map = <String, String>{};
    for (final u in usernames) {
      map[u] = displayNames[u] ?? u;
    }
    return map;
  }

  @override
  Future<String?> getContactDatabasePath() async => contactDbPath;
}
