/// 结算页随机夸奖话术本地化出口（B4，与 `species_lore_l10n.dart` 同构）。
///
/// ## 为什么存在
/// 迁移前 20 条夸奖话术硬编码中文在 `core/constants/praise_phrases.dart`
/// （C49 / 玄参 2026-10-10），唯一消费点 `settle_page.dart::_PraiseCard`。
/// 英文模式下结算页夸奖卡**仍是中文** —— i18n 残留。
///
/// 本文件把话术整体搬到 ARB（`praise_phrase_1..20`，共 20 条）：
///  · **zh 逐字节不变**：20 条 ARB zh 值与迁移前 `kPraisePhrases` 完全一致
///    （守卫见 `test/m3/praise_phrases_test.dart`）；
///  · **en 口语化新译**（玄参 2026-10-23「直接翻译就好，尽量口语化」）；
///  · **随机下标与取词解耦**：`randomPraiseIndex()` 只产出 0..19 的下标，
///    字符串在 build 时经 [praisePhraseAt] 取 —— 进结算页抽一次下标
///    （State 字段锁存），动画重建不换句、locale 内文案稳定。
///  · **单点真源**：`core/constants/praise_phrases.dart` 已整体删除，防止
///    「迁了 ARB 但 UI 仍读常量」的双真源假迁移。
library praise_l10n;

import 'dart:math';

import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 话术池条数（与 ARB `praise_phrase_1..20` 一一对应，守卫测试钉死）。
const int kPraisePhraseCount = 20;

/// 第 [index]（0-based）条夸奖话术；越界回退第 1 条（Random 保证不会发生）。
String praisePhraseAt(int index, AppLocalizations t) {
  switch (index) {
    case 0:
      return t.praise_phrase_1;
    case 1:
      return t.praise_phrase_2;
    case 2:
      return t.praise_phrase_3;
    case 3:
      return t.praise_phrase_4;
    case 4:
      return t.praise_phrase_5;
    case 5:
      return t.praise_phrase_6;
    case 6:
      return t.praise_phrase_7;
    case 7:
      return t.praise_phrase_8;
    case 8:
      return t.praise_phrase_9;
    case 9:
      return t.praise_phrase_10;
    case 10:
      return t.praise_phrase_11;
    case 11:
      return t.praise_phrase_12;
    case 12:
      return t.praise_phrase_13;
    case 13:
      return t.praise_phrase_14;
    case 14:
      return t.praise_phrase_15;
    case 15:
      return t.praise_phrase_16;
    case 16:
      return t.praise_phrase_17;
    case 17:
      return t.praise_phrase_18;
    case 18:
      return t.praise_phrase_19;
    case 19:
      return t.praise_phrase_20;
    default:
      return t.praise_phrase_1;
  }
}

/// 随机抽一条话术的下标（0-based）；可传入 [random] 便于测试注入。
int randomPraiseIndex([Random? random]) {
  final Random rng = random ?? Random();
  return rng.nextInt(kPraisePhraseCount);
}
