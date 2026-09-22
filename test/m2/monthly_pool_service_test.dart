/// 周阳光池服务测试（§3.2 / §4.1）。
///
/// 纯 Dart：用 Fake 仓储替换 WeeklyPoolRepository / SettingsRepository / TrackingRepository。
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:test/test.dart';

/// 测试用低档默认设置（AppSettings 部分字段为 required，集中提供）。
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

void main() {
  group('WeeklyPoolService', () {
    test('ensureAndReset 首次建池：budget=设置默认值，且 track weekly_pool_reset',
        () async {
      final settings = FakeSettingsRepository(lowSettings);
      final repo = FakeWeeklyPoolRepository();
      final tracking = FakeTrackingRepository();
      final service = WeeklyPoolService(repo, settings, tracking);

      final now = DateTime(2026, 9, 15);
      final pool = await service.ensureAndReset(now);

      expect(pool.weekKey, '2026-09-14');
      expect(pool.budget, 160);
      expect(repo.store.containsKey('2026-09-14'), isTrue);
      expect(tracking.events, hasLength(1));
      expect(tracking.events.first.name, TrackingEventNames.weeklyPoolReset);
      expect(tracking.events.first.payload['pool_size'], 160);
      expect(tracking.events.first.payload['tier'], 'low');
    });

    test('同周二次 ensureAndReset 不重建、不重复 track', () async {
      final settings = FakeSettingsRepository(lowSettings);
      final repo = FakeWeeklyPoolRepository();
      final tracking = FakeTrackingRepository();
      final service = WeeklyPoolService(repo, settings, tracking);

      final pool1 = await service.ensureAndReset(DateTime(2026, 9, 15));
      final pool2 = await service.ensureAndReset(DateTime(2026, 9, 20));

      expect(pool2, same(pool1)); // 返回既有实例，不新建
      expect(tracking.events, hasLength(1)); // 仅首次 track
      expect(repo.store.length, 1);
    });

    test('pool() 不存在时返回以默认预算填充的占位池（不落库）', () async {
      final settings = FakeSettingsRepository(lowSettings);
      final service = WeeklyPoolService(
        FakeWeeklyPoolRepository(),
        settings,
        FakeTrackingRepository(),
      );
      final p = await service.pool('2026-01-05');
      expect(p.budget, 160);
      expect(p.used, 0);
      expect(p.autoReleased, 0);
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

    test('autoApproveCap 低档 160 → 40', () async {
      final settings = FakeSettingsRepository(lowSettings);
      final service = WeeklyPoolService(
        FakeWeeklyPoolRepository(),
        settings,
        FakeTrackingRepository(),
      );
      final pool = await service.ensureAndReset(DateTime(2026, 9, 1));
      expect(service.autoApproveCap(pool, AgeTier.low), 40);
    });
  });
}
