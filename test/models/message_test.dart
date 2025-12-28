import 'package:echotrace/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Message.fromMap', () {
    test('parses text message content', () {
      final msg = Message.fromMap({
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
      });

      expect(msg.displayContent, 'hello');
      expect(msg.isTextMessage, isTrue);
      expect(msg.isImageMessage, isFalse);
    });

    test('parses voice message duration from xml', () {
      final msg = Message.fromMap({
        'local_id': 2,
        'server_id': 2,
        'local_type': 34,
        'sort_seq': 0,
        'real_sender_id': 0,
        'create_time': 1,
        'status': 0,
        'upload_status': 0,
        'download_status': 0,
        'server_seq': 0,
        'origin_source': 0,
        'source': '',
        'message_content': '<msg><voicelength>3</voicelength></msg>',
        'compress_content': '',
        'packed_info_data': <int>[],
      });

      expect(msg.displayContent, '[语音 3秒]');
      expect(msg.voiceDurationSeconds, 3);
      expect(msg.isVoiceMessage, isTrue);
    });

    test('parses system revoke message with myWxid', () {
      final msg = Message.fromMap({
        'local_id': 3,
        'server_id': 3,
        'local_type': 10000,
        'sort_seq': 0,
        'real_sender_id': 0,
        'create_time': 1,
        'status': 0,
        'upload_status': 0,
        'download_status': 0,
        'server_seq': 0,
        'origin_source': 0,
        'source': '',
        'message_content': '<revokemsg><session><newmsgid>1</newmsgid></session></revokemsg>',
        'compress_content': '',
        'packed_info_data': <int>[],
        'sender_username': 'wxid_friend',
      }, myWxid: 'me');

      expect(msg.displayContent, contains('撤回'));
      expect(msg.isSystemMessage, isTrue);
    });

    test('parses quote message display content', () {
      final msg = Message.fromMap({
        'local_id': 4,
        'server_id': 4,
        'local_type': 244813135921,
        'sort_seq': 0,
        'real_sender_id': 0,
        'create_time': 1,
        'status': 0,
        'upload_status': 0,
        'download_status': 0,
        'server_seq': 0,
        'origin_source': 0,
        'source': '',
        'message_content': '''
<msg>
  <appmsg>
    <refermsg>
      <displayname>Alice</displayname>
      <content>Hello there</content>
      <type>1</type>
    </refermsg>
  </appmsg>
</msg>
''',
        'compress_content': '',
        'packed_info_data': <int>[],
      });

      expect(msg.displayContent, contains('Alice'));
      expect(msg.displayContent, contains('Hello there'));
      expect(msg.quotedContent, isNotEmpty);
    });
  });

  group('Message.fromMapLite', () {
    test('extracts image dat name from packed info data', () {
      final bytes = 'C:/wx/abcdef1234.t.dat'.codeUnits;
      final msg = Message.fromMapLite({
        'local_id': 3,
        'server_id': 3,
        'local_type': 3,
        'sort_seq': 0,
        'real_sender_id': 0,
        'create_time': 1,
        'status': 0,
        'upload_status': 0,
        'download_status': 0,
        'server_seq': 0,
        'origin_source': 0,
        'source': '',
        'packed_info_data': bytes,
      });

      expect(msg.imageDatName, 'abcdef1234');
      expect(msg.hasImage, isTrue);
    });
  });
}
