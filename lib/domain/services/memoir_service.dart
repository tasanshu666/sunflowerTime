/// 纪念册服务（P0 · B，§8.3 毕业纪念册 / §6 埋点最低事件集）。
///
/// 三大事件（`praise_sent` / `garden_snapshot` / `milestone_event`）的写入与去重。
///
/// ⛔ **铁律：零 `TrackingRepository` 接口变更** —— 该接口被 5 处手写 fake 实现
/// （`test/m2/tracking_test.dart`、`test/nav/nav_structure_test.dart` 等），任何新增
/// 方法都会让它们编译失败。故本服务**只调**现成的 `track` / `eventsOfType`，
/// 去重一律走 `eventsOfType(TrackingType.milestone)` + 内存过滤。
///
/// 纯 Dart，零 Flutter 依赖（可 `package:test` 直接单测）。
library memoir_service;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';

/// 纪念册服务：花园周快照 / 里程碑 / 夸夸语录送达。
class MemoirService {
  MemoirService(this._tracking, this._plants);

  final TrackingRepository _tracking;
  final PlantRepository _plants;

  /// 每周花园快照（**惰性 + 幂等**）：本周已写则跳过；**不补历史周**（不伪造错标数据）。
  ///
  /// payload：`{ week_no: <weekKey(now)>, garden_state: <json 串> }`，type = milestone。
  Future<void> ensureWeeklySnapshot(DateTime now) async {
    final String week = weekKey(now);
    final List<TrackingEvent> milestones =
        await _tracking.eventsOfType(TrackingType.milestone);
    final bool already =
        milestones.any((TrackingEvent e) =>
            e.name == TrackingEventNames.gardenSnapshot &&
            e.payload['week_no'] == week);
    if (already) return;

    final List<Plant> plants = await _plants.plants();
    final String gardenState = jsonEncode(plants
        .map((Plant p) => <String, Object?>{
              'id': p.id,
              'species': p.speciesId,
              'stage': p.stage.name,
              'status': p.status.name,
              'progress': p.growthProgress,
            })
        .toList());

    await _tracking.track(TrackingEvent(
      id: Uuid().v4(),
      name: TrackingEventNames.gardenSnapshot,
      type: TrackingType.milestone,
      ts: now,
      payload: <String, dynamic>{
        'week_no': week,
        'garden_state': gardenState,
      },
    ));
  }

  /// 里程碑（**按 type 去重，一生只写一次**）。
  ///
  /// payload：`{ type: <里程碑类型>, ts: <iso8601> }`，type = milestone。
  /// [type] 取 `prd_params.dart` 的 `kMilestone*Type` 常量（禁止裸字面量）。
  Future<void> recordMilestone(String type, DateTime now) async {
    final List<TrackingEvent> milestones =
        await _tracking.eventsOfType(TrackingType.milestone);
    final bool already =
        milestones.any((TrackingEvent e) =>
            e.name == TrackingEventNames.milestoneEvent &&
            e.payload['type'] == type);
    if (already) return;

    await _tracking.track(TrackingEvent(
      id: Uuid().v4(),
      name: TrackingEventNames.milestoneEvent,
      type: TrackingType.milestone,
      ts: now,
      payload: <String, dynamic>{
        'type': type,
        'ts': now.toIso8601String(),
      },
    ));
  }

  /// 夸夸语录送达：`content_hash = sha256(utf8(content))` 的 hex。
  ///
  /// payload：`{ content_hash: <hex>, ts: <iso8601> }`，type = milestone。
  Future<void> recordPraiseSent(String content, DateTime now) async {
    final String contentHash =
        sha256.convert(utf8.encode(content)).toString();
    await _tracking.track(TrackingEvent(
      id: Uuid().v4(),
      name: TrackingEventNames.praiseSent,
      type: TrackingType.milestone,
      ts: now,
      payload: <String, dynamic>{
        'content_hash': contentHash,
        'ts': now.toIso8601String(),
      },
    ));
  }
}
