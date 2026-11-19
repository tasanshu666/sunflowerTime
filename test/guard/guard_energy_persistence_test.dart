/// 玄参 v0.3 验收反馈 3：守卫能量是**持久余额**，只消耗、不随天数消失。
///
/// 真实 GuardService + 真 prefs store + 内存库；覆盖 5 条口径：
/// ① 今天两次有效专注 ⇒ 余额 2；② 跨天仍 2；③ 跑过 expire() 仍 2；
/// ④ claim 消耗 1 ⇒ 余额 1；⑤ 同一 session 重复入账仍 2（幂等）。
library guard_energy_persistence_test;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/guard_energy_prefs_store.dart';
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/guard_energy.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String childId = 'single-child';
  final DateTime today = DateTime(2026, 11, 20, 10, 30);
  final DateTime nextDay = DateTime(2026, 11, 21, 0, 5);
  final String todayKey = dayKey(today);

  Future<({ProviderContainer container, GuardService guard, SharedPreferences sp})>
      boot() async {
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
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(database),
        accountServiceProvider.overrideWithValue(account),
        entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
      ],
    );
    addTearDown(container.dispose);
    return (
      container: container,
      guard: container.read(guardServiceProvider),
      sp: sp
    );
  }

  Future<void> seedFocus(
    ProviderContainer container, {
    required String id,
    required DateTime start,
  }) async {
    await container.read(focusRepositoryProvider).saveSession(
          FocusSession(
            id: id,
            start: start,
            end: start.add(const Duration(minutes: 25)),
            plannedMin: 0,
            actualFocusMin: 25,
            status: FocusStatus.completed,
            sunlightEarned: 0,
            createdAt: start,
          ),
        );
  }

  testWidgets('① 今天攒 2 → ② 跨天仍 2 → ③ expire 后仍 2 → ④ 消耗 1 → ⑤ 幂等',
      (WidgetTester tester) async {
    final ({ProviderContainer container, GuardService guard, SharedPreferences sp})
        env = await boot();
    final ProviderContainer container = env.container;
    final GuardService guard = env.guard;

    await seedFocus(container,
        id: 'f1', start: DateTime(2026, 11, 20, 8, 0));
    await seedFocus(container,
        id: 'f2', start: DateTime(2026, 11, 20, 9, 0));
    // ① 两笔有效专注各入账 1（会员上限 2）。
    expect(await guard.energyAvailable(now: today), 2,
        reason: '两次有效专注 ⇒ 余额 2');
    // ⑤ 同两笔会话重复读：幂等键是 focus session id（不是日期），
    //    跨天再回来也不得重复入账 / 互相覆盖。
    expect(await guard.energyAvailable(now: today), 2,
        reason: '同一 session 重复入账仍 2');
    expect(await guard.energyAvailable(now: nextDay), 2,
        reason: '跨天重复读也不重复入账');
    final GuardEnergyPrefsStore checkStore = GuardEnergyPrefsStore(env.sp);
    final GuardEnergy afterRepeat = await checkStore.read(childId);
    expect(afterRepeat.creditedSessionIds, <String>{'f1', 'f2'},
        reason: '入账账本按 session id 去重，恰好两条');
    expect(afterRepeat.creditedSessionIds.length, 2);

    // ② 跨天：余额不随天数归零。
    expect(await guard.energyAvailable(now: nextDay), 2,
        reason: '跨天后余额仍是 2');

    // ③ 跨天结算 clear 当日状态存档，不波及独立能量键。
    await guard.expire(now: nextDay);
    expect(await guard.energyAvailable(now: nextDay), 2,
        reason: 'expire() 后余额仍是 2');

    // ④ 真实 claim 消耗一发：先种一株、resolve 出贼、再 claim。
    await container.read(plantRepositoryProvider).savePlant(
          Plant(
            id: 'p1',
            speciesId: 'sunflower',
            potIndex: 0,
            stage: PlantStage.seed,
            stageStartedAt: today,
            growthFactor: 1.0,
            status: PlantStatus.growing,
            plantedAt: today,
          ),
        );
    await container.read(sunlightRepositoryProvider).append(SunlightEntry(
          id: 'seed_sun',
          ts: today,
          type: SunlightType.earn,
          gross: 30,
          net: 30,
          balanceAfter: 30,
          refType: 'seed',
          refId: 'seed',
          dayKey: todayKey,
        ));
    final GuardResolveResult resolved = await guard.resolve(now: today);
    expect(resolved.cost, GuardCostMode.free, reason: '有持久能量 ⇒ 免费');
    await guard.claim(now: today);

    expect(await guard.energyAvailable(now: today), 1,
        reason: 'claim 消耗 1 ⇒ 余额 1');
    final GuardEnergyPrefsStore store =
        GuardEnergyPrefsStore(env.sp);
    expect((await store.read(childId)).balance, 1,
        reason: '余额真的落在独立 prefs 键上');
  });
}
