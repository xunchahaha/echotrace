import 'package:echotrace/models/chat_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromMap populates fields and cleans strings', () {
    final session = ChatSession.fromMap({
      'username': 'wxid_123',
      'type': 3,
      'unread_count': 5,
      'unread_first_msg_srv_id': 10,
      'is_hidden': 0,
      'summary': 'hello',
      'draft': ' draft ',
      'status': 1,
      'last_timestamp': 100,
      'sort_timestamp': 90,
      'last_clear_unread_timestamp': 50,
      'last_msg_local_id': 7,
      'last_msg_type': 1,
      'last_msg_sub_type': 0,
      'last_msg_sender': 'wxid_sender',
      'last_sender_display_name': 'Alice\u0000', // 控制字符应被清理
    });

    expect(session.username, 'wxid_123');
    expect(session.unreadCount, 5);
    expect(session.lastSenderDisplayName, 'Alice');
  });
}
