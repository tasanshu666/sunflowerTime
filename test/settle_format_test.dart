// B25 修复回归测试：结算页专注时长格式化 `formatFocusMinutes`。
// [minutes] 单位为**分钟**，应先转成总秒数再拆「分 + 秒」，
// 避免把分钟当秒拆导致 1 分钟显示成「1 秒」。
import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';

void main() {
  group('formatFocusMinutes (B25 修复)', () {
    test('1.0 分钟 → "1 分钟"', () {
      expect(formatFocusMinutes(1.0), '1 分钟');
    });

    test('20.0 分钟 → "20 分钟"', () {
      expect(formatFocusMinutes(20.0), '20 分钟');
    });

    test('1.5 分钟 → "1 分 30 秒"', () {
      expect(formatFocusMinutes(1.5), '1 分 30 秒');
    });

    test('0.05 分钟 → "3 秒"', () {
      expect(formatFocusMinutes(0.05), '3 秒');
    });

    test('0 分钟 → "0 秒"', () {
      expect(formatFocusMinutes(0.0), '0 秒');
    });

    test('1.9 分钟 → "1 分 54 秒"', () {
      expect(formatFocusMinutes(1.9), '1 分 54 秒');
    });
  });
}
