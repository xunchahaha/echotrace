import 'package:echotrace/models/analytics_data.dart';
import 'package:echotrace/services/analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAnalyticsService extends AnalyticsService {
  _FakeAnalyticsService() : super(null);

  @override
  Future<ChatStatistics> getChatStatistics(String username) async {
    return ChatStatistics(
      totalMessages: 4,
      textMessages: 2,
      imageMessages: 1,
      voiceMessages: 1,
      videoMessages: 0,
      otherMessages: 0,
      sentMessages: 1,
      receivedMessages: 3,
      firstMessageTime: DateTime(2024, 1, 1),
      lastMessageTime: DateTime(2024, 1, 2),
      activeDays: 2,
    );
  }
}

void main() {
  test('getChatStatistics returns expected aggregates', () async {
    final service = _FakeAnalyticsService();
    final stats = await service.getChatStatistics('wxid_friend');
    expect(stats.totalMessages, 4);
    expect(stats.textMessages, 2);
    expect(stats.imageMessages, 1);
    expect(stats.voiceMessages, 1);
    expect(stats.chatDurationDays, 2);
  });
}
