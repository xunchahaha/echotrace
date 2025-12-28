import 'package:echotrace/models/analytics_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatStatistics computed properties', () {
    final stats = ChatStatistics(
      totalMessages: 10,
      textMessages: 6,
      imageMessages: 2,
      voiceMessages: 1,
      videoMessages: 1,
      otherMessages: 0,
      sentMessages: 4,
      receivedMessages: 6,
      firstMessageTime: DateTime(2024, 1, 1),
      lastMessageTime: DateTime(2024, 1, 3),
      activeDays: 2,
    );

    expect(stats.messageTypeDistribution['文本'], 6);
    expect(stats.sendReceiveRatio['发送'], 4);
    expect(stats.chatDurationDays, 3);
    expect(stats.averageMessagesPerDay, closeTo(10 / 3, 0.0001));

    final json = stats.toJson();
    expect(json['totalMessages'], 10);
  });
}
