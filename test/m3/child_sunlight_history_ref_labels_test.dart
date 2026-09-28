/// 孩子端「阳光来源记录」页的 refType → 文案映射回归：（成株后循环玩法 Batch 1）。
///
/// 钉住两件事：
///  ① 开花瞬间奖励 / 第二段（花开回访）奖励的 **refType 常量字符串值**
///     （`'bloom_reward'` / `'bloom_reward_24h'`——后者为历史遗留值，已冻结不改）；
///  ② 「阳光来源记录」页对这两个 refType 有**专属中文文案**（不再落到兜底「其他」）。
///
/// 防回归意义：若有人改 refType 字符串值、或漏把这俩 key 加进 `_refLabels`，
/// 本测试必红（前者由常量断言捕获，后者由文案断言捕获）。
library child_sunlight_history_ref_labels_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/presentation/child/pages/child_sunlight_history_page.dart';

/// 仅 `all` / `balance` 有意义的假账本（其余方法返回中性值）。
class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository(this._entries);

  final List<SunlightEntry> _entries;

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(_entries);
  @override
  Future<double> balance() async => 99;
  @override
  Future<double> append(SunlightEntry entry) async => 0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
}

SunlightEntry _entry(String id, String? refType, double net) => SunlightEntry(
      id: id,
      ts: DateTime(2026, 9, 25, 8, 0),
      type: SunlightType.earn,
      gross: net,
      net: net,
      balanceAfter: net,
      refType: refType,
      dayKey: '2026-09-25',
    );

void main() {
  test('Batch1 开花奖励 refType 字符串值冻结（防改名分裂历史账本 tag）', () {
    expect(kBloomRewardRefType, 'bloom_reward');
    expect(kBloomSecondPhaseRefType, 'bloom_reward_24h');
  });

  testWidgets('开花奖励 / 花开回访奖励 在「阳光来源记录」显示专属文案（非「其他」）',
      (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository(
          <SunlightEntry>[
            _entry('e1', kBloomRewardRefType, 6), // 开花瞬间奖励
            _entry('e2', kBloomSecondPhaseRefType, 3), // 第二段（花开回访）奖励
            _entry('e3', 'something_unknown', 1), // 未知 refType → 兜底
          ],
        )),
      ],
      child: const MaterialApp(home: ChildSunlightHistoryPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('开花奖励'), findsOneWidget);
    expect(find.text('花开回访奖励'), findsOneWidget);
    // 未知 refType 仍安全兜底为「其他」。
    expect(find.text('其他'), findsOneWidget);
  });
}
