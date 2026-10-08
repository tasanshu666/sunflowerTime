/// App 使用时长「单次限时」控制器测试（F99，玄参 2026-10-08）。
///
/// 口径：娱乐 tab 连续使用满 [kSingleUseLimitMinutes]（10）分钟 → 锁定娱乐 tab
/// [kSingleUseLockMinutes]（10）分钟 → 解锁后可继续（每日 30 分钟总量照旧拦截）。
/// 关键不变量：
///  ① 首次结算到点 → 锁定（lockedUntilMs 非空 + 单次秒数归零 + 停表）；
///  ② 锁定期间 startCounting 不放行（counting 恒 false）；
///  ③ 锁定期满 → 惰性解锁，可重新计时（单次从 0 重新累计）；
///  ④ 解锁时刻持久化：锁定时落盘、到期清锁时移除（重启绕不过锁定）。
///
/// 测试缝：控制器构造参数注入 `singleLimitMinutes=0`（任意结算即到点）/
/// `singleLockMinutes`（0 = 即时到期），免去真实等待 10 分钟。
library app_usage_single_limit_test;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/app_usage_service.dart';
import 'package:sunflower_time/presentation/child/state/app_usage_controller.dart';

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.high,
        dailyFocusCap: 120,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 400,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

Future<ProviderContainer> _container({
  required int singleLimitMinutes,
  required int singleLockMinutes,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      settingsStoreProvider.overrideWithValue(SettingsStore(sp)),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      appUsageControllerProvider.overrideWith(
        () => AppUsageController(
          singleLimitMinutes: singleLimitMinutes,
          singleLockMinutes: singleLockMinutes,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('纯函数边界：isSingleLimitReached 599 秒 false / 600 秒 true', () {
    expect(
      AppUsageService.isSingleLimitReached(
          limitMinutes: 10, singleSeconds: 599),
      isFalse,
    );
    expect(
      AppUsageService.isSingleLimitReached(
          limitMinutes: 10, singleSeconds: 600),
      isTrue,
    );
  });

  test('F99①②：单次到点 → 锁定 + 停表 + 单次归零 + 持久化；锁定中不放行', () async {
    final ProviderContainer container = await _container(
      singleLimitMinutes: 0, // 任意结算即到点
      singleLockMinutes: 10,
    );
    final AppUsageController ctrl = container.read(appUsageControllerProvider.notifier);

    await ctrl.startCounting();
    await ctrl.stopCounting(); // 触发一次结算 → 单次到点 → 锁定

    final AppUsageState s = container.read(appUsageControllerProvider);
    expect(s.lockedUntilMs, isNotNull, reason: '到点必须锁定');
    expect(s.singleSeconds, 0, reason: '锁定触发时单次秒数归零');
    expect(s.counting, isFalse, reason: '锁定即刻停表');
    expect(s.sessionLockedAt(DateTime.now()), isTrue);

    // 锁定中再进娱乐 tab：不放行。
    await ctrl.startCounting();
    expect(container.read(appUsageControllerProvider).counting, isFalse,
        reason: '锁定期间 startCounting 不放行');

    // 持久化：解锁时刻已落盘。
    final SharedPreferences sp = await SharedPreferences.getInstance();
    expect(sp.getInt(kPrefAppUsageLockedUntilMs), s.lockedUntilMs);
  });

  test('F99③④：锁定期满 → 惰性解锁、可重新计时、持久化清除', () async {
    final ProviderContainer container = await _container(
      singleLimitMinutes: 0,
      singleLockMinutes: 0, // 锁定即时到期
    );
    final AppUsageController ctrl = container.read(appUsageControllerProvider.notifier);

    await ctrl.startCounting();
    await ctrl.stopCounting(); // 锁定并立即到期

    // 到期后再进娱乐 tab：应放行且重新计时（单次从 0 重新累计）。
    await ctrl.startCounting();
    final AppUsageState s = container.read(appUsageControllerProvider);
    expect(s.sessionLockedAt(DateTime.now()), isFalse, reason: '锁定期满自动解锁');
    expect(s.counting, isTrue, reason: '解锁后可重新计时');

    // 持久化清除：到期解锁后 sp 中不再有锁定时刻（清除为 unawaited，让事件队列跑完）。
    // ⚠️ 必须在 stopCounting 之前断言——测试缝 limit=0 时任何一次 settle 都会再次
    // 触发锁定并重新落盘（生产 limit=10 不存在该现象）。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final SharedPreferences sp = await SharedPreferences.getInstance();
    expect(sp.getInt(kPrefAppUsageLockedUntilMs), isNull);
    await ctrl.stopCounting();
  });

  test('对照：未到点（单次秒数很少）不触发锁定', () async {
    final ProviderContainer container = await _container(
      singleLimitMinutes: 10,
      singleLockMinutes: 10,
    );
    final AppUsageController ctrl = container.read(appUsageControllerProvider.notifier);

    await ctrl.startCounting();
    await ctrl.stopCounting(); // 增量≈0 秒

    final AppUsageState s = container.read(appUsageControllerProvider);
    expect(s.lockedUntilMs, isNull, reason: '未到点不锁定');
    expect(s.reached, isFalse);
    expect(s.sessionLockedAt(DateTime.now()), isFalse);
  });
}
