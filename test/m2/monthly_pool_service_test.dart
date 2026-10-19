/// 周阳光池服务测试（§3.2 / §4.1；**C90-C 同日二次修订**）。
///
/// 纯 Dart：用 Fake 仓储替换 WeeklyPoolRepository / SettingsRepository /
/// TrackingRepository / AccountService。
///
/// 预算口径（判定单点 `WeeklyPoolService._budgetForCurrentTier`）：
///  · 注入 [AccountService] → 预算按 `FakeAccountService.currentAgeTier` 派生
///    （低 300 / 中 600 / 高 0 不限额哨兵），`settings.poolBudget` 已退出消费链
///    （夹具故意保留 160 作金丝雀：若服务仍读它，下述断言会翻车）；
///  · 未注入（旧路径）→ 回退全局 settings 单行 `ageTier` 派生。
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:test/test.dart';

/// 测试用低档默认设置（AppSettings 部分字段为 required，集中提供）。
///
/// 🔴 `poolBudget: 160` 是**金丝雀**：C90-C 同日二次修订起 `settings.poolBudget`
/// 不再被服务消费（实际预算按年级默认值派生）；若有人把消费链接回来，
/// 下面的 300/600 断言会立即失败。
const lowSettings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

class FakeWeeklyPoolRepository implements WeeklyPoolRepository {
  final Map<String, WeeklyPool> store = {};
  @override
  Future<WeeklyPool?> get(String weekKey) async => store[weekKey];
  @override
  Future<void> upsert(WeeklyPool pool) async => store[pool.weekKey] = pool;
  @override
  List<String> weeksBetween(String fromKey, String toKey) => [fromKey, toKey];
}

class FakeSettingsRepository implements SettingsRepository {
  final AppSettings _settings;
  FakeSettingsRepository(this._settings);
  @override
  Future<AppSettings> getSettings() async => _settings;
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class FakeTrackingRepository implements TrackingRepository {
  final List<TrackingEvent> events = [];
  @override
  Future<void> track(TrackingEvent e) async => events.add(e);
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      events.where((e) => e.type == t).toList();
  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

/// 档位可配置的账号 Fake（C90-C 同日二次修订：预算按当前孩子年级派生）。
///
/// 恒单孩子桩口径：仅 `currentAgeTier()` 有语义，其余成员只满足接口。
class FakeAccountService implements AccountService {
  FakeAccountService(this._tier);
  final AgeTier _tier;

  @override
  String get childId => kChildIdDefault;
  @override
  String currentChildId() => kChildIdDefault;
  @override
  Future<void> ensureChild() => throw UnsupportedError('x');
  @override
  Future<void> initialize() async {}
  @override
  Future<void> switchTo(String id) => throw UnsupportedError('x');
  @override
  Future<ChildProfile> createChild(String name, AgeTier ageTier) =>
      throw UnsupportedError('x');
  @override
  Future<ChildProfile?> currentProfile() async => null;
  @override
  Future<AgeTier> currentAgeTier() async => _tier;
  @override
  Never signIn() => throw UnsupportedError('x');
  @override
  Never linkFamily() => throw UnsupportedError('x');
  @override
  Never syncProfile() => throw UnsupportedError('x');
}

void main() {
  group('WeeklyPoolService', () {
    test('ensureAndReset 首次建池：预算按注入 AccountService 的当前年级派生（低→300），'
        'tier 键维持全局 settings 口径', () async {
      final settings = FakeSettingsRepository(lowSettings);
      final repo = FakeWeeklyPoolRepository();
      final tracking = FakeTrackingRepository();
      final service = WeeklyPoolService(repo, settings, tracking,
          account: FakeAccountService(AgeTier.low));

      final now = DateTime(2026, 9, 15);
      final pool = await service.ensureAndReset(now);

      expect(pool.weekKey, '2026-09-14');
      // C90-C 同日二次修订：低年级默认 300（不再读 settings.poolBudget=160 金丝雀）。
      expect(pool.budget, kPoolBudgetDefaultLow);
      expect(repo.store.containsKey('2026-09-14'), isTrue);
      expect(tracking.events, hasLength(1));
      expect(tracking.events.first.name, TrackingEventNames.weeklyPoolReset);
      expect(tracking.events.first.payload['pool_size'], kPoolBudgetDefaultLow);
      // 既有裁定：tier 埋点键维持全局 settings 口径（勿改）。
      expect(tracking.events.first.payload['tier'], 'low');
    });

    test('ensureAndReset：中年级→600 / 高年级→0（不限额哨兵）', () async {
      final now = DateTime(2026, 9, 15);

      final mid = WeeklyPoolService(
        FakeWeeklyPoolRepository(),
        FakeSettingsRepository(lowSettings),
        FakeTrackingRepository(),
        account: FakeAccountService(AgeTier.mid),
      );
      expect((await mid.ensureAndReset(now)).budget, kPoolBudgetDefaultMid);

      final high = WeeklyPoolService(
        FakeWeeklyPoolRepository(),
        FakeSettingsRepository(lowSettings),
        FakeTrackingRepository(),
        account: FakeAccountService(AgeTier.high),
      );
      // 高年级不限额哨兵 0：兑换只受阳光余额约束（判定单点 RedemptionService.decide）。
      expect(
        (await high.ensureAndReset(now)).budget,
        kWeeklyPoolBudgetUnlimited,
      );
    });

    test('同周二次 ensureAndReset 不重建、不重复 track', () async {
      final settings = FakeSettingsRepository(lowSettings);
      final repo = FakeWeeklyPoolRepository();
      final tracking = FakeTrackingRepository();
      final service = WeeklyPoolService(repo, settings, tracking);

      final pool1 = await service.ensureAndReset(DateTime(2026, 9, 15));
      final pool2 = await service.ensureAndReset(DateTime(2026, 9, 20));

      // C91：既有行返回「预算即时派生」的视图副本（非同一实例），记账字段原样。
      expect(pool2.weekKey, pool1.weekKey);
      expect(pool2.budget, pool1.budget);
      expect(pool2.used, pool1.used);
      expect(pool2.autoReleased, pool1.autoReleased);
      expect(tracking.events, hasLength(1)); // 仅首次 track
      expect(repo.store.length, 1);
    });

    test('C91 即时派生：存量行预算 400（修复前旧值）→ 读取视图立即纠正为年级默认值，'
        '行内 budget 列不被改写', () async {
      final repo = FakeWeeklyPoolRepository();
      // 模拟「周池即时派生」上线前建的存量行：budget=400（不回填纪律下一直带着旧值）。
      repo.store['2026-09-14'] = const WeeklyPool(
        weekKey: '2026-09-14',
        budget: 400,
        used: 120,
        autoReleased: 30,
      );
      final service = WeeklyPoolService(
        repo,
        FakeSettingsRepository(lowSettings),
        FakeTrackingRepository(),
        account: FakeAccountService(AgeTier.low), // 低档 → 300
      );

      final p = await service.pool('2026-09-14');
      expect(p.budget, kPoolBudgetDefaultLow,
          reason: '展示/判定一律现算：高年级立即「不限」、低/中立即 300/600');
      expect(p.used, 120, reason: '行只承担 used/autoReleased 记账，原样透出');
      expect(p.autoReleased, 30);

      final ensured = await service.ensureAndReset(DateTime(2026, 9, 15));
      expect(ensured.budget, kPoolBudgetDefaultLow);
      expect(ensured.used, 120);
      // 行内 budget 列不被改写（列保留标废弃，无迁移；历史行自然作废）。
      expect(repo.store['2026-09-14']!.budget, 400);
    });

    test('pool() 占位池：预算按注入 AccountService 的当前年级派生（中→600）', () async {
      final service = WeeklyPoolService(
        FakeWeeklyPoolRepository(),
        FakeSettingsRepository(lowSettings),
        FakeTrackingRepository(),
        account: FakeAccountService(AgeTier.mid),
      );
      final p = await service.pool('2026-01-05');
      expect(p.budget, kPoolBudgetDefaultMid);
      expect(p.used, 0);
      expect(p.autoReleased, 0);
    });

    test('pool() 旧路径回退：未注入 AccountService → 按 settings.ageTier 派生（低→300）',
        () async {
      final service = WeeklyPoolService(
        FakeWeeklyPoolRepository(),
        FakeSettingsRepository(lowSettings), // ageTier: low
        FakeTrackingRepository(),
      );
      final p = await service.pool('2026-01-05');
      expect(p.budget, kPoolBudgetDefaultLow);
    });

    test('ensureAndReset 旧路径回退：未注入 AccountService → 按 settings.ageTier 派生（低→300）',
        () async {
      final repo = FakeWeeklyPoolRepository();
      final service = WeeklyPoolService(
        repo,
        FakeSettingsRepository(lowSettings), // ageTier: low
        FakeTrackingRepository(),
      );
      final pool = await service.ensureAndReset(DateTime(2026, 9, 15));
      expect(pool.budget, kPoolBudgetDefaultLow);
    });

    test('applyRedemption：auto=true 累 autoReleased，auto=false 累 used，upsert 可读回',
        () async {
      final settings = FakeSettingsRepository(lowSettings);
      final repo = FakeWeeklyPoolRepository();
      final service = WeeklyPoolService(repo, settings, FakeTrackingRepository());

      final now = DateTime(2026, 9, 1);
      final base = await service.ensureAndReset(now);

      await service.applyRedemption(base, 30, auto: true);
      final after1 = (await repo.get('2026-08-31'))!;
      expect(after1.autoReleased, 30);
      expect(after1.used, 0);

      await service.applyRedemption(after1, 20, auto: false);
      final after2 = (await repo.get('2026-08-31'))!;
      expect(after2.autoReleased, 30);
      expect(after2.used, 20);
    });

  });
}
