import 'package:echotrace/utils/xml_message_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XmlMessageParser.parseRevokeMessage', () {
    test('returns self revoke text when sender is myself', () {
      final result = XmlMessageParser.parseRevokeMessage(
        '<revokemsg></revokemsg>',
        'me',
        'me',
        'Me',
      );
      expect(result, contains('撤回'));
      expect(result, contains('你'));
    });

    test('returns sender display name when available', () {
      final result = XmlMessageParser.parseRevokeMessage(
        '<revokemsg></revokemsg>',
        'me',
        'friend_wxid',
        'Alice',
      );
      expect(result, contains('Alice'));
      expect(result, contains('撤回'));
    });
  });

  group('XmlMessageParser.parsePatMessageInfo', () {
    test('extracts template and wxids', () {
      const xml = '''
      <msg>
        <template>${r'${wxid_1}'} patted ${r'${wxid_2}'}</template>
      </msg>
      ''';
      final result = XmlMessageParser.parsePatMessageInfo(xml);
      expect(result, isNotNull);
      expect(result!['template'], contains('wxid_1'));
      expect(result['wxids'], containsAll(['wxid_1', 'wxid_2']));
    });
  });

  group('XmlMessageParser.renderPatMessage', () {
    test('replaces placeholders with display names', () {
      const template = r'${wxid_a} poked ${wxid_b}';
      final rendered = XmlMessageParser.renderPatMessage(template, {
        'wxid_a': 'Tom',
        'wxid_b': 'Jerry',
      });
      expect(rendered, 'Tom poked Jerry');
    });
  });

  group('XmlMessageParser.parseQuoteMessage', () {
    test('parses quoted text content and display name', () {
      const xml = '''
      <msg>
        <appmsg>
          <refermsg>
            <displayname>Alice</displayname>
            <content>Hello</content>
            <type>1</type>
          </refermsg>
        </appmsg>
      </msg>
      ''';
      final result = XmlMessageParser.parseQuoteMessage(xml);
      expect(result, isNotNull);
      expect(result!['displayName'], 'Alice');
      expect(result['content'], 'Hello');
    });

    test('returns null on malformed xml', () {
      final result = XmlMessageParser.parseQuoteMessage('<msg><bad></msg>');
      expect(result, isNull);
    });

    test('renders non-text types to friendly labels', () {
      const xml = '''
      <msg>
        <appmsg>
          <refermsg>
            <displayname>Bob</displayname>
            <content>ignored</content>
            <type>3</type>
          </refermsg>
        </appmsg>
      </msg>
      ''';
      final result = XmlMessageParser.parseQuoteMessage(xml);
      expect(result, isNotNull);
      expect(result!['content'], '[图片]');
    });
  });
}
