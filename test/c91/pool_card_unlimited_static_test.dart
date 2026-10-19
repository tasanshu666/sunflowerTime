/// C91 二轮（玄参 iOS 模拟器反馈）：周池「不限」下进度横条一直闪烁 —— 回归守卫。
///
/// 根因：`WeeklyPoolCard` 在不限额（高年级，budget <= kWeeklyPoolBudgetUnlimited）
/// 分支渲染 `LinearProgressIndicator(value: null)` —— **不确定态 = 无限循环动画**
/// （AnimationController.repeat，逐帧重绘永不收敛）→ 真机表现为「进度条一直刷新」。
///
/// 守卫两条（任一被破坏即红）：
///  ① 不限额时**不得渲染进度条**（无分母无进度，整块不渲染）；
///  ② 不限额状态下连续 pump 后**不得再有未决帧**（`hasScheduledFrame == false`
///     = 无持续动画 / 无循环刷新；不确定态动画会永久排帧，此断言即红）。
///
/// 脚手架：假仓储（settings=高年级 → 预算派生「不限」）+ 真 `WeeklyPoolService`，
/// 无平台通道。参照 `test/qa/phase4_gating_test.dart` 的周池 Fake。
library pool_card_unlimited_static_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:sunflower_time/presentation/parent/widgets/pool_indicator.dart';

class _FakeWeeklyPoolRepository implements WeeklyPoolRepository {
  WeeklyPool? _row;

  @override
  Future<WeeklyPool?> get(String weekKey) async => _row;

  @override
  Future<void> upsert(WeeklyPool pool) async => _row = pool;

  @override
  List<String> weeksBetween(String fromKey, String toKey) => <String>[];
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.high,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
      );

  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeTrackingRepository implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent event) async {}

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async =>
      <TrackingEvent>[];

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

void main() {
  testWidgets('不限额（高年级）：显示「不限」+ 已用数，不渲染进度条、无持续动画',
      (tester) async {
    final _FakeWeeklyPoolRepository poolRepo = _FakeWeeklyPoolRepository();
    final WeeklyPoolService service = WeeklyPoolService(
      poolRepo,
      _FakeSettingsRepository(),
      _FakeTrackingRepository(),
    );
    // 本周已有消耗（旧口径存量行 budget=400 也无妨：预算即时派生为「不限」）。
    final String week = weekKey(DateTime.now());
    await poolRepo.upsert(WeeklyPool(weekKey: week, budget: 400, used: 66));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          weeklyPoolServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: Scaffold(body: WeeklyPoolCard())),
      ),
    );
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ① 大字「不限」+ 不限额说明（C91 口径：只显示已用）。
    expect(find.text('不限'), findsOneWidget);
    expect(find.text('本周不限额，已用 66 阳光（兑换只受阳光余额约束）'),
        findsOneWidget);

    // ② 不限额时进度条整块不渲染（旧实现 value: null = 无限循环动画）。
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: '不限额无分母，不得渲染进度条（更不得是不确定态动画）');

    // ③ 连续 pump 后不得再有未决帧 —— 有任何持续动画 / 循环刷新此断言即红
    //   （真机「一直闪烁」的行为级等价守卫）。
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: '不限额状态下不得有任何持续动画 / 循环刷新（闪烁根因）');
  });

  testWidgets('限额（非高年级）：进度条照常渲染且为确定性（有 value、无持续动画）',
      (tester) async {
    final _FakeWeeklyPoolRepository poolRepo = _FakeWeeklyPoolRepository();
    final WeeklyPoolService service = WeeklyPoolService(
      poolRepo,
      _FakeSettingsLowTier(),
      _FakeTrackingRepository(),
    );
    final String week = weekKey(DateTime.now());
    await poolRepo.upsert(WeeklyPool(weekKey: week, budget: 300, used: 90));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          weeklyPoolServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: Scaffold(body: WeeklyPoolCard())),
      ),
    );
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 大字 = 派生预算（低年级 kPoolBudgetDefaultLow）。
    expect(find.text('$kPoolBudgetDefaultLow'), findsOneWidget);
    expect(find.text('已用 90 / 共 $kPoolBudgetDefaultLow 阳光'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // 确定性进度条不产生持续排帧。
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

/// 低年级（限额档）设置假仓储。
class _FakeSettingsLowTier implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
      );

  @override
  Future<void> saveSettings(AppSettings s) async {}
}
