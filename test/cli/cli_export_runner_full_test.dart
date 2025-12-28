import 'dart:io';

import 'package:echotrace/cli/cli_export_runner.dart';
import 'package:echotrace/models/chat_session.dart';
import 'package:echotrace/models/message.dart';
import 'package:echotrace/providers/app_state.dart';
import 'package:echotrace/services/chat_export_service.dart';
import 'package:echotrace/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAppState extends AppState {
  @override
  Future<void> initialize() async {
    // no-op
  }
}

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService(this.sessions, this.messages, {this.dbMode = DatabaseMode.decrypted});

  final List<ChatSession> sessions;
  final List<Message> messages;
  final DatabaseMode dbMode;

  @override
  bool get isConnected => true;

  @override
  DatabaseMode get mode => dbMode;

  @override
  Future<List<ChatSession>> getSessions({int? limit}) async => sessions;

  @override
  Future<List<Message>> getMessagesByDate(
    String sessionId,
    int startTimestamp,
    int endTimestamp,
  ) async {
    return messages
        .where((m) => m.createTime >= startTimestamp && m.createTime <= endTimestamp)
        .toList();
  }

  @override
  Future<int> getMessageCount(String sessionId) async => messages.length;

  @override
  Future<List<Message>> getMessages(
    String sessionId, {
    int limit = 1000,
    int offset = 0,
  }) async {
    final slice = messages.skip(offset).take(limit).toList();
    return slice;
  }
}

class _FakeExportService extends ChatExportService {
  _FakeExportService(DatabaseService db) : super(db);
  int jsonCalls = 0;
  int htmlCalls = 0;
  int excelCalls = 0;

  @override
  Future<bool> exportToJson(
    ChatSession session,
    List<Message> messages, {
    String? filePath,
    void Function(int, int, String)? onProgress,
  }) async {
    jsonCalls++;
    return true;
  }

  @override
  Future<bool> exportToHtml(
    ChatSession session,
    List<Message> messages, {
    String? filePath,
    void Function(int, int, String)? onProgress,
  }) async {
    htmlCalls++;
    return true;
  }

  @override
  Future<bool> exportToExcel(
    ChatSession session,
    List<Message> messages, {
    String? filePath,
    void Function(int, int, String)? onProgress,
  }) async {
    excelCalls++;
    return true;
  }
}

Message _buildMessage({
  required int localId,
  required int createTimeSeconds,
  required int isSend,
}) {
  return Message.fromMap({
    'local_id': localId,
    'server_id': localId,
    'local_type': 1,
    'sort_seq': 0,
    'real_sender_id': 0,
    'create_time': createTimeSeconds,
    'status': 0,
    'upload_status': 0,
    'download_status': 0,
    'server_seq': 0,
    'origin_source': 0,
    'source': '',
    'message_content': 'hi',
    'compress_content': '',
    'packed_info_data': <int>[],
    'is_send': isSend,
    'sender_username': 'wxid_friend',
  }, myWxid: 'wxid_me');
}

ChatSession _buildSession() => ChatSession(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cli runner exports with injected services', () async {
    final tmpDir = await Directory.systemTemp.createTemp('cli_full');
    final start = DateTime(2024, 1, 1);
    final end = DateTime(2024, 12, 31);
    final messages = [
      _buildMessage(localId: 1, createTimeSeconds: start.millisecondsSinceEpoch ~/ 1000, isSend: 1),
      _buildMessage(localId: 2, createTimeSeconds: end.millisecondsSinceEpoch ~/ 1000, isSend: 0),
    ];
    final fakeDb = _FakeDatabaseService([_buildSession()], messages);
    final fakeExport = _FakeExportService(fakeDb);

    final runner = CliExportRunner(
      appState: _FakeAppState(),
      databaseService: fakeDb,
      chatExportService: fakeExport,
    );

    final code = await runner.tryHandle([
      '-e',
      tmpDir.path,
      '--format',
      'json',
      '--start',
      '2024-01-01',
      '--end',
      '2024-12-31',
    ]);

    expect(code, 0);
    expect(fakeExport.jsonCalls, 1);
  });

  test('cli runner respects html/excel formats', () async {
    final tmpDir = await Directory.systemTemp.createTemp('cli_full_html');
    final messages = [
      _buildMessage(localId: 1, createTimeSeconds: 1704067200, isSend: 1), // 2024-01-01
    ];
    final fakeDb = _FakeDatabaseService([_buildSession()], messages);
    final fakeExport = _FakeExportService(fakeDb);
    final runner = CliExportRunner(
      appState: _FakeAppState(),
      databaseService: fakeDb,
      chatExportService: fakeExport,
    );

    final htmlCode = await runner.tryHandle(['-e', tmpDir.path, '--format', 'html']);
    final excelCode = await runner.tryHandle(['-e', tmpDir.path, '--format', 'excel']);

    expect(htmlCode, 0);
    expect(excelCode, 0);
    expect(fakeExport.htmlCalls, 1);
    expect(fakeExport.excelCalls, 1);
  });
}
