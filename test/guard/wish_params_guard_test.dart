/// A7.2 numeric single-source guard (no duplicated literals or dead criteria).
library wish_params_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  final String params = _read('lib/core/constants/prd_params.dart');
  final String matrix = _read('lib/core/constants/entitlement_matrix.dart');

  test('6 个目标值区间常量的定稿数值', () {
    expect(kWishGoalFocusMinutesDefault, 30);
    expect(kWishGoalFocusMinutesMin, 10);
    expect(kWishGoalFocusMinutesMax, 600);
    expect(kWishGoalTaskCountDefault, 3);
    expect(kWishGoalTaskCountMin, 1);
    expect(kWishGoalTaskCountMax, 5);
  });

  test('2 个挂载位常量 + 2 个天花板常量', () {
    expect(kWishSlotBaseFree, 1);
    expect(kWishSlotPremiumMultiplier, 2);
    expect(kWishSlotMaxFree, 10);
    expect(kWishSlotMaxPremium, 20);
  });

  test('M1/M2 数值（里程碑步长 / 软门槛 / 文本长度双阈值）', () {
    expect(kWishPoolMilestoneStep, 3);
    expect(kWishSoftGateMinPlants, 1);
    expect(kWishTextMinLength, 2);
    // v0.3.0（R3-P0-04 / D1）：单阈值 30 作废，改双阈值（汉字 100 / 英文 300）。
    expect(kWishTextMaxLengthZh, 100);
    expect(kWishTextMaxLengthEn, 300);
    expect(kWishDuplicateLookbackDays, 30);
  });

  test('v0.3.0 字数上限单一取数函数（wishMaxTextLength）', () {
    // 唯一取数入口：zh（及任何非 en 语言）= 100，en = 300。
    expect(wishMaxTextLength('zh'), 100);
    expect(wishMaxTextLength('en'), 300);
    // 非 en 一律取 100（新增语言不会意外放宽到 300）。
    expect(wishMaxTextLength('ja'), kWishTextMaxLengthZh);
    expect(wishMaxTextLength(''), kWishTextMaxLengthZh);
    // 反向用例（R3-P1-02③）：错值必须能被断言拦住。
    expect(wishMaxTextLength('en'), isNot(100));
    expect(wishMaxTextLength('zh'), isNot(300));
  });

  test('触发方字面量只出现在 prd_params.dart', () {
    const List<String> literals = <String>['parentAction', 'progress', 'child'];
    final Directory lib = Directory('lib');
    final List<File> files = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) =>
            f.path.endsWith('.dart') &&
            (f.path.contains('wish') ||
                f.path.endsWith('tracking_event_names.dart')))
        .toList();
    for (final File f in files) {
      if (f.path.endsWith('prd_params.dart')) continue;
      final String src = _read(f.path);
      for (final String literal in literals) {
        expect(src.contains("'$literal'"), isFalse,
            reason: '${f.path} must reference kWishFulfillSource* constants');
      }
    }
  });

  test('禁止第二份 fulfill_source != child 计数口径', () {
    final Directory lib = Directory('lib');
    for (final File f in lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))) {
      final String src = _read(f.path);
      expect(src.contains("!= 'child'"), isFalse, reason: f.path);
      expect(src.contains("!= kWishFulfillSourceChild"), isFalse,
          reason: f.path);
    }
  });

  test('FeatureKey.wishSlot 已登记且天花板语义', () {
    final FeatureRule rule = kEntitlementMatrix[FeatureKey.wishSlot]!;
    expect(rule.freeQuota, kWishSlotMaxFree);
    expect(rule.premiumQuota, kWishSlotMaxPremium);
    expect(rule.freeEnabled, isTrue);
  });

  test('矩阵 const Map 不引用 const List.length', () {
    expect(matrix.contains('kFocusLevelTitleLevels.length'), isFalse);
  });

  test('等级节点字面量只在 prd_params 一处', () {
    expect(params.contains('const List<int> kFocusLevelTitleLevels'), isTrue);
    expect('[1, 5, 10, 15, 20, 25, 30, 35, 40]'.allMatches(params).length, 1);
  });

  test('FeatureKey 只新增 wishSlot 一个（无按日限条数 key）', () {
    expect(FeatureKey.values.length, 12);
    expect(FeatureKey.values.last, FeatureKey.wishSlot);
    expect(params.contains('kWishDaily'), isFalse);
  });
}
