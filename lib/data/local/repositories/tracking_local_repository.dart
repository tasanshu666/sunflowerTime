/// 本地埋点仓储（实现 domain 接口，§2.1 / §6 / §8.3）。
///
/// 真实 Drift 实现，替换 M0 的 `TrackingLocalRepositoryStub`（T-A）。
/// 落盘由上层决定，本实现只负责读写与 JSONL 序列化。
library tracking_local_repository;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';

class TrackingLocalRepository implements TrackingRepository {
  final db.AppDatabase _db;

  TrackingLocalRepository(this._db);

  @override
  Future<void> track(TrackingEvent event) => _db.trackingEventDao.insert(
        db.TrackingEventsCompanion(
          id: Value(event.id),
          name: Value(event.name),
          type: Value(event.type.index),
          ts: Value(event.ts),
          payload: Value(jsonEncode(event.payload)),
        ),
      );

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async {
    final List<db.TrackingEvent> rows =
        await _db.trackingEventDao.ofType(type.index);
    return rows.map(_toEvent).toList();
  }

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async {
    final List<db.TrackingEvent> rows =
        await _db.trackingEventDao.inRange(from, to);
    return rows.map(_toJsonLine).join('\n');
  }

  /// 单行序列化为 JSON 字符串（供 JSONL 拼接）。
  String _toJsonLine(db.TrackingEvent row) => jsonEncode(<String, dynamic>{
        'id': row.id,
        'name': row.name,
        'type': row.type,
        'ts': row.ts.toIso8601String(),
        'payload': jsonDecode(row.payload) as Map<String, dynamic>,
      });

  TrackingEvent _toEvent(db.TrackingEvent row) => TrackingEvent(
        id: row.id,
        name: row.name,
        type: TrackingType.values[row.type],
        ts: row.ts,
        payload: jsonDecode(row.payload) as Map<String, dynamic>,
      );
}
