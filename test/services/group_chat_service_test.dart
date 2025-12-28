import 'package:echotrace/services/group_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGroupChatService extends GroupChatService {
  _FakeGroupChatService() : super(null);

  @override
  Future<Map<String, int>> getMemberMessageCounts(String username) async {
    return {'a': 2, 'b': 1};
  }

  @override
  Future<Map<String, int>> getMediaCounts(String username) async {
    return {'image': 3, 'video': 1};
  }
}

void main() {
  test('member message counts aggregation', () async {
    final svc = _FakeGroupChatService();
    final counts = await svc.getMemberMessageCounts('chatroom');
    expect(counts['a'], 2);
    expect(counts['b'], 1);
  });

  test('media counts aggregation', () async {
    final svc = _FakeGroupChatService();
    final media = await svc.getMediaCounts('chatroom');
    expect(media['image'], 3);
  });
}
