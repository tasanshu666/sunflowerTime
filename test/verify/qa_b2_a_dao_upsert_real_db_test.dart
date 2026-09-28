/// 独立复验探针 A（qa-verify2）：`BloomRewardDao.insertPending` 崩溃根因是否真被消除，
/// 且**没有掩盖真 bug**。
///
/// 全部断言跑在**真实 Drift 库**（`NativeDatabase.memory()`）上——不是工程内存 Fake，
/// 与玄参在 iOS 模拟器上实测崩溃的路径同源（真实 SQLite 主键约束）。
///
/// 覆盖：
///  ① 根因存在性：直接裸 `INSERT` 同 id 二次写 → 真实抛 `UNIQUE constraint failed`
///     （证明表上确有 PK 约束，历史缺陷成立，不是臆测）；
///  ② 修法有效：走仓储 `insertPendingBloomReward`（现为 `insertOnConflictUpdate`）
///     同 id 二次写（改 `due_at`）→ **不抛**、表里**只剩 1 行**、`due_at` 被覆盖为新值；
///  ③ 反向质疑（防「用 upsert 掩盖重复登记」）：把同 id 覆盖写当正常路径后，
///     必须证明「同一株一次盛开恰好 2 条、重复 tick 不新增、已领取不被重新写回」
///     ——见 `qa_b2_service_real_db_test.dart` 的 A 组（那里用真实服务 + 真实库）。
library qa_b2_a_dao_upsert_real_db_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:test/test.dart';

/// 全新真实内存库（drift 首次访问即按 schemaVersion=11 建全表）。
Future<db.AppDatabase> _fresh() async {
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  await database.customSelect('SELECT 1').get(); // 触发建表
  addTearDown(() => database.close());
  return database;
}

/// 某表行数（真实 SQL 计数）。
Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row =
      await database.customSelect('SELECT COUNT(*) AS c FROM $table;').getSingle();
  return row.read<int>('c');
}

/// 某 pending 行的 due_at（真实 SQL 读回，unix 秒）。
Future<int> _dueAtSec(db.AppDatabase database, String id) async {
  final QueryRow row = await database
      .customSelect('SELECT due_at AS d FROM pending_bloom_rewards WHERE id = ?;',
          variables: <Variable>[Variable.withString(id)])
      .getSingle();
  return row.read<int>('d');
}

const String _insertSql =
    'INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed) '
    'VALUES (?, ?, ?, ?, 0);';

void main() {
  group('A · 根因存在：真实 SQLite 主键约束会拒绝同 id 二次裸 INSERT', () {
    test('裸 INSERT 同 id 两次 → 第二次抛异常（历史崩溃根因成立）', () async {
      final db.AppDatabase database = await _fresh();

      await database.customStatement(
          _insertSql, <Object?>['dup', 'p1', 1000, 'instant']);
      expect(await _count(database, 'pending_bloom_rewards'), 1);

      // 第二次同 id：应抛（SQLITE_CONSTRAINT UNIQUE，错误码 1555 / 2067）。
      await expectLater(
        database.customStatement(
            _insertSql, <Object?>['dup', 'p1', 2000, 'instant']),
        throwsA(anything),
        reason: '真实库上同 id 裸 INSERT 必须失败 —— 这是玄参实测崩溃的根因',
      );

      // 失败后表仍只有 1 行、due_at 仍是旧值（证明「改 due_at」确实被拒）。
      expect(await _count(database, 'pending_bloom_rewards'), 1);
      expect(await _dueAtSec(database, 'dup'), 1000);
    });
  });

  group('A · 修法有效：仓储 upsert 同 id 二次写安全、幂等、覆盖 due_at', () {
    test('insertPendingBloomReward 同 id 二写（改 due_at）→ 不抛 + 仅 1 行 + 值被覆盖',
        () async {
      final db.AppDatabase database = await _fresh();
      final PlantLocalRepository repo = PlantLocalRepository(database);

      final DateTime due1 = DateTime(2026, 9, 27, 8, 0, 0);
      final DateTime due2 = DateTime(2026, 9, 27, 20, 30, 0); // 调试面板改到「已到期」

      await repo.insertPendingBloomReward(PendingBloomReward(
        id: 'x1',
        plantId: 'p1',
        dueAt: due1,
        rewardKind: 'instant',
      ));
      // 同 id 覆盖写：历史缺陷路径。修好后不得抛。
      await repo.insertPendingBloomReward(PendingBloomReward(
        id: 'x1',
        plantId: 'p1',
        dueAt: due2,
        rewardKind: 'instant',
      ));

      expect(await _count(database, 'pending_bloom_rewards'), 1,
          reason: '同 id 覆盖写只应留 1 行');
      // drift 未开 storeDateTimesAsText → 落库为 unix 秒。
      expect(await _dueAtSec(database, 'x1'),
          due2.millisecondsSinceEpoch ~/ 1000,
          reason: 'due_at 必须被覆盖为新值（调试面板「让奖励可领取」依赖此语义）');
    });

    test('连续多次同 id 覆盖写（模拟反复点击调试按钮）→ 始终 1 行、不抛', () async {
      final db.AppDatabase database = await _fresh();
      final PlantLocalRepository repo = PlantLocalRepository(database);

      for (int i = 0; i < 10; i++) {
        await repo.insertPendingBloomReward(PendingBloomReward(
          id: 'y1',
          plantId: 'p1',
          dueAt: DateTime(2026, 9, 27, 8 + i),
          rewardKind: 'instant',
        ));
      }
      expect(await _count(database, 'pending_bloom_rewards'), 1);
    });

    test('不同 id 各自成行（upsert 不得误合并不同记录）', () async {
      final db.AppDatabase database = await _fresh();
      final PlantLocalRepository repo = PlantLocalRepository(database);

      await repo.insertPendingBloomReward(PendingBloomReward(
          id: 'a', plantId: 'p1', dueAt: DateTime(2026, 9, 27, 8), rewardKind: 'instant'));
      await repo.insertPendingBloomReward(PendingBloomReward(
          id: 'b', plantId: 'p1', dueAt: DateTime(2026, 9, 29, 8), rewardKind: 'normal'));

      expect(await _count(database, 'pending_bloom_rewards'), 2);
    });
  });
}
