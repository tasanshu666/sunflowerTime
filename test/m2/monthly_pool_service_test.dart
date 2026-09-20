/// 月度池服务测试（§3.2 / §4.1）。
///
/// 纯 Dart：用 Fake 仓储替换 MonthlyPoolRepository / SettingsRepository / TrackingRepository。
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/monthly_pool.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/monthly_pool_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/monthly_pool_service.dart';
import 'package:test/test.dart';

/// 测试用低档默认设置（AppSettings 部分字段为 required，集中提供）。
const lowSettings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  monthlyPoolBudget: 160,
);

class FakeMonthlyPoolRepository implements MonthlyPoolRepository {
  final Map<String, MonthlyPool> store = {};
  @override
  Future<MonthlyPool?> get(String monthKey) async => store[monthKey];
  @override
  Future<void> upsert(MonthlyPool pool) async => store[pool.monthKey] = pool;
  @override
  List<String> monthsBetween(String fromKey, String toKey) => [fromKey, toKey];
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

void main() {
  group('MonthlyPoolService', () {
    test('ensureAndReset 首次建池：budget=设置默认值，且 track monthly_pool_reset',
        () async {
      final settings = FakeSettingsRepository(lowSettings);
      final repo = FakeMonthlyPoolRepository();
      final tracking = FakeTrackingRepository();
      final service = MonthlyPoolService(repo, settings, tracking);

      final now = DateTime(2026, 9, 15);
      final pool = await service.ensureAndReset(now);

      expect(pool.monthKey, '2026-09');
      expect(pool.budget, 160);
      expect(repo.store.containsKey('2026-09'), isTrue);
      expect(tracking.events, hasLength(1));
      expect(tracking.events.first.name, TrackingEventNames.monthlyPoolReset);
      expect(tracking.events.first.payload['pool_size'], 160);
      expect(tracking.events.first.payload['tier'], 'low');
    });

    test('同月二次 ensureAndReset 不重建、不重复 track', () async {
      final settings = FakeSettingsRepository(lowSettings);
      final repo = FakeMonthlyPoolRepository();
      final tracking = FakeTrackingRepository();
      final service = MonthlyPoolService(repo, settings, tracking);

      final pool1 = await service.ensureAndReset(DateTime(2026, 9, 15));
      final pool2 = await service.ensureAndReset(DateTime(2026, 9, 20));

      expect(pool2, same(pool1)); // 返回既有实例，不新建
      expect(tracking.events, hasLength(1)); // 仅首次 track
      expect(repo.store.length, 1);
    });

    test('pool() 不存在时返回以默认预算填充的占位池（不落库）', () async {
      final settings = FakeSettingsRepository(lowSettings);
      final service = MonthlyPoolService(
        FakeMonthlyPoolRepository(),
        settings,
        FakeTrackingRepository(),
      );
      final p = await service.pool('2026-01');
      expect(p.budget, 160);
      expect(p.used, 0);
      expect(p.autoReleased, 0);
    });

    test('applyRedemption：auto=true 累 autoReleased，auto=false 累 used，upsert 可读回',
        () async {
      final settings = FakeSettingsRepository(lowSettings);
      final repo = FakeMonthlyPoolRepository();
      final service = MonthlyPoolService(repo, settings, FakeTrackingRepository());

      final now = DateTime(2026, 9, 1);
      final base = await service.ensureAndReset(now);

      await service.applyRedemption(base, 30, auto: true);
      final after1 = (await repo.get('2026-09'))!;
      expect(after1.autoReleased, 30);
      expect(after1.used, 0);

      await service.applyRedemption(after1, 20, auto: false);
      final after2 = (await repo.get('2026-09'))!;
      expect(after2.autoReleased, 30);
      expect(after2.used, 20);
    });

    test('autoApproveCap 低档 160 → 40', () async {
      final settings = FakeSettingsRepository(lowSettings);
      final service = MonthlyPoolService(
        FakeMonthlyPoolRepository(),
        settings,
        FakeTrackingRepository(),
      );
      final pool = await service.ensureAndReset(DateTime(2026, 9, 1));
      expect(service.autoApproveCap(pool, AgeTier.low), 40);
    });
  });
}
