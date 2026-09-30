import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/presentation/child/pages/focus_page.dart';

/// 专注页「今日额度用完」轻提示的判定契约（玄参 2026-09-30）。
///
/// 判定抽成公开纯函数 `focusQuotaExhausted`（不依赖 widget），便于单测：
/// 它决定「什么时候弹那张左上角小卡」，正确性不能只靠真机肉眼。
void main() {
  group('focusQuotaExhausted · 额度用完判定', () {
    test('额度充足（已专注 5 分钟 / 剩余 30 分钟）→ 不提示', () {
      expect(
        focusQuotaExhausted(
          elapsed: const Duration(minutes: 5),
          remainingMin: 30,
        ),
        isFalse,
      );
    });

    test('差一点没用完（已专注 29 分钟 / 剩余 30 分钟）→ 不提示', () {
      expect(
        focusQuotaExhausted(
          elapsed: const Duration(minutes: 29),
          remainingMin: 30,
        ),
        isFalse,
      );
    });

    test('刚好用完（已专注 30 分钟 / 剩余 30 分钟）→ 提示', () {
      expect(
        focusQuotaExhausted(
          elapsed: const Duration(minutes: 30),
          remainingMin: 30,
        ),
        isTrue,
      );
    });

    test('已超出（已专注 35 分钟 / 剩余 30 分钟）→ 提示', () {
      expect(
        focusQuotaExhausted(
          elapsed: const Duration(minutes: 35),
          remainingMin: 30,
        ),
        isTrue,
      );
    });

    test('额度只剩零头（<1 分钟）→ 一进场即视为用完（与入口页同口径）', () {
      expect(
        focusQuotaExhausted(
          elapsed: Duration.zero,
          remainingMin: 0.5,
        ),
        isTrue,
      );
    });

    test('额度为 0 → 视为用完', () {
      expect(
        focusQuotaExhausted(elapsed: Duration.zero, remainingMin: 0),
        isTrue,
      );
    });
  });
}
