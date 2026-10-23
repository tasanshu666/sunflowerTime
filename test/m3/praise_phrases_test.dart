// 随机夸奖话术池测试（C49 / 玄参 2026-10-10；B4 i18n 迁移 2026-10-23）：
// 结算页原「家长留言区」占位框改随机系统夸奖卡；B4 把 20 条话术自
// `core/constants/praise_phrases.dart` 迁 ARB（`praise_phrase_1..20`，经
// `core/i18n/praise_l10n.dart` 取词）。本测试锚定：
//  · zh 逐字节不变（迁移等价性）；
//  · en 双语齐全（口语化英译，玄参 2026-10-23「直接翻译就好，尽量口语化」）；
//  · 随机下标必落池内、可复现（防止越界 / 拿错下标）。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/praise_l10n.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();
  final AppLocalizationsEn en = AppLocalizationsEn();

  // 迁移前 kPraisePhrases 原文（zh 逐字节不变锚点）。
  const List<String> kLegacyZh = <String>[
    '真棒！你又专注地完成了一段时光！',
    '太厉害了，向日葵为你开心！',
    '你的专注力又变强了一点点！',
    '坚持就是超能力，你做到了！',
    '今天也是闪闪发光的一天！',
    '了不起！离满罐阳光又近了一步！',
    '你认真起来的样子真好看！',
    '每一次专注，都让你更棒！',
    '向日葵说：谢谢你陪我一起努力！',
    '哇，你比昨天更专注了！',
    '小小的坚持，大大的成长！',
    '你是最棒的小太阳！',
    '完成得真好，给自己一个大大的赞吧！',
    '专注的时刻，就是你发光的时刻！',
    '又收获一份阳光，继续加油哦！',
    '又完成了一次专注挑战，真了不起！',
    '你的努力，向日葵都看在眼里啦！',
    '棒极了！明天也要一起加油呀！',
    '每一分专注，都会开出美丽的花！',
    '你专注的样子，比阳光还耀眼！',
  ];

  List<String> zhPool() =>
      List<String>.generate(kPraisePhraseCount, (int i) => praisePhraseAt(i, zh));
  List<String> enPool() =>
      List<String>.generate(kPraisePhraseCount, (int i) => praisePhraseAt(i, en));

  group('话术池（ARB praise_phrase_1..20）', () {
    test('常量条数 = 20，与 ARB key 一一对应', () {
      expect(kPraisePhraseCount, 20);
      expect(kPraisePhraseCount, kLegacyZh.length);
    });

    test('zh 迁移等价：20 条与旧 kPraisePhrases 逐字节一致', () {
      expect(zhPool(), kLegacyZh);
    });

    test('zh：无重复、每条非空短句（≤ 24 字，6-9 岁口径）', () {
      final List<String> pool = zhPool();
      expect(pool.toSet().length, pool.length);
      for (final String p in pool) {
        expect(p.trim(), isNotEmpty);
        expect(p.length, lessThanOrEqualTo(24), reason: '过长：$p');
      }
    });

    test('en：20 条齐全、无重复、非空', () {
      final List<String> pool = enPool();
      expect(pool.length, 20);
      expect(pool.toSet().length, pool.length);
      for (final String p in pool) {
        expect(p.trim(), isNotEmpty);
        // en 模式不得漏翻（出现 CJK 字符 = 中文回潮）。
        expect(p.contains(RegExp(r'[\u4e00-\u9fff]')), isFalse,
            reason: 'en 话术混入中文：$p');
      }
    });
  });

  group('randomPraiseIndex', () {
    test('抽取下标必落 [0, 20)，经 praisePhraseAt 必取到池内话术', () {
      final Random rng = Random(42);
      for (int i = 0; i < 50; i++) {
        final int idx = randomPraiseIndex(rng);
        expect(idx, inInclusiveRange(0, kPraisePhraseCount - 1));
        expect(praisePhraseAt(idx, zh), isIn(zhPool()));
      }
    });

    test('传入同一 Random 种子结果可复现（便于测试注入）', () {
      expect(randomPraiseIndex(Random(7)), randomPraiseIndex(Random(7)));
    });

    test('praisePhraseAt 越界兜底不崩（回退第 1 条）', () {
      expect(praisePhraseAt(-1, zh), zhPool()[0]);
      expect(praisePhraseAt(999, en), enPool()[0]);
    });
  });
}
