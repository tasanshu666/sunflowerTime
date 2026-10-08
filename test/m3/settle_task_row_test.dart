/// 结算页「任务奖励」数据行测试（F98，玄参 2026-10-08）。
///
/// 背景：联动成长项结算**后端早已入账**（check_in verified + 账本 task_checkin +6，
/// 2026-10-08 19:28 场真机库实证），但结算页只把任务奖励渲染成「拥有阳光」下方的
/// 金色小字 → 玄参反馈「只有专注奖励和护眼奖励，没有任务奖励」。修复 = 升级为与
/// 「护眼奖励」同级的 _StatRow：
///  ① verified → 「任务奖励 +6 ☀️」（N = 实际入账 granted）；
///  ② rejected → 「任务奖励 0 ☀️」（本次没达标）+ 下方灰字解释；
///  ③ 无联动项（taskOutcome == null）→ 不渲染该行（普通专注不出现空行）。
///
/// ⚠️ 结算页序列帧是真实位图 → 拦截资产加载（与 settle_eye_care_test 同纪律），
/// 有界 pump、禁 pumpAndSettle。
library settle_task_row_test;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';

class _FakeSunlightRepository implements SunlightRepository {
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<double> balance() async => 100;
  @override
  Future<double> append(SunlightEntry entry) async => 100;
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
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.high,
        dailyFocusCap: 60,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 400,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  const MethodChannel assets = MethodChannel('flutter/assets');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    assets,
    (MethodCall call) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(assets, null));
}

Future<void> _pump(WidgetTester tester, SettleArgs args) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      audioServiceProvider.overrideWithValue(
        AudioService(playerFactory: () => null),
      ),
    ],
    child: MaterialApp(home: SettlePage(args: args)),
  ));
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

FocusSettlement _settlement() => const FocusSettlement(
      sessionId: 's-1',
      actualFocusMin: 15.33,
      rawS: 15.33,
      net: 15.33,
      balanceAfter: 106,
      todayNet: 15.33,
      plannedMin: 15,
      status: FocusStatus.completed,
      endReason: FocusEndReason.timedOut,
    );

void main() {
  testWidgets('F98①：verified 任务 → 「任务奖励 +6 ☀️」数据行 + 金色说明行', (tester) async {
    _usePhoneScreen(tester);
    await _pump(
      tester,
      SettleArgs(
        settlement: _settlement(),
        taskName: '完成学校作业',
        taskOutcome: const TaskCheckInOutcome(
          checkInId: 'c-1',
          reward: 6,
          granted: 6,
          cappedByDailyCap: false,
          perfectDayBonus: false,
          allTasksDone: false,
          status: CheckInStatus.verified,
        ),
      ),
    );

    expect(find.text('任务奖励'), findsOneWidget);
    expect(find.text('+6 ☀️'), findsOneWidget);
    expect(
      find.text('成长项「完成学校作业」完成 +6 ☀'),
      findsOneWidget,
      reason: '金色说明行保留（带任务名）',
    );
  });

  testWidgets('F98②：rejected 任务 → 「任务奖励 0 ☀️」+ 灰字「还差一点」', (tester) async {
    _usePhoneScreen(tester);
    await _pump(
      tester,
      SettleArgs(
        settlement: _settlement(),
        taskName: '完成学校作业',
        taskOutcome: const TaskCheckInOutcome(
          checkInId: '',
          reward: 6,
          granted: 0,
          cappedByDailyCap: false,
          perfectDayBonus: false,
          allTasksDone: false,
          status: CheckInStatus.rejected,
        ),
      ),
    );

    expect(find.text('任务奖励'), findsOneWidget);
    // 「0 ☀️」与护眼奖励行（本例护眼=0）文案相同 → 只断言「至少 2 处」（护眼行 + 任务行）。
    expect(find.text('0 ☀️'), findsAtLeastNWidgets(2));
    expect(
      find.text('成长项「完成学校作业」还差一点，下次专注够时长就算上啦 🌻'),
      findsOneWidget,
    );
  });

  testWidgets('F98③：无联动项（taskOutcome == null）→ 不出现「任务奖励」行', (tester) async {
    _usePhoneScreen(tester);
    await _pump(
      tester,
      SettleArgs(settlement: _settlement()),
    );

    expect(find.text('任务奖励'), findsNothing);
    expect(find.text('护眼奖励'), findsOneWidget, reason: '既有护眼奖励行不受影响');
  });
}
