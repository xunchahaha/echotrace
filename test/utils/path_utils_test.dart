import 'dart:io';

import 'package:echotrace/utils/path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PathUtils.normalizeDatabasePath', () {
    test('handles Chinese chars', () {
      final path = r'D:\Documents\中文\EchoTrace\session.db';
      final normalized = PathUtils.normalizeDatabasePath(path);

      expect(normalized, contains('中文'));
      expect(normalized, contains('EchoTrace'));
      expect(normalized.startsWith('D:'), isTrue);
    });

    test('handles spaces', () {
      final path = r'D:\Documents\OneDrive - My Cloud Disk\EchoTrace\session.db';
      final normalized = PathUtils.normalizeDatabasePath(path);

      expect(normalized, contains('OneDrive - My Cloud Disk'));
      expect(normalized, contains('EchoTrace'));
    });

    test('handles Chinese + spaces', () {
      final path = r'D:\我的文档\OneDrive - 我的云盘\微信数据\session.db';
      final normalized = PathUtils.normalizeDatabasePath(path);

      expect(normalized, contains('我的文档'));
      expect(normalized, contains('我的云盘'));
      expect(normalized, contains('微信数据'));
    });

    test('normalizes separators', () {
      final path = r'D:/Documents/EchoTrace/session.db';
      final normalized = PathUtils.normalizeDatabasePath(path);

      if (Platform.isWindows) {
        expect(normalized, contains(r'\'));
        expect(normalized, isNot(contains('/')));
      }
    });

    test('removes long path prefix first', () {
      final path = r'\\?\D:\Documents\EchoTrace\session.db';
      final normalized = PathUtils.normalizeDatabasePath(path);

      expect(normalized.startsWith(r'\\?\'), isFalse);
      expect(normalized.startsWith('D:'), isTrue);
    });

    test('uppercases drive letter', () {
      final path = r'd:\documents\echotrace\session.db';
      final normalized = PathUtils.normalizeDatabasePath(path);

      expect(normalized.startsWith('D:'), isTrue);
    });
  });

  group('PathUtils.hasSpecialCharacters', () {
    test('detects Chinese', () {
      expect(PathUtils.hasSpecialCharacters(r'D:\文档\EchoTrace'), isTrue);
      expect(PathUtils.hasSpecialCharacters(r'D:\Documents\EchoTrace'), isFalse);
    });

    test('detects space', () {
      expect(PathUtils.hasSpecialCharacters(r'D:\My Documents\EchoTrace'), isTrue);
      expect(PathUtils.hasSpecialCharacters(r'D:\Documents\EchoTrace'), isFalse);
    });
  });

  group('PathUtils.join/basename/dirname/extension', () {
    test('join safely', () {
      final joined = PathUtils.join(r'D:\Documents', 'EchoTrace', 'session.db');
      expect(joined, contains('Documents'));
      expect(joined, contains('EchoTrace'));
      expect(joined, contains('session.db'));
    });

    test('join with Chinese', () {
      final joined = PathUtils.join(r'D:\文档', 'EchoTrace', 'session.db');
      expect(joined, contains('文档'));
      expect(joined, contains('EchoTrace'));
      expect(joined, contains('session.db'));
    });

    test('basename', () {
      final filename = PathUtils.basename(r'D:\Documents\EchoTrace\session.db');
      expect(filename, equals('session.db'));
    });

    test('dirname', () {
      final dir = PathUtils.dirname(r'D:\Documents\EchoTrace\session.db');
      expect(dir, contains('EchoTrace'));
      expect(dir, isNot(contains('session.db')));
    });

    test('extension', () {
      final ext = PathUtils.extension(r'D:\Documents\EchoTrace\session.db');
      expect(ext, equals('.db'));
    });

    test('replaceExtension', () {
      final newPath = PathUtils.replaceExtension(
        r'D:\Documents\EchoTrace\image.dat',
        '.jpg',
      );
      expect(newPath, endsWith('.jpg'));
      expect(newPath, isNot(contains('.dat')));
    });
  });

  test('isDatabaseFile detects db/sqlite/sqlite3', () {
    expect(PathUtils.isDatabaseFile('session.db'), isTrue);
    expect(PathUtils.isDatabaseFile('data.sqlite'), isTrue);
    expect(PathUtils.isDatabaseFile('data.sqlite3'), isTrue);
    expect(PathUtils.isDatabaseFile('image.jpg'), isFalse);
  });

  test('escapeForLog escapes slashes/quotes/newlines', () {
    final escaped = PathUtils.escapeForLog('path\\with"quote\n');
    expect(escaped, contains(r'\\'));
    expect(escaped, contains(r'\"'));
    expect(escaped, contains(r'\n'));
  });
}
