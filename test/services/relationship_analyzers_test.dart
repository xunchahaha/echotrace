import 'package:echotrace/services/former_friend_analyzer.dart';
import 'package:echotrace/services/response_time_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('former friend analyzer computes lost friends', () {
    final analyzer = FormerFriendAnalyzer();
    final lost = analyzer.analyzeFormerFriends(
      sentContacts: {'a', 'b', 'c'},
      receivedContacts: {'a', 'c'},
    );
    expect(lost, contains('b'));
  });

  test('response time analyzer average calculation', () {
    final analyzer = ResponseTimeAnalyzer();
    final durations = analyzer.calculateResponseTimes([
      ResponseRecord(
        senderIsMe: true,
        sendTime: DateTime(2024, 1, 1, 10, 0),
        replyTime: DateTime(2024, 1, 1, 10, 1),
      ),
      ResponseRecord(
        senderIsMe: false,
        sendTime: DateTime(2024, 1, 1, 11, 0),
        replyTime: DateTime(2024, 1, 1, 11, 3),
      ),
    ]);
    expect(durations.averageSeconds.round(), 150); // (60 + 180) / 2
  });
}
