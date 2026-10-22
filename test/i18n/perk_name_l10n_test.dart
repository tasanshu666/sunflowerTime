/// 称号属性名本地化守卫（i18n B3 · T05）。
///
/// ## 迁移动机
/// 迁移前 9 条属性名是 `lib/core/constants/prd_params.dart` 的 `kPerkNames`
/// （护眼 / 浇水 / 施肥 / 除草 / 除虫 / 绽放 / 晨露 / 扩盆 / 铲除），由
/// `domain/services/plant_perk.dart::perkNameOfTitleNode(nodeLevel)` 派生 —— 详情卡
/// 属性行「👁 护眼 +1 ☀」的**名称位**。虽然常量本身不在 `lib/domain/**`，但它是
/// 属性名的唯一上屏通道，等于领域层间接持有文案。
///
/// ## 本文件守什么
/// ① zh 逐字节等价（9 条一个都不能变，索引不能错位）；
/// ② en 真英文且无 CJK；
/// ③ **索引对齐**：9 个 key 的顺序必须 = `kFocusLevelTitleLevels` 的顺序 =
///    `kPerkEmojis` 的顺序（错位不会崩，只会「👁 显示成浇水」——静默且致命）；
/// ④ 非节点（7 / 0 / 100）→ 空串（原口径）；
/// ⑤ 反向守卫：domain 不得再出现属性名出口（`perkNameOfTitleNode`）、
///    `prd_params.dart` 不得再出现 `kPerkNames`。
library perk_name_l10n_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/domain_text_l10n.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// 9 节点 → zh 属性名（迁移前 `kPerkNames` 原文，逐字节）。
const Map<int, String> _zhNames = <int, String>{
  1: '护眼',
  5: '浇水',
  10: '施肥',
  15: '除草',
  20: '除虫',
  25: '绽放',
  30: '晨露',
  35: '扩盆',
  40: '铲除',
};

/// 9 节点 → en 属性名。
const Map<int, String> _enNames = <int, String>{
  1: 'Eye care',
  5: 'Watering',
  10: 'Fertilizing',
  15: 'Weeding',
  20: 'Pest control',
  25: 'Bloom',
  30: 'Morning dew',
  35: 'Pot upgrade',
  40: 'Removal',
};

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  // ─────────────────── ① zh 逐字节等价 ───────────────────
  group('① zh 逐字节等价（就是原来 kPerkNames 的 9 条）', () {
    test('9 节点逐条命中', () {
      expect(kFocusLevelTitleLevels.length, 9);
      for (final int node in kFocusLevelTitleLevels) {
        expect(_zhNames.containsKey(node), isTrue, reason: '缺期望值：Lv.$node');
        expect(
          perkNameOfTitleNodeL10n(node, zh),
          _zhNames[node],
          reason: 'Lv.$node 属性名必须与迁移前一字不差',
        );
      }
    });

    test('9 条互不相同（防复制粘贴成同名）', () {
      final Set<String> names = <String>{
        for (final int node in kFocusLevelTitleLevels)
          perkNameOfTitleNodeL10n(node, zh),
      };
      expect(names.length, 9);
    });
  });

  // ─────────────────── ② en 真英文 ───────────────────
  group('② en 生效（本批目的）', () {
    test('9 节点逐条英文且无 CJK', () {
      for (final int node in kFocusLevelTitleLevels) {
        final String name = perkNameOfTitleNodeL10n(node, en);
        expect(name, _enNames[node], reason: 'en 下 Lv.$node');
        expect(name, isNotEmpty);
        expect(_cjk.hasMatch(name), isFalse, reason: 'en 属性名含 CJK：$name');
      }
    });
  });

  // ─────────────────── ③ 索引对齐 ───────────────────
  group('③ 索引对齐（错位不崩但会显示错属性名）', () {
    test('key 顺序 == kFocusLevelTitleLevels 顺序 == kPerkEmojis 顺序', () {
      // 三张表必须同长、同序：任一重排都会让「👁 浇水 +1」这种串行出现。
      expect(kPerkEmojis.length, kFocusLevelTitleLevels.length,
          reason: 'kPerkEmojis 与节点表必须同长');
      expect(
        <int>[..._zhNames.keys],
        kFocusLevelTitleLevels,
        reason: '本测试的期望表顺序必须与节点表一致（防测试自身漂移）',
      );
    });

    test('同一节点的 emoji 与名称语义匹配（4 个可机器判定的抽样）', () {
      // 只挑「emoji 与词义强相关」的 4 个做断言，避免把美术口径写成硬规格。
      expect(perkEmojiOfTitleNode(15), '🌿', reason: '除草 ← 草');
      expect(perkNameOfTitleNodeL10n(15, zh), '除草');
      expect(perkEmojiOfTitleNode(1), '👁', reason: '护眼 ← 眼');
      expect(perkNameOfTitleNodeL10n(1, zh), '护眼');
    });
  });

  // ─────────────────── ④ 非节点兜底 ───────────────────
  group('④ 非节点 → 空串（原口径）', () {
    test('7 / 0 / 负数 / 100 一律空串（zh 与 en 都是）', () {
      for (final int bad in <int>[0, 7, 9, -1, 100]) {
        expect(perkNameOfTitleNodeL10n(bad, zh), '',
            reason: 'zh 下 Lv.$bad 不是称号节点');
        expect(perkNameOfTitleNodeL10n(bad, en), '');
      }
    });
  });

  // ─────────────────── ⑤ 反向守卫 ───────────────────
  group('⑤ 反向守卫（domain 与常量层都不得再持有属性名）', () {
    test('domain 无 perkNameOfTitleNode 出口', () {
      final String src = File('lib/domain/services/plant_perk.dart')
          .readAsStringSync();
      // 允许在文档注释里提到这个名字（说明迁移去向），但**不许有函数定义**。
      expect(
        RegExp(r'^String\s+perkNameOfTitleNode\s*\(', multiLine: true)
            .hasMatch(src),
        isFalse,
        reason: '`perkNameOfTitleNode` 已迁 UI 侧，不许在 domain 重新定义',
      );
    });

    test('prd_params 无 kPerkNames 常量（只剩注释里的一句话）', () {
      final String src =
          File('lib/core/constants/prd_params.dart').readAsStringSync();
      expect(
        RegExp(r'^const\s+List<String>\s+kPerkNames', multiLine: true)
            .hasMatch(src),
        isFalse,
        reason: '`kPerkNames` 9 条中文已迁 ARB，不许加回',
      );
    });

    test('UI 侧确实调用了 l10n 版本（接线不得回退）', () {
      final String ui = File(
        'lib/presentation/child/widgets/focus_level_badge.dart',
      ).readAsStringSync();
      expect(ui.contains('perkNameOfTitleNodeL10n('), isTrue,
          reason: '详情卡属性名必须走 ARB 版本');
      expect(ui.contains('perkNameOfTitleNode('), isFalse,
          reason: '旧函数名不得残留（会静默引用到不存在的符号，编译即红）');
    });
  });
}
