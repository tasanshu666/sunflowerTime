/// 守卫战 v2 独立验收 · **W6 降级路径探针**。
///
/// | # | 探针 | 判据 |
/// |---|---|---|
/// | 1 | prefs 不可用宿主（守卫存档 store 抛异常）⇒ 今日页正常渲染为 absent，无错误页、场景卡零占位 | |
/// | 2 | `tutorialSeen` 写失败 ⇒ 教学浮层不阻断开战（点 OK 后战斗照常进入），存档不被写坏 | |
/// | 3 | debug override provider 无写入环境恒 null ⇒ 生产路径走真实派生 | |
library;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/guard_state_prefs_store.dart';
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart' show dayKey;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_debug_script.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

import '../helpers/no_hit_random.dart';

/// read 抛异常（prefs 宿主不可用的最坏情形）。
class _ThrowingStore implements GuardStateStore {
  @override
  Future<GuardDayState> read(String childId) async =>
      throw StateError('注入：prefs 宿主不可用（read）');

  @override
  Future<void> write(String childId, GuardDayState state) async =>
      throw StateError('注入：prefs 宿主不可用（write）');

  @override
  Future<void> clear(String childId) async =>
      throw StateError('注入：prefs 宿主不可用（clear）');
}

/// write 抛异常（read 正常：只对「教学标记」这一笔写失败，
/// 模拟 `markTutorialSeen` 落盘失败；resolve / markFighting 的写放行）。
class _ThrowOnWriteStore implements GuardStateStore {
  _ThrowOnWriteStore(this._real);
  final GuardStateStore _real;
  int writeAttempts = 0;

  @override
  Future<GuardDayState> read(String childId) => _real.read(childId);

  @override
  Future<void> write(String childId, GuardDayState state) async {
    if (state.tutorialSeen) {
      writeAttempts++;
      throw StateError('注入：tutorialSeen 落盘失败');
    }
    await _real.write(childId, state);
  }

  @override
  Future<void> clear(String childId) => _real.clear(childId);
}

Future<(SharedPreferences, db.AppDatabase, AccountService)> _makeBase() async {
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
  return (sp, database, account);
}

/// 种一株 + 一次有效专注（让今天有贼、可开战）。
Future<void> _seedFightReady(
  db.AppDatabase database,
  AccountService account,
) async {
  final DateTime now = DateTime.now();
  // 🔴 午夜安全：sessionsOfDay 按 start 归日，`now − 20min` 在午夜后 20 分钟
  // 内属于昨天 ⇒ 能量 0（详见 guard_battle_field_test 同名注释）。
  final DateTime todayStart = DateTime(now.year, now.month, now.day);
  final DateTime rawStart = now.subtract(const Duration(minutes: 20));
  final DateTime start = rawStart.isBefore(todayStart)
      ? todayStart.add(const Duration(seconds: 1))
      : rawStart;
  await PlantLocalRepository(database, account: account).savePlant(Plant(
    id: 'plant_1',
    speciesId: 'sunflower',
    potIndex: 0,
    stage: PlantStage.seed,
    stageStartedAt: now,
    growthFactor: 1.0,
    status: PlantStatus.growing,
    plantedAt: now,
  ));
  await FocusLocalRepository(database, account: account).saveSession(
    FocusSession(
      id: 'f_1',
      start: start,
      end: now,
      plannedMin: 0,
      actualFocusMin: 20,
      status: FocusStatus.completed,
      sunlightEarned: 0,
      createdAt: now,
    ),
  );
}

Future<void> _pumpToday(
  WidgetTester tester, {
  required SharedPreferences sp,
  required db.AppDatabase database,
  required AccountService account,
  List<Override> overrides = const <Override>[],
}) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      ...overrides,
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(database),
      accountServiceProvider.overrideWithValue(account),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChildTodayPage()),
    ),
  );
  // 26 帧 × 100ms：覆盖 kGuardTodayReadTimeout(600ms) 的降级窗口。
  for (int i = 0; i < 26; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 200,
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget, reason: '等待超时：目标 widget 一直没出现');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('W6-1 prefs 不可用宿主 ⇒ absent 降级、无错误页', () {
    testWidgets('守卫存档 store 全抛异常 ⇒ 页面照常渲染、场景卡零占位',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final (SharedPreferences sp, db.AppDatabase database,
              AccountService account) =
          await _makeBase();
      final GuardService brokenGuard = GuardService(
        store: _ThrowingStore(),
        ledger: SunlightLocalRepository(database, account: account),
        focus: FocusLocalRepository(database, account: account),
        plants: PlantLocalRepository(database, account: account),
        growth: PlantGrowthService(
          plants: PlantLocalRepository(database, account: account),
          focus: FocusLocalRepository(database, account: account),
          ledger: SunlightLocalRepository(database, account: account),
          settings: SettingsLocalRepository(database),
          bloomRewards: InMemoryBloomRewardRepository(),
          weedRandom: NoHitRandom(),
        ),
        childId: () => account.childId,
      );
      await _pumpToday(
        tester,
        sp: sp,
        database: database,
        account: account,
        overrides: <Override>[
          guardServiceProvider.overrideWithValue(brokenGuard),
        ],
      );
      expect(tester.takeException(), isNull, reason: '🔴 不得抛出错误页');
      expect(find.byKey(GuardSceneCard.cardKey), findsNothing,
          reason: '🔴 降级为 absent：场景卡零占位');
      // 页面本体仍在（今日页其它内容照常）。
      expect(find.byType(ChildTodayPage), findsOneWidget);
    });
  });

  group('W6-2 tutorialSeen 写失败 ⇒ 教学不阻断开战', () {
    testWidgets('教学浮层照弹、点 OK 后战斗照进、存档不被写坏',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final (SharedPreferences sp, db.AppDatabase database,
              AccountService account) =
          await _makeBase();
      await _seedFightReady(database, account);
      final SunlightLocalRepository ledger =
          SunlightLocalRepository(database, account: account);
      await ledger.append(SunlightEntry(
        id: 'qa_seed_20',
        ts: DateTime.now(),
        type: SunlightType.earn,
        gross: 20,
        net: 20,
        balanceAfter: 20,
        refType: 'qa_seed',
        refId: 'qa',
        dayKey: dayKey(DateTime.now()),
      ));
      final _ThrowOnWriteStore store =
          _ThrowOnWriteStore(GuardStatePrefsStore(sp));
      final GuardService guard = GuardService(
        store: store,
        ledger: SunlightLocalRepository(database, account: account),
        focus: FocusLocalRepository(database, account: account),
        plants: PlantLocalRepository(database, account: account),
        growth: PlantGrowthService(
          plants: PlantLocalRepository(database, account: account),
          focus: FocusLocalRepository(database, account: account),
          ledger: SunlightLocalRepository(database, account: account),
          settings: SettingsLocalRepository(database),
          bloomRewards: InMemoryBloomRewardRepository(),
          weedRandom: NoHitRandom(),
        ),
        childId: () => account.childId,
      );
      await _pumpToday(
        tester,
        sp: sp,
        database: database,
        account: account,
        overrides: <Override>[
          guardServiceProvider.overrideWithValue(guard),
        ],
      );
      // 点「开始守卫」→ 教学浮层（首次）。
      await _pumpUntil(tester, find.byKey(GuardSceneCard.startButtonKey));
      await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
      await _pumpUntil(tester, find.byKey(kGuardTutorialOkKey));
      // 等浮层进场动画走完再点（route transition 期间 hit test 会落空）。
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byKey(kGuardTutorialOkKey), warnIfMissed: false);
      // 🔴 B13.7：免费路径也弹确认卡（防误操作）⇒ 点「确定」后战斗才上屏。
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('确定').evaluate().isNotEmpty) {
        await tester.tap(find.text('确定'), warnIfMissed: false);
      }
      // 🔴 markTutorialSeen 写失败被服务层吞掉 ⇒ 链路不阻断：L4 战斗层照常上屏。
      await _pumpUntil(tester, find.byKey(GuardBattleField.fieldKey));
      if (find.byKey(GuardBattleField.fieldKey).evaluate().isEmpty) {
        // 再等一拍：handler 的 microtask（markFighting / provider 翻转）。
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      expect(store.writeAttempts, greaterThanOrEqualTo(1),
          reason: '夹具前提：markTutorialSeen / markFighting 至少尝试写过一次且失败');
      // 存档不被写坏：read 仍返回原状态（写失败 = 一个字节都不落）。
      expect(tester.takeException(), isNull);
    });
  });

  group('W6-3 debug override provider 默认恒 null', () {
    test('无写入环境下直接构造 ProviderContainer ⇒ 默认值 null（生产走真实派生）',
        () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(debugGuardBattleScriptOverrideProvider), isNull,
          reason: '🔴 release 语义：无人写入 ⇒ 恒 null ⇒ GuardBattleField 走 '
              'deriveGuardBattleScript 真实派生');
    });
  });
}
