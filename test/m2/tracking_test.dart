/// 埋点体系测试（§3.3 / §7.5）：9 个事件的 name 与 payload 键集合正确，
/// 且 TrackingEventNames 常量字符串与验证计划一字不差。
///
/// 纯 Dart：仅构造事件并断言，不实例化 Flutter 页面（页面级埋点由真机验证）。
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:test/test.dart';

/// 实现 TrackingRepository 的 Fake，捕获所有 track 调用供断言。
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
  group('TrackingEventNames 常量与 §3.3 完全一致', () {
    test('9 个事件名', () {
      expect(TrackingEventNames.focusSessionStart, 'focus_session_start');
      expect(TrackingEventNames.focusSessionEnd, 'focus_session_end');
      expect(TrackingEventNames.sunEarned, 'sun_earned');
      expect(TrackingEventNames.validFocusDay, 'valid_focus_day');
      expect(TrackingEventNames.rewardRedeemRequest, 'reward_redeem_request');
      expect(TrackingEventNames.rewardVerified, 'reward_verified');
      expect(TrackingEventNames.rewardQueue, 'reward_queue');
      expect(TrackingEventNames.weeklyPoolReset, 'weekly_pool_reset');
      expect(TrackingEventNames.parentDau, 'parent_dau');
    });
  });

  final DateTime now = DateTime(2026, 9, 15, 10, 0, 0);

  /// 构造 9 个事件（payload 键严格按 §3.3）。
  Map<String, TrackingEvent> buildEvents() => {
        TrackingEventNames.focusSessionStart: TrackingEvent(
          id: 'e1',
          name: TrackingEventNames.focusSessionStart,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'session_id': 's1',
            'planned_min': 30,
            'tier': 'low',
          },
        ),
        TrackingEventNames.focusSessionEnd: TrackingEvent(
          id: 'e2',
          name: TrackingEventNames.focusSessionEnd,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'session_id': 's1',
            'actual_min': 28.5,
            'reason': 'completed',
            'tier': 'low',
          },
        ),
        TrackingEventNames.validFocusDay: TrackingEvent(
          id: 'e3',
          name: TrackingEventNames.validFocusDay,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'day_key': '2026-09-15',
            'actual_min': 28.5,
            'met': true,
          },
        ),
        TrackingEventNames.sunEarned: TrackingEvent(
          id: 'e4',
          name: TrackingEventNames.sunEarned,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'gross': 30.0,
            'net': 25.0,
            'balance_after': 120.0,
            'capped': false,
          },
        ),
        TrackingEventNames.rewardRedeemRequest: TrackingEvent(
          id: 'e5',
          name: TrackingEventNames.rewardRedeemRequest,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'reward_id': 'r1',
            'cost_sun': 20,
            'category': 'parentHandled',
            'tier': 'low',
            'is_auto_pass': true,
          },
        ),
        TrackingEventNames.rewardVerified: TrackingEvent(
          id: 'e6',
          name: TrackingEventNames.rewardVerified,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'request_id': 'r1',
            'verify_ts': now.toIso8601String(),
            'within_48h': true,
            'amount': 20,
            'tier': 'low',
            'is_small': true,
          },
        ),
        TrackingEventNames.rewardQueue: TrackingEvent(
          id: 'e7',
          name: TrackingEventNames.rewardQueue,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'request_id': 'r2',
            'queue_rank': 1,
            'month': '2026-09',
          },
        ),
        TrackingEventNames.weeklyPoolReset: TrackingEvent(
          id: 'e8',
          name: TrackingEventNames.weeklyPoolReset,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'pool_size': 160,
            'tier': 'low',
          },
        ),
        TrackingEventNames.parentDau: TrackingEvent(
          id: 'e9',
          name: TrackingEventNames.parentDau,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'ts': now.toIso8601String(),
            'tier': 'low',
          },
        ),
      };

  group('9 个事件 payload 键集合与 §3.3 一致', () {
    final events = buildEvents();

    test('focus_session_start', () {
      final e = events[TrackingEventNames.focusSessionStart]!;
      expect(e.name, 'focus_session_start');
      expect(e.payload.keys.toSet(),
          {'session_id', 'planned_min', 'tier'});
    });
    test('focus_session_end', () {
      final e = events[TrackingEventNames.focusSessionEnd]!;
      expect(e.name, 'focus_session_end');
      expect(e.payload.keys.toSet(),
          {'session_id', 'actual_min', 'reason', 'tier'});
    });
    test('valid_focus_day', () {
      final e = events[TrackingEventNames.validFocusDay]!;
      expect(e.name, 'valid_focus_day');
      expect(e.payload.keys.toSet(), {'day_key', 'actual_min', 'met'});
    });
    test('sun_earned', () {
      final e = events[TrackingEventNames.sunEarned]!;
      expect(e.name, 'sun_earned');
      expect(e.payload.keys.toSet(),
          {'gross', 'net', 'balance_after', 'capped'});
    });
    test('reward_redeem_request', () {
      final e = events[TrackingEventNames.rewardRedeemRequest]!;
      expect(e.name, 'reward_redeem_request');
      expect(e.payload.keys.toSet(),
          {'reward_id', 'cost_sun', 'category', 'tier', 'is_auto_pass'});
    });
    test('reward_verified', () {
      final e = events[TrackingEventNames.rewardVerified]!;
      expect(e.name, 'reward_verified');
      expect(e.payload.keys.toSet(),
          {'request_id', 'verify_ts', 'within_48h', 'amount', 'tier', 'is_small'});
    });
    test('reward_queue', () {
      final e = events[TrackingEventNames.rewardQueue]!;
      expect(e.name, 'reward_queue');
      expect(e.payload.keys.toSet(),
          {'request_id', 'queue_rank', 'month'});
    });
    test('weekly_pool_reset', () {
      final e = events[TrackingEventNames.weeklyPoolReset]!;
      expect(e.name, 'weekly_pool_reset');
      expect(e.payload.keys.toSet(), {'pool_size', 'tier'});
    });
    test('parent_dau', () {
      final e = events[TrackingEventNames.parentDau]!;
      expect(e.name, 'parent_dau');
      expect(e.payload.keys.toSet(), {'ts', 'tier'});
    });
  });

  group('FakeTrackingRepository 捕获事件', () {
    test('track 后 events 可读回', () async {
      final repo = FakeTrackingRepository();
      final events = buildEvents();
      for (final e in events.values) {
        await repo.track(e);
      }
      expect(repo.events, hasLength(9));
      expect(repo.events.where((e) => e.type == TrackingType.metric).length, 9);
    });
  });

  // ── P0 · B 新增 3 个纪念册事件（不改动上面既有 9 条断言）──────────────
  group('P0 · B 新增 3 个埋点事件（纪念册）：name 与 payload 键集合', () {
    test('事件名常量与《验证计划 §3.2》一致', () {
      expect(TrackingEventNames.praiseSent, 'praise_sent');
      expect(TrackingEventNames.gardenSnapshot, 'garden_snapshot');
      expect(TrackingEventNames.milestoneEvent, 'milestone_event');
    });

    test('payload 键集合严格匹配；事件 type 一律 milestone', () {
      final TrackingEvent praise = TrackingEvent(
        id: 'm1',
        name: TrackingEventNames.praiseSent,
        type: TrackingType.milestone,
        ts: now,
        payload: {'content_hash': 'abc123', 'ts': now.toIso8601String()},
      );
      final TrackingEvent snapshot = TrackingEvent(
        id: 'm2',
        name: TrackingEventNames.gardenSnapshot,
        type: TrackingType.milestone,
        ts: now,
        payload: {'week_no': '2026-09-14', 'garden_state': '[]'},
      );
      final TrackingEvent milestone = TrackingEvent(
        id: 'm3',
        name: TrackingEventNames.milestoneEvent,
        type: TrackingType.milestone,
        ts: now,
        payload: {'type': 'first_bloom', 'ts': now.toIso8601String()},
      );

      expect(praise.payload.keys.toSet(), {'content_hash', 'ts'});
      expect(snapshot.payload.keys.toSet(), {'week_no', 'garden_state'});
      expect(milestone.payload.keys.toSet(), {'type', 'ts'});

      expect(praise.type, TrackingType.milestone);
      expect(snapshot.type, TrackingType.milestone);
      expect(milestone.type, TrackingType.milestone);
    });
  });
}
