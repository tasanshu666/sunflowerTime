/// 称号属性摘要文案守卫（i18n B3 · T02）。
///
/// 从 `test/m3/plant_perk_test.dart` 搬来（该文件是纯 Dart、不许拖 Flutter 依赖）：
/// 原 4 条 `perkSummaryTextOf` 文案断言现在针对 `perkSummaryTextL10n`。
///
/// 钉住三件事：
///  · `PlantPerk.none` → 空串（演出行据此决定是否显示）；
///  · 逐项只输出**非零**属性（C78 前置：Lv.1 只有「护眼奖励 +1」）；
///  · 满级 9 项齐全、` · ` 连接顺序固定 —— 文案与迁移前**逐字节一致**。
library perk_summary_l10n_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/domain_text_l10n.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

final RegExp _cjkRe = RegExp(r'[\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]');

void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();
  final AppLocalizationsEn en = AppLocalizationsEn();

  group('perkSummaryTextL10n（称号属性摘要）', () {
    test('none → 空串', () {
      expect(perkSummaryTextL10n(PlantPerk.none, zh), '');
      expect(perkSummaryTextL10n(PlantPerk.none, en), '');
    });

    test('Lv.1 只有「护眼奖励 +1」（C78 节点前置，逐项只输出非零项）', () {
      expect(perkSummaryTextL10n(perkOfLevel(1), zh), '护眼奖励 +1');
    });

    test('Lv.5 逐项累积：护眼 +1 且 浇水消耗 −1', () {
      expect(perkSummaryTextL10n(perkOfLevel(5), zh), '浇水消耗 −1 · 护眼奖励 +1');
    });

    test('满级（Lv.40）9 项齐全、顺序固定、` · ` 连接', () {
      const List<String> frags = <String>[
        '浇水消耗 −1',
        '施肥消耗 −1',
        '除草奖励 +1',
        '除虫奖励 +1',
        '开花阳光 +2',
        '晨露阳光 +2',
        '护眼奖励 +1',
        '花盆扩容 −20',
        '铲除退款 +20',
      ];
      final String full = perkSummaryTextL10n(perkOfLevel(40), zh);
      for (final String frag in frags) {
        expect(full, contains(frag), reason: '满级摘要应含「$frag」');
      }
      expect(full.split(' · ').length, 9, reason: '9 条属性、` · ` 连接');
      expect(full, frags.join(' · '), reason: '顺序必须与 9 条属性声明顺序一致');
    });

    test('en 同样逐项输出且不含 CJK（真翻译，非复制中文）', () {
      final String s = perkSummaryTextL10n(perkOfLevel(5), en);
      expect(s, 'Water cost −1 · Eye-care bonus +1');
      expect(_cjkRe.hasMatch(s), isFalse);
      final String full = perkSummaryTextL10n(perkOfLevel(40), en);
      expect(_cjkRe.hasMatch(full), isFalse);
      expect(full.split(' · ').length, 9);
    });
  });
}
