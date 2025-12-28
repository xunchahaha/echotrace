import 'dart:io';

import 'package:echotrace/models/chat_session.dart';
import 'package:echotrace/models/message.dart';
import 'package:echotrace/services/chat_export_service.dart';
import 'package:echotrace/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  Future<String> _createContactDb() async {
    final dir = await Directory.systemTemp.createTemp('contact_db_test');
    final path = p.join(dir.path, 'contact.db');
    final db = await databaseFactoryFfi.openDatabase(
      path,
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
          await db.insert('contact', {
            'username': 'wxid_me',
            'nick_name': '我自己',
            'remark': '自己备注',
            'alias': 'me_alias',
          });
        },
      ),
    );
    await db.close();
    return path;
  }

  ChatSession _buildSession() {
    return ChatSession(
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
  }

  Message _buildMessage({
    required int localId,
    required String content,
    required String sender,
    required int isSend,
  }) {
    return Message.fromMap({
      'local_id': localId,
      'server_id': localId,
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
      'message_content': content,
      'compress_content': '',
      'packed_info_data': <int>[],
      'is_send': isSend,
      'sender_username': sender,
    }, myWxid: 'wxid_me');
  }

  test('exportToJson writes expected content', () async {
    final contactDbPath = await _createContactDb();
    final fakeDb = _FakeDatabaseService(
      contactDbPath: contactDbPath,
      displayNames: {
        'wxid_friend': '好友昵称',
        'wxid_me': '我自己',
      },
      currentWxid: 'wxid_me',
    );

    final exportService = ChatExportService(fakeDb);

    final session = _buildSession();
    final messages = [
      _buildMessage(localId: 1, content: 'hello', sender: 'wxid_friend', isSend: 0),
      _buildMessage(localId: 2, content: 'hi', sender: 'wxid_me', isSend: 1),
    ];

    final outDir = await Directory.systemTemp.createTemp('export_json_test');
    final outPath = p.join(outDir.path, 'out.json');

    final ok = await exportService.exportToJson(
      session,
      messages,
      filePath: outPath,
    );

    expect(ok, isTrue);
    final content = await File(outPath).readAsString();
    expect(content, contains('hello'));
    expect(content, contains('好友昵称'));
    expect(content, contains('wxid_friend'));
  });

  test('exportToHtml writes file', () async {
    final contactDbPath = await _createContactDb();
    final fakeDb = _FakeDatabaseService(
      contactDbPath: contactDbPath,
      displayNames: {
        'wxid_friend': '好友昵称',
        'wxid_me': '我自己',
      },
      currentWxid: 'wxid_me',
    );

    final exportService = ChatExportService(fakeDb);

    final session = _buildSession();
    final messages = [
      _buildMessage(localId: 1, content: 'hello', sender: 'wxid_friend', isSend: 0),
    ];

    final outDir = await Directory.systemTemp.createTemp('export_html_test');
    final outPath = p.join(outDir.path, 'out.html');

    final ok = await exportService.exportToHtml(
      session,
      messages,
      filePath: outPath,
    );

    expect(ok, isTrue);
    final content = await File(outPath).readAsString();
    expect(content, contains('<html'));
    expect(content, contains('hello'));
  });

  test('exportToExcel writes file', () async {
    final contactDbPath = await _createContactDb();
    final fakeDb = _FakeDatabaseService(
      contactDbPath: contactDbPath,
      displayNames: {
        'wxid_friend': '好友昵称',
        'wxid_me': '我自己',
      },
      currentWxid: 'wxid_me',
    );

    final exportService = ChatExportService(fakeDb);

    final session = _buildSession();
    final messages = [
      _buildMessage(localId: 1, content: 'hello', sender: 'wxid_friend', isSend: 0),
    ];

    final outDir = await Directory.systemTemp.createTemp('export_excel_test');
    final outPath = p.join(outDir.path, 'out.xlsx');

    final ok = await exportService.exportToExcel(
      session,
      messages,
      filePath: outPath,
    );

    expect(ok, isTrue);
    expect(File(outPath).existsSync(), isTrue);
    // 简单校验文件非空
    expect(File(outPath).lengthSync(), greaterThan(100));
  });
}
