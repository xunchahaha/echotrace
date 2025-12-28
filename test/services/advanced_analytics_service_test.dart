import 'package:echotrace/models/advanced_analytics_data.dart';
import 'package:echotrace/models/message.dart';
import 'package:echotrace/services/advanced_analytics_service.dart';
import 'package:echotrace/services/analytics_service.dart';
import 'package:echotrace/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDatabaseService extends DatabaseService {
  final Map<int, Map<int, int>> heatmap;
  final List<Message> messages;

  _FakeDatabaseService({required this.heatmap, required this.messages});

  @override
  Future<Map<int, Map<int, int>>> getActivityHeatmapData({int? year}) async {
    // 模拟按年过滤：如果指定年份则返回非空，否则返回空。
    return year == null ? heatmap : heatmap;
  }
}

class _FakeAnalyticsService extends AnalyticsService {
  final List<Message> messages;
  _FakeAnalyticsService(this.messages) : super(null);

  @override
  Future<List<Message>> getAllMessagesForSession(String username) async {
    return messages;
  }
}

Message _msg({
  required int ts,
  required int isSend,
  required int localType,
  String content = '',
}) {
  return Message.fromMap({
    'local_id': ts,
    'server_id': ts,
    'local_type': localType,
    'sort_seq': 0,
    'real_sender_id': 0,
    'create_time': ts,
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
    'sender_username': 'wxid_friend',
  }, myWxid: 'wxid_me');
}

void main() {
  test('analyzeActivityPattern returns normalized heatmap', () async {
    final fakeDb = _FakeDatabaseService(
      heatmap: {
        8: {1: 5},
        9: {1: 10},
      },
      messages: const [],
    );
    final svc = AdvancedAnalyticsService(
      fakeDb,
      analyticsService: _FakeAnalyticsService(const []),
    );
    final heatmap = await svc.analyzeActivityPattern();
    expect(heatmap.maxCount, 10);
    expect(heatmap.getCount(8, 1), 5);
  });

  test('generateIntimacyCalendar respects year filter', () async {
    final msgs = [
      _msg(ts: DateTime(2024, 1, 1).millisecondsSinceEpoch ~/ 1000, isSend: 1, localType: 1),
      _msg(ts: DateTime(2023, 12, 31).millisecondsSinceEpoch ~/ 1000, isSend: 1, localType: 1),
    ];
    final svc = AdvancedAnalyticsService(
      _FakeDatabaseService(heatmap: const {}, messages: msgs),
      analyticsService: _FakeAnalyticsService(msgs),
    );
    svc.setYearFilter(2024);
    final cal = await svc.generateIntimacyCalendar('wxid_friend');
    expect(cal.maxDailyCount, 1);
    expect(cal.dailyMessages.length, 1);
  });

  test('analyzeConversationBalance calculates ratios', () async {
    final msgs = [
      _msg(ts: 1, isSend: 1, localType: 1, content: 'hi'), // 我发
      _msg(ts: 2, isSend: 0, localType: 1, content: 'hello'), // 对方发
      _msg(ts: 3, isSend: 1, localType: 1, content: 'how are you'),
    ];

    final svc = AdvancedAnalyticsService(
      _FakeDatabaseService(heatmap: const {}, messages: msgs),
      analyticsService: _FakeAnalyticsService(msgs),
    );
    final balance = await svc.analyzeConversationBalance('wxid_friend');
    expect(balance.sentMessages, 2);
    expect(balance.receivedMessages, 1);
    expect(balance.sentWords, greaterThan(0));
  });
}
