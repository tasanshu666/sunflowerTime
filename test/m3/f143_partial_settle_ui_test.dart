/// F143（玄参 2026-10-20）：**联动成长项按专注时长比例结算** —— 表现层守卫。
///
/// 覆盖：
///  ① 结算页「提前结束 · 实际 X 分钟 · 完成度 Y% · 得 Z 阳光」逐字（zh）；
///  ② 部分完成同时被日上限截断 → 仍带截断说明（复用 `child_settle_task_capped`）；
///  ③ 英文环境同一条文案**无 CJK**（i18n 双向）；
///  ④ 孩子端任务卡：**部分完成**才多显示「实际 X 分钟 · 完成度 Y%」一行；
///     满额完成不显示（避免满额卡片多一行零信息噪音）。
///
/// ⚠️ 结算页序列帧是真实位图 → 拦截资产加载（与 settle_task_row_test 同纪律），
/// 有界 pump、禁 pumpAndSettle。
library f143_partial_settle_ui_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';

/// CJK 判定（与 `test/i18n/no_han_in_domain_test.dart` 同一字符类）。
final RegExp _cjk = RegExp(
  r'[\u3000-\u303F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]',
);

class _FakeSunlightRepository implements SunlightRepository {
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
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
  Future<int> countByRefType(String refType) async => 0;
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

FocusSettlement _settlement(double actualMin) => FocusSettlement(
      sessionId: 's-1',
      actualFocusMin: actualMin,
      rawS: actualMin,
      net: actualMin,
      balanceAfter: 106,
      todayNet: actualMin,
      plannedMin: 20,
      status: FocusStatus.completed,
      endReason: FocusEndReason.timedOut,
    );

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

Future<void> _pumpSettle(WidgetTester tester, SettleArgs args) async {
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

/// 部分完成的结算结果（20 分钟门槛、实际 10 分钟 → 应发 4 / 完成度 50%）。
const TaskCheckInOutcome _partialOutcome = TaskCheckInOutcome(
  checkInId: 'c-partial',
  reward: 4,
  granted: 4,
  cappedByDailyCap: false,
  perfectDayBonus: false,
  allTasksDone: false,
  status: CheckInStatus.verified,
  partial: true,
  completionPercent: 50,
);

Task _linkedTask(String id, String name, {int minFocusMin = 20}) => Task(
      id: id,
      name: name,
      subject: TaskSubject.general,
      requiresFocus: true,
      minFocusMin: minFocusMin,
      sunlightReward: Task.rewardCapFor(minFocusMin),
      isCustom: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppLocaleController.init(AppLanguage.system));

  group('F143 结算页', () {
    testWidgets('① 部分完成 → 「提前结束 · 实际 10 分钟 · 完成度 50% · 得 4 阳光」逐字',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      await _pumpSettle(
        tester,
        SettleArgs(
          settlement: _settlement(10),
          taskName: '完成学校作业',
          taskOutcome: _partialOutcome,
        ),
      );

      expect(
        find.text('提前结束 · 实际 10 分钟 · 完成度 50% · 得 4 阳光'),
        findsOneWidget,
        reason: 'partial 走新文案（含实际分钟 / 完成度 / 实到阳光）',
      );
      // 全额那句（「成长项「X」完成 +N ☀」）在这一分支**不得**出现（文案二选一）。
      expect(find.text('成长项「完成学校作业」完成 +4 ☀'), findsNothing);

      // 数据行仍按实发显示「任务奖励 +4 ☀️」（既有行不受影响）。
      expect(find.text('任务奖励'), findsOneWidget);
      expect(find.text('+4 ☀️'), findsOneWidget);
    });

    testWidgets('② 部分完成 + 日上限截断 → 仍带截断说明（复用 child_settle_task_capped）',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      await _pumpSettle(
        tester,
        SettleArgs(
          settlement: _settlement(10),
          taskName: '完成学校作业',
          taskOutcome: const TaskCheckInOutcome(
            checkInId: 'c-partial-cap',
            reward: 4,
            granted: 1,
            cappedByDailyCap: true,
            perfectDayBonus: false,
            allTasksDone: false,
            status: CheckInStatus.verified,
            partial: true,
            completionPercent: 50,
          ),
        ),
      );

      expect(find.text('提前结束 · 实际 10 分钟 · 完成度 50% · 得 1 阳光'),
          findsOneWidget);
      expect(find.text('（今日阳光已达上限，本次只到账 1 ☀）'), findsOneWidget,
          reason: '部分完成也要交代截断，不许只报 1 阳光不说原因');
    });

    testWidgets('③ 英文环境：同一句文案渲染为英文且**无 CJK**', (WidgetTester tester) async {
      AppLocaleController.init(AppLanguage.en);
      _usePhoneScreen(tester);
      await _pumpSettle(
        tester,
        SettleArgs(
          settlement: _settlement(10),
          taskName: 'Homework',
          taskOutcome: _partialOutcome,
        ),
      );

      expect(find.text('Ended early · 10 min · 50% done · +4 sunlight'),
          findsOneWidget);
      final Text found = tester.widget<Text>(
        find.text('Ended early · 10 min · 50% done · +4 sunlight'),
      );
      expect(_cjk.hasMatch(found.data!), isFalse,
          reason: '英文环境不许出现任何中文字符');
    });
  });

  group('F143 孩子端任务卡', () {
    testWidgets('④ 部分完成 → 卡片多一行「实际 10 分钟 · 完成度 50%」；满额不显示',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final AccountService account = AccountService(
        children: ChildProfileLocalRepository(database),
        settings: SettingsLocalRepository(database),
        prefs: sp,
      );
      await account.initialize();
      final TaskLocalRepository repo =
          TaskLocalRepository(database, account: account);

      final Task partialTask = _linkedTask('t_partial', '提前结束的朗读');
      final Task fullTask = _linkedTask('t_full', '全额完成的朗读');
      await repo.saveTask(partialTask);
      await repo.saveTask(fullTask);

      final DateTime now = DateTime.now();
      await repo.checkIn(CheckIn(
        id: 'c_partial',
        taskId: partialTask.id,
        date: now,
        completedAt: now,
        sessionId: 's_partial',
        isPerfectDay: false,
        status: CheckInStatus.verified,
        sunlightGross: 4,
        sunlightGranted: 4,
        actualFocusMin: 10,
      ));
      await repo.checkIn(CheckIn(
        id: 'c_full',
        taskId: fullTask.id,
        date: now,
        completedAt: now,
        sessionId: 's_full',
        isPerfectDay: false,
        status: CheckInStatus.verified,
        sunlightGross: 8,
        sunlightGranted: 8,
        actualFocusMin: 20,
      ));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: ProviderContainer(
            overrides: <Override>[
              sharedPreferencesProvider.overrideWithValue(sp),
              appDatabaseProvider.overrideWithValue(database),
              accountServiceProvider.overrideWithValue(account),
            ],
          ),
          child: const MaterialApp(home: ChildTaskPage()),
        ),
      );
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('实际 10 分钟 · 完成度 50%'), findsOneWidget,
          reason: '部分完成的任务卡必须标注实际分钟与完成度');
      expect(find.text('实际 20 分钟 · 完成度 100%'), findsNothing,
          reason: '满额完成不显示（零信息噪音），卡片与既往一致');
    });
  });
}
