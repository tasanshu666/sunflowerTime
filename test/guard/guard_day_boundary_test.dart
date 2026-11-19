/// 守卫专用 **6 点日界**护栏：纯函数 + 真 GuardService（真 DI / 真 prefs store）。
///
/// 00:00–05:59 仍属**前一守卫日**，06:00 起算新守卫日。天气 / 账本 / 专注 /
/// 任务仍按自然日 0 点，本文件只钉守卫这一条口径，防止串味。
library guard_day_boundary_test;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_day.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';

class _Env {
  _Env(this.container, this.database);

  final ProviderContainer container;
  final db.AppDatabase database;

  GuardService get guard => container.read(guardServiceProvider);
  String get childId => container.read(accountServiceProvider).childId;
}

Future<_Env> _boot() async {
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
    ],
  );
  addTearDown(container.dispose);
  return _Env(container, database);
}

void main() {
  group('① 纯函数 guardDayKey', () {
    test('05:59 归前一守卫日、06:00 起算当天', () {
      expect(
        guardDayKey(DateTime(2026, 11, 10, 5, 59)),
        '2026-11-09',
        reason: '午夜后不到 6 点仍算前一天',
      );
      expect(guardDayKey(DateTime(2026, 11, 10, 6, 0)), '2026-11-10');
      expect(guardDayKey(DateTime(2026, 11, 10, 0, 0)), '2026-11-09');
      expect(guardDayKey(DateTime(2026, 11, 10, 23, 59)), '2026-11-10');
      expect(guardDayKey(DateTime(2026, 1, 1, 3, 0)), '2025-12-31',
          reason: '跨年也要正确回退');
    });
  });

  group('② 真 GuardService：todayState / expire / resolve 跟随 6 点', () {
    final DateTime before = DateTime(2026, 11, 10, 5, 59);
    final DateTime after = DateTime(2026, 11, 10, 6, 0);

    Future<_Env> seedYesterdayState() async {
      final _Env env = await _boot();
      await env.container.read(guardStateStoreProvider).write(
            env.childId,
            const GuardDayState(
              dayKey: '2026-11-09',
              status: GuardDayStatus.pending,
              thiefKind: GuardThiefKind.sunRat,
              sunStolen: 3,
              winSun: 2,
            ),
          );
      return env;
    }

    test('05:59 仍看到昨天的守卫日状态；06:00 切到新一天', () async {
      final _Env env = await seedYesterdayState();
      final GuardDayState late = await env.guard.todayState(now: before);
      expect(late.dayKey, '2026-11-09');
      expect(late.hasThief, isTrue, reason: '05:59 昨天的贼仍在该守卫日');

      final GuardDayState early = await env.guard.todayState(now: after);
      expect(early.dayKey, '2026-11-10');
      expect(early.hasThief, isFalse, reason: '06:00 昨天的贼不许出现在新守卫日');
    });

    test('expire 在 05:59 空操作、06:00 才结算昨天', () async {
      final _Env env = await seedYesterdayState();
      expect((await env.guard.expire(now: before)).settled, isFalse,
          reason: '05:59 仍是同一守卫日，不能提前结算');
      final GuardExpireOutcome out = await env.guard.expire(now: after);
      expect(out.settled, isTrue);
      expect(out.expiredDayKey, '2026-11-09');
    });

    test('resolve 落盘日界：05:59 写 11-09，06:00 写 11-10', () async {
      final _Env env = await _boot();
      final GuardResolveResult late = await env.guard.resolve(now: before);
      expect(late.dayKey, '2026-11-09');

      // 同一个内存库，清掉状态再解析新守卫日（避免开两个 Drift 实例告警）。
      await env.container.read(guardStateStoreProvider).clear(env.childId);
      final GuardResolveResult early = await env.guard.resolve(now: after);
      expect(early.dayKey, '2026-11-10');
    });
  });
}
