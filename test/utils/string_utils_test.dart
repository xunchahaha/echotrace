import 'package:echotrace/utils/string_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StringUtils.cleanUtf16', () {
    test('removes control chars and unpaired surrogate but keeps emoji pair', () {
      const input = 'A\u0000\u0007\uD83D\uDE0A\uD800B';
      final result = StringUtils.cleanUtf16(input);
      expect(result, 'A\uD83D\uDE0AB');
    });

    test('returns empty when input is empty', () {
      expect(StringUtils.cleanUtf16(''), isEmpty);
    });
  });

  group('StringUtils.getFirstChar', () {
    test('returns full emoji when first char is surrogate pair', () {
      final result = StringUtils.getFirstChar('\uD83D\uDE0AHello');
      expect(result, '\uD83D\uDE0A');
    });

    test('returns default when first code unit is invalid surrogate', () {
      final result = StringUtils.getFirstChar('\uDC00test', defaultChar: '?');
      expect(result, '?');
    });

    test('uppercases latin letters', () {
      expect(StringUtils.getFirstChar('abc'), 'A');
    });
  });

  group('StringUtils.cleanOrDefault', () {
    test('returns cleaned text when not empty', () {
      expect(StringUtils.cleanOrDefault(' hi ', 'N/A'), ' hi ');
    });

    test('returns default when cleaned result is empty', () {
      expect(StringUtils.cleanOrDefault('\u0000', 'fallback'), 'fallback');
    });
  });
}
