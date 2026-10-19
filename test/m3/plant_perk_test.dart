/// C77 · **称号专属属性 · 纯函数单测**（`lib/domain/services/plant_perk.dart`）。
///
/// **C78 节点重排已同步**（护眼 → Lv.1，其余 8 条顺延一位；数值不变）。
///
/// 覆盖系统设计 §12.1 的 TC-01..TC-14：
///  · [perkOfLevel] 边界（未解锁 / 节点 / 非节点 / 满级）与**累积语义**；
///  · 9 条 perk-aware 取值函数（`waterCostOf` … `shovelRefundOf`）的定值；
///  · **零重复 P5**（每节点恰好一个字段非零 + 9 项绑定 9 个不同字段）；
///  · **免费 / 买断一致 P4**（签名无档位入参，同 level 同结果）。
///
/// 纯 Dart：零 I/O、零 Flutter，`dart test` / `flutter test` 均可直跑。
library plant_perk_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';

void main() {
  group('TC-01..05 perkOfLevel 边界与累积语义', () {
    test('TC-01 未解锁（level<1）→ isNone', () {
      expect(perkOfLevel(0).isNone, isTrue);
      expect(perkOfLevel(-3), PlantPerk.none);
    });

    test('TC-02 Lv.1 只解锁「护眼 +1」（C78 前置），其余 8 项为 0', () {
      final PlantPerk p = perkOfLevel(1);
      expect(p.eyeCareBonus, kPerkEyeCareBonus);
      expect(p.waterDiscount, 0);
      expect(p.fertilizeDiscount, 0);
      expect(p.weedBonus, 0);
      expect(p.pestBonus, 0);
      expect(p.bloomInstantBonus, 0);
      expect(p.dewBonus, 0);
      expect(p.expandDiscount, 0);
      expect(p.shovelRefundBonus, 0);
      expect(p.isNone, isFalse);
    });

    test('TC-03 非节点等级 Lv.4 → 取已解锁最高节点（Lv.1 护眼）', () {
      expect(perkOfLevel(4), perkOfLevel(1));
      expect(perkOfLevel(4).eyeCareBonus, kPerkEyeCareBonus);
    });

    test('TC-04 Lv.5 → 两节点各一条，**叠加**（护眼 +1 且 浇水 −1）', () {
      final PlantPerk p = perkOfLevel(5);
      expect(p.waterDiscount, kPerkWaterDiscount);
      expect(p.eyeCareBonus, kPerkEyeCareBonus);
      // 其余 7 项仍为 0（未到 Lv.10 节点）。
      expect(p.fertilizeDiscount, 0);
      expect(p.weedBonus, 0);
      expect(p.pestBonus, 0);
    });

    test('TC-05 Lv.40（满级）→ 9 项全非零且等于 9 条定值', () {
      final PlantPerk p = perkOfLevel(kFocusLevelMaxLevel);
      expect(p.isNone, isFalse);
      expect(p.waterDiscount, kPerkWaterDiscount);
      expect(p.fertilizeDiscount, kPerkFertilizeDiscount);
      expect(p.weedBonus, kPerkWeedBonus);
      expect(p.pestBonus, kPerkPestBonus);
      expect(p.bloomInstantBonus, kPerkBloomInstantBonus);
      expect(p.dewBonus, kPerkDewBonus);
      expect(p.eyeCareBonus, kPerkEyeCareBonus);
      expect(p.expandDiscount, kPerkExpandDiscount);
      expect(p.shovelRefundBonus, kPerkShovelRefundBonus);
    });

    test('单调不减：等级越高，累积属性只增不减', () {
      int prevTotal = 0;
      for (int lv = 1; lv <= kFocusLevelMaxLevel; lv++) {
        final PlantPerk p = perkOfLevel(lv);
        final int total = p.waterDiscount +
            p.fertilizeDiscount +
            p.weedBonus +
            p.pestBonus +
            p.bloomInstantBonus +
            p.dewBonus +
            p.eyeCareBonus +
            p.expandDiscount +
            p.shovelRefundBonus;
        expect(total, greaterThanOrEqualTo(prevTotal),
            reason: 'Lv.$lv 累积属性不得少于 Lv.${lv - 1}');
        prevTotal = total;
      }
    });
  });

  group('TC-06..11 perk-aware 取值函数定值', () {
    test('TC-06 waterCostOf(Lv.5) == 4（5 − 1）；未到浇水节点（Lv.1）则基础价', () {
      expect(waterCostOf(perkOfLevel(5)), kPlantWaterCost - 1);
      expect(waterCostOf(perkOfLevel(5)), 4);
      expect(waterCostOf(perkOfLevel(1)), kPlantWaterCost);
    });

    test('TC-07 fertilizeCostOf(Lv.10) == 9（10 − 1）', () {
      expect(fertilizeCostOf(perkOfLevel(10)), kPlantFertilizeCost - 1);
      expect(fertilizeCostOf(perkOfLevel(10)), 9);
    });

    test('TC-08 weedRewardOf(Lv.15) == 2 / pestRewardOf(Lv.20) == 3', () {
      expect(weedRewardOf(perkOfLevel(15)), kGardenWeedReward + 1);
      expect(weedRewardOf(perkOfLevel(15)), 2);
      expect(pestRewardOf(perkOfLevel(20)), kGardenPestReward + 1);
      expect(pestRewardOf(perkOfLevel(20)), 3);
    });

    test('TC-09 bloomInstantBaseOf(Lv.25) → 普通 8 / 精品 12（C91：绽放 +1 → +2）', () {
      expect(bloomInstantBaseOf(perkOfLevel(25), premium: false),
          kBloomInstantSunlight + 2);
      expect(bloomInstantBaseOf(perkOfLevel(25), premium: false), 8);
      expect(bloomInstantBaseOf(perkOfLevel(25), premium: true),
          kBloomInstantSunlightPremium + 2);
      expect(bloomInstantBaseOf(perkOfLevel(25), premium: true), 12);
    });

    test('TC-10 eyeCareRewardOf(Lv.1) == 3（C78 基础 2 + 1；C78 前置）', () {
      expect(eyeCareRewardOf(perkOfLevel(1)), kEyeCareRewardSunlight + 1);
      expect(eyeCareRewardOf(perkOfLevel(1)), 3);
    });

    test('TC-11 expandCostOf(Lv.35) → 精品 380 / 普通 140', () {
      expect(expandCostOf(perkOfLevel(35), premium: true),
          kPlantPotExpandCostHigh - kPerkExpandDiscount);
      expect(expandCostOf(perkOfLevel(35), premium: true), 380);
      expect(expandCostOf(perkOfLevel(35), premium: false),
          kPlantPotExpandCostLow - kPerkExpandDiscount);
      expect(expandCostOf(perkOfLevel(35), premium: false), 140);
    });

    test('无称号（Lv.0）→ 全部取值 = 基础值，逐位不变（回归）', () {
      final PlantPerk none = perkOfLevel(0);
      expect(waterCostOf(none), kPlantWaterCost);
      expect(fertilizeCostOf(none), kPlantFertilizeCost);
      expect(weedRewardOf(none), kGardenWeedReward);
      expect(pestRewardOf(none), kGardenPestReward);
      expect(bloomInstantBaseOf(none, premium: false), kBloomInstantSunlight);
      expect(bloomInstantBaseOf(none, premium: true),
          kBloomInstantSunlightPremium);
      expect(eyeCareRewardOf(none), kEyeCareRewardSunlight);
      expect(expandCostOf(none, premium: true), kPlantPotExpandCostHigh);
      expect(expandCostOf(none, premium: false), kPlantPotExpandCostLow);
    });

    test('钳制：减免/加成极端值不产生负价 / 不越界', () {
      expect(waterCostOf(const PlantPerk(waterDiscount: 999)), 0);
      expect(fertilizeCostOf(const PlantPerk(fertilizeDiscount: 999)), 0);
      expect(expandCostOf(const PlantPerk(expandDiscount: 999), premium: false),
          0);
    });
  });

  group('TC-12 shovelRefundOf 三态（基础额「种下时定」+ 加成「铲除时叠加」）', () {
    test('基础额 150/250 + Lv.40 加成 +20', () {
      expect(shovelRefundOf(150, perkOfLevel(40)), 170);
      expect(shovelRefundOf(250, perkOfLevel(40)), 270);
    });

    test('base == 0（免费首株）**不加成** → 0（防「免费种 → 铲」刷分）', () {
      expect(shovelRefundOf(0, perkOfLevel(40)), 0);
    });

    test('无称号（Lv.0）→ 基础额原样（C29 §2 逐位不变）', () {
      expect(shovelRefundOf(150, perkOfLevel(0)), 150);
      expect(shovelRefundOf(250, perkOfLevel(0)), 250);
      expect(shovelRefundOf(0, perkOfLevel(0)), 0);
    });

    test('Lv.39（未到 Lv.40）→ 无铲除加成', () {
      expect(shovelRefundOf(150, perkOfLevel(39)), 150);
    });
  });

  group('TC-13 零重复 P5（9 条属性绑定 9 个不同字段）', () {
    test('每项恰好一个字段非零，且 9 项落在 9 个不同字段上', () {
      expect(kPlantPerkPerTitleNode.length, kFocusLevelTitleLevels.length);
      expect(kPlantPerkPerTitleNode.length, 9);
      final Set<int> fieldIndices = <int>{};
      for (final PlantPerk p in kPlantPerkPerTitleNode) {
        final List<int> fields = <int>[
          p.waterDiscount,
          p.fertilizeDiscount,
          p.weedBonus,
          p.pestBonus,
          p.bloomInstantBonus,
          p.dewBonus,
          p.eyeCareBonus,
          p.expandDiscount,
          p.shovelRefundBonus,
        ];
        final int nonZero = fields.where((int v) => v != 0).length;
        expect(nonZero, 1, reason: '每节点属性必须恰好一个字段非零：$p');
        fieldIndices.add(fields.indexWhere((int v) => v != 0));
      }
      expect(fieldIndices.length, 9, reason: '9 条属性必须绑定 9 个不同字段（零重复）');
    });

    test('节点属性表逐项与该节点新增属性一致（perkOfTitleNode 索引对齐）', () {
      for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
        expect(perkOfTitleNode(kFocusLevelTitleLevels[i]),
            kPlantPerkPerTitleNode[i]);
      }
    });
  });

  group('TC-14 免费 / 买断一致 P4', () {
    test('perkOfLevel 无档位入参 → 同 level 同结果', () {
      for (final int lv in <int>[0, 1, 5, 12, 20, 35, 40]) {
        expect(perkOfLevel(lv), perkOfLevel(lv));
      }
    });
  });

  group('辅助：perkOfTitleNode / emoji / 文案单点', () {
    test('perkOfTitleNode 非节点 → none', () {
      expect(perkOfTitleNode(7), PlantPerk.none);
      expect(perkOfTitleNode(0), PlantPerk.none);
    });

    test('perkEmojiOfTitleNode 与节点一一对应，非节点 → 空串', () {
      expect(kPerkEmojis.length, kFocusLevelTitleLevels.length);
      for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
        expect(perkEmojiOfTitleNode(kFocusLevelTitleLevels[i]), kPerkEmojis[i]);
      }
      expect(perkEmojiOfTitleNode(7), '');
    });

    test('perkShortTextOf：C81 纯数值带符号（9 节点逐条）；none → 空串', () {
      expect(perkShortTextOf(PlantPerk.none), '');
      expect(perkShortTextOf(perkOfTitleNode(1)), '+1'); // ① 护眼
      expect(perkShortTextOf(perkOfTitleNode(5)), '−1'); // ② 浇水
      expect(perkShortTextOf(perkOfTitleNode(10)), '−1'); // ③ 施肥
      expect(perkShortTextOf(perkOfTitleNode(15)), '+1'); // ④ 除草
      expect(perkShortTextOf(perkOfTitleNode(20)), '+1'); // ⑤ 除虫
      expect(perkShortTextOf(perkOfTitleNode(25)), '+2'); // ⑥ 绽放（C91：+1 → +2）
      expect(perkShortTextOf(perkOfTitleNode(30)), '+2'); // ⑦ 晨露（C91：+1 → +2）
      expect(perkShortTextOf(perkOfTitleNode(35)), '−20'); // ⑧ 扩盆
      expect(perkShortTextOf(perkOfTitleNode(40)), '+20'); // ⑨ 铲除
      // 🔴 C81 ③：描述词（额外/消耗/返还）已全部去掉。
      for (final int lv in kFocusLevelTitleLevels) {
        final String t = perkShortTextOf(perkOfTitleNode(lv));
        expect(t, isNot(contains('额外')));
        expect(t, isNot(contains('消耗')));
        expect(t, isNot(contains('返还')));
      }
    });

    test('perkNameOfTitleNode：C81 属性名（9 节点逐条，与 emoji 同索引）；非节点空串', () {
      expect(kPerkNames.length, kFocusLevelTitleLevels.length);
      expect(perkNameOfTitleNode(1), '护眼');
      expect(perkNameOfTitleNode(5), '浇水');
      expect(perkNameOfTitleNode(10), '施肥');
      expect(perkNameOfTitleNode(15), '除草');
      expect(perkNameOfTitleNode(20), '除虫');
      expect(perkNameOfTitleNode(25), '绽放');
      expect(perkNameOfTitleNode(30), '晨露');
      expect(perkNameOfTitleNode(35), '扩盆');
      expect(perkNameOfTitleNode(40), '铲除');
      for (final int lv in kFocusLevelTitleLevels) {
        expect(perkNameOfTitleNode(lv), isNotEmpty);
      }
      expect(perkNameOfTitleNode(7), '');
      expect(perkNameOfTitleNode(0), '');
    });

    test('perkSummaryTextOf：none → 空串；Lv.1 含「护眼奖励 +1」（C78 前置）；满级 9 项齐全', () {
      expect(perkSummaryTextOf(PlantPerk.none), '');
      expect(perkSummaryTextOf(perkOfLevel(1)), contains('护眼奖励 +1'));
      expect(perkSummaryTextOf(perkOfLevel(5)), contains('浇水消耗 −1'));
      final String full = perkSummaryTextOf(perkOfLevel(40));
      for (final String frag in <String>[
        '浇水消耗 −1',
        '施肥消耗 −1',
        '除草奖励 +1',
        '除虫奖励 +1',
        '开花阳光 +2',
        '晨露阳光 +2',
        '护眼奖励 +1',
        '花盆扩容 −20',
        '铲除退款 +20',
      ]) {
        expect(full, contains(frag), reason: '满级摘要应含「$frag」');
      }
    });

    test('演出版式模板含占位符 {text}', () {
      expect(kLevelUpFxPerkTemplate, contains('{text}'));
    });
  });
}
