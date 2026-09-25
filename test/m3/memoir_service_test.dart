/// 纪念册服务单测（P0 · B，§6 测试要点）。
///
/// 锁 4 件事：
///  ① `ensureWeeklySnapshot` 连调两次只写 1 条（幂等）；跨周写 2 条且 `week_no` 不同；
///  ② `recordMilestone` 同 type 连调两次只 1 条；不同 type 各 1 条；
///  ③ 3 个事件 payload 键集合精确匹配《验证计划 §3.2》；
///  ④ 事件 type 一律 `milestone`。
///
/// 纯 Dart（`package:test`）—— 用手写 Fake 仓储，不触碰真实 DB / 不改接口。
library;

import 'dart:convert';

import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/memoir_service.dart';
import 'package:test/test.dart';

/// 捕获全部 track 调用的 Fake（**实现既有 3 方法，不加方法**）。
class _FakeTracking implements TrackingRepository {
  final List<TrackingEvent> events = <TrackingEvent>[];
  @override
  Future<void> track(TrackingEvent e) async => events.add(e);
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      events.where((TrackingEvent e) => e.type == t).toList();
  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

/// 最小 Fake 植物仓储（只用到 [plants]）。
class _FakePlants implements PlantRepository {
  _FakePlants(this._plants);
  final List<Plant> _plants;
  @override
  Future<List<Plant>> plants() async => _plants;
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[];
}

void main() {
  final DateTime now = DateTime(2026, 9, 23, 10, 0, 0);

  Plant plant(String id, {PlantStatus status = PlantStatus.growing}) => Plant(
        id: id,
        speciesId: 'species_sunflower',
        potIndex: 0,
        stage: PlantStage.sprout,
        stageStartedAt: now,
        growthFactor: 1.0,
        status: status,
        plantedAt: now,
        growthProgress: 0.5,
      );

  List<TrackingEvent> named(List<TrackingEvent> events, String name) =>
      events.where((TrackingEvent e) => e.name == name).toList();

  group('ensureWeeklySnapshot：惰性 + 幂等 + 不补历史周', () {
    test('连调两次 → 只写 1 条（本周已写则跳过）', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc =
          MemoirService(tracking, _FakePlants(<Plant>[plant('p1')]));

      await svc.ensureWeeklySnapshot(now);
      await svc.ensureWeeklySnapshot(now);

      expect(named(tracking.events, TrackingEventNames.gardenSnapshot),
          hasLength(1));
    });

    test('跨周 → 2 条，week_no 不同', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc =
          MemoirService(tracking, _FakePlants(<Plant>[plant('p1')]));

      await svc.ensureWeeklySnapshot(DateTime(2026, 9, 23)); // 周三
      await svc.ensureWeeklySnapshot(DateTime(2026, 9, 30)); // 次周周三

      final List<TrackingEvent> snaps =
          named(tracking.events, TrackingEventNames.gardenSnapshot);
      expect(snaps, hasLength(2));
      expect(snaps[0].payload['week_no'], isNot(snaps[1].payload['week_no']));
    });

    test('payload 键集合 = {week_no, garden_state}；type = milestone', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc = MemoirService(
        tracking,
        _FakePlants(<Plant>[plant('p1', status: PlantStatus.bloomed)]),
      );

      await svc.ensureWeeklySnapshot(now);

      final TrackingEvent e = tracking.events.single;
      expect(e.name, TrackingEventNames.gardenSnapshot);
      expect(e.type, TrackingType.milestone);
      expect(e.payload.keys.toSet(), <String>{'week_no', 'garden_state'});
    });
  });

  group('recordMilestone：按 type 去重（一生只写一次）', () {
    test('同 type 连调两次 → 只 1 条', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc = MemoirService(tracking, _FakePlants(<Plant>[]));

      await svc.recordMilestone('first_bloom', now);
      await svc.recordMilestone('first_bloom', now);

      expect(named(tracking.events, TrackingEventNames.milestoneEvent),
          hasLength(1));
    });

    test('不同 type → 各 1 条', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc = MemoirService(tracking, _FakePlants(<Plant>[]));

      await svc.recordMilestone('first_bloom', now);
      await svc.recordMilestone('valid_days_30', now);

      final List<TrackingEvent> miles =
          named(tracking.events, TrackingEventNames.milestoneEvent);
      expect(miles, hasLength(2));
      expect(miles.map((TrackingEvent e) => e.payload['type']).toSet(),
          <String>{'first_bloom', 'valid_days_30'});
    });

    test('payload 键集合 = {type, ts}；type = milestone', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc = MemoirService(tracking, _FakePlants(<Plant>[]));

      await svc.recordMilestone('first_valid_focus_day', now);

      final TrackingEvent e = tracking.events.single;
      expect(e.type, TrackingType.milestone);
      expect(e.payload.keys.toSet(), <String>{'type', 'ts'});
    });
  });

  group('recordPraiseSent', () {
    test('payload 键集合 = {content_hash, ts}；type = milestone；hash 为 sha256 hex',
        () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc = MemoirService(tracking, _FakePlants(<Plant>[]));

      await svc.recordPraiseSent('宝贝今天真棒', now);

      final TrackingEvent e = tracking.events.single;
      expect(e.name, TrackingEventNames.praiseSent);
      expect(e.type, TrackingType.milestone);
      expect(e.payload.keys.toSet(), <String>{'content_hash', 'ts'});
      expect((e.payload['content_hash'] as String).length, 64); // sha256 hex 长度
    });

    test('相同内容 hash 稳定；不同内容 hash 不同', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc = MemoirService(tracking, _FakePlants(<Plant>[]));

      await svc.recordPraiseSent('A', now);
      await svc.recordPraiseSent('A', now);
      await svc.recordPraiseSent('B', now);

      final List<TrackingEvent> praises =
          named(tracking.events, TrackingEventNames.praiseSent);
      expect(praises, hasLength(3));
      expect(praises[0].payload['content_hash'], praises[1].payload['content_hash']);
      expect(praises[0].payload['content_hash'], isNot(praises[2].payload['content_hash']));
    });
  });

  // ── QA 独立补强：garden_state 序列化健壮性 + 多里程碑具现 ──────────────
  group('ensureWeeklySnapshot · garden_state 序列化（QA 补强）', () {
    test('花园为空 → garden_state = "[]" 且不崩，仍写入 1 条', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc = MemoirService(tracking, _FakePlants(<Plant>[]));

      await svc.ensureWeeklySnapshot(now);

      final TrackingEvent e = tracking.events.single;
      expect(e.payload['garden_state'], '[]');
      expect(jsonDecode(e.payload['garden_state'] as String), isEmpty);
    });

    test('多株植物 → garden_state 为 JSON 数组，长度与植物数一致，字段齐全', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc = MemoirService(
        tracking,
        _FakePlants(<Plant>[
          plant('p1'),
          plant('p2', status: PlantStatus.bloomed),
          plant('p3', status: PlantStatus.wilting),
        ]),
      );

      await svc.ensureWeeklySnapshot(now);

      final String raw = tracking.events.single.payload['garden_state'] as String;
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      expect(decoded, hasLength(3));
      expect(
        (decoded.first as Map<String, dynamic>).keys.toSet(),
        <String>{'id', 'species', 'stage', 'status', 'progress'},
      );
    });

    test('跨 3 周 → 3 条快照，week_no 两两不同（每周一份，不重不漏）', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc =
          MemoirService(tracking, _FakePlants(<Plant>[plant('p1')]));

      await svc.ensureWeeklySnapshot(DateTime(2026, 9, 23)); // 周三
      await svc.ensureWeeklySnapshot(DateTime(2026, 9, 30));
      await svc.ensureWeeklySnapshot(DateTime(2026, 10, 7));

      final List<TrackingEvent> snaps =
          named(tracking.events, TrackingEventNames.gardenSnapshot);
      expect(snaps, hasLength(3));
      expect(
        snaps.map((TrackingEvent e) => e.payload['week_no']).toSet(),
        hasLength(3),
      );
    });
  });

  group('recordMilestone · 同一轮结算跨过多个里程碑（QA 补强）', () {
    test('4 类里程碑各记 1 条；重复结算再调 → 去重后仍 4 条', () async {
      final _FakeTracking tracking = _FakeTracking();
      final MemoirService svc = MemoirService(tracking, _FakePlants(<Plant>[]));
      const List<String> four = <String>[
        'first_valid_focus_day',
        'focus_total_600min',
        'valid_days_30',
        'first_bloom',
      ];

      for (final String t in four) {
        await svc.recordMilestone(t, now);
      }
      expect(named(tracking.events, TrackingEventNames.milestoneEvent),
          hasLength(4));

      // 第二轮结算（阈值仍满足）重复调用 → 按 type 去重，仍 4 条。
      for (final String t in four) {
        await svc.recordMilestone(t, now);
      }
      expect(named(tracking.events, TrackingEventNames.milestoneEvent),
          hasLength(4));
    });
  });
}
