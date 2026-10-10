// 随机夸奖话术池测试（C49 / 玄参 2026-10-10）：
// 结算页原「家长留言区」占位框改随机系统夸奖卡；话术池口径锚点 ——
// 池非空、无重复、随机抽取必落池内（防止拿错下标 / 越界）。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/praise_phrases.dart';

void main() {
  group('kPraisePhrases 话术池', () {
    test('池非空（≥ 10 条，保证随机感）', () {
      expect(kPraisePhrases.length, greaterThanOrEqualTo(10));
    });

    test('无重复话术', () {
      expect(kPraisePhrases.toSet().length, kPraisePhrases.length);
    });

    test('每条都是非空短句（≤ 24 字，6-9 岁口径）', () {
      for (final String p in kPraisePhrases) {
        expect(p.trim(), isNotEmpty);
        expect(p.length, lessThanOrEqualTo(24), reason: '过长：$p');
      }
    });
  });

  group('randomPraisePhrase', () {
    test('抽取结果必落池内', () {
      final Random rng = Random(42);
      for (int i = 0; i < 50; i++) {
        expect(kPraisePhrases.contains(randomPraisePhrase(rng)), isTrue);
      }
    });

    test('传入同一 Random 种子结果可复现（便于测试注入）', () {
      expect(randomPraisePhrase(Random(7)), randomPraisePhrase(Random(7)));
    });
  });
}
