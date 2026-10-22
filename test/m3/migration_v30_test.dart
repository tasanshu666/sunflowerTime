/// 迁移回归测试 v29 → v30（**F143：check_ins 加 actual_focus_min 列**，玄参 2026-10-20 拍板）。
///
/// 背景（F143 口径）：联动成长项改为**按专注时长比例结算** ——
/// 「实际专注 ≥ 5 分钟但 < 任务门槛」也算完成、按 `floor(实际×满额/门槛)` 发阳光。
/// 为了让孩子端任务卡与家长端记录能标注「实际 X 分钟 · 完成度 Y%」，
/// `check_ins` 加 `actual_focus_min REAL NULL`：
///  · **null = 未记录** —— 历史行（v30 之前落库）、非联动项手动打卡、pending 行；
///  · 只有**联动专注结算**（含部分完成）才写实际专注分钟。
///
/// 简单加列（无主键变更）→ `_ensureColumn` 幂等 ALTER TABLE ADD COLUMN，无需表重建，
/// schemaVersion 29 → 30。
///
/// 本测试钉死：
///  ① v29 旧库（check_ins v29 形态 DDL + 历史行）→ 迁移后 actual_focus_min 列存在、
///     历史行取 NULL；
///  ② 新装库（v30 直建）直接就有该列；
///  ③ 幂等：二次访问不报错、列仍在、行数不变。
library migration_v30_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// v29 时期 check_ins 表 DDL（**无 actual_focus_min 列**）。
///
/// 列集 = v29 真实 schema：M4（v6）五列 + C90 期 2（v27）child_id。
const String _checkInsV29Ddl = 'CREATE TABLE "check_ins" ('
    '"id" TEXT NOT NULL, '
    '"task_id" TEXT NOT NULL, '
    '"date" INTEGER NOT NULL, '
    '"completed_at" INTEGER NOT NULL, '
    '"session_id" TEXT NULL, '
    '"is_perfect_day" INTEGER NOT NULL, '
    '"status" INTEGER NOT NULL DEFAULT 0, '
    '"sunlight_gross" REAL NOT NULL DEFAULT 0.0, '
    '"sunlight_granted" REAL NOT NULL DEFAULT 0.0, '
    '"resolved_at" INTEGER NULL, '
    '"parent_note" TEXT NULL, '
    '"child_id" TEXT NOT NULL DEFAULT \'$kChildIdDefault\', '
    'PRIMARY KEY ("id"));';

/// 打开一个「v29 旧库」：check_ins（v29 列集）+ 一条历史打卡 +
/// `user_version = 29`，打开即触发 v30 加列迁移（其余表由 onUpgrade 首步
/// `m.createAll()` 幂等补齐）。
Future<db.AppDatabase> _openV29() async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute(_checkInsV29Ddl);
        // 一条历史行（v29 之前的联动自动结算：verified + 应发/实发各 8）。
        // ⚠️ 本仓未开 storeDateTimesAsText，DateTime 落库为 unix 秒 INTEGER。
        rawDb.execute(
          "INSERT INTO check_ins (id, task_id, date, completed_at, session_id, "
          "is_perfect_day, status, sunlight_gross, sunlight_granted, "
          "resolved_at, parent_note, child_id) VALUES ("
          "'c_old', 't_old', 1729000000, 1729000000, 's_old', 0, 0, 8.0, 8.0, "
          "NULL, NULL, '$kChildIdDefault');",
        );
        rawDb.execute('PRAGMA user_version = 29;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get(); // 首次访问触发迁移
  return database;
}

Future<bool> _hasColumn(db.AppDatabase d, String table, String column) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA table_info($table);').get();
  return rows.any((QueryRow r) => r.read<String>('name') == column);
}

Future<int> _countCheckIns(db.AppDatabase d) async =>
    (await d.customSelect('SELECT COUNT(*) AS n FROM check_ins;').getSingle())
        .read<int>('n');

void main() {
  group('迁移 v29->v30：check_ins 加 actual_focus_min 列（F143）', () {
    test('① schemaVersion 必须为最新 30（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV29();
      addTearDown(database.close);
      expect(database.schemaVersion, 30);
    });

    test('② v29 老库升级后 actual_focus_min 列存在，历史行值为 null', () async {
      final db.AppDatabase database = await _openV29();
      addTearDown(database.close);

      expect(
        await _hasColumn(database, 'check_ins', 'actual_focus_min'),
        isTrue,
        reason: 'v30 必须给 check_ins 补 actual_focus_min 列',
      );

      final Map<String, Object?> row = (await database
              .customSelect("SELECT * FROM check_ins WHERE id = 'c_old';")
              .getSingle())
          .data;
      expect(row['actual_focus_min'], isNull,
          reason: '历史行 = 未记录（null），绝不能被补成 0 分钟');
      // 迁移只补列，历史业务字段逐位不变。
      expect(row['sunlight_gross'], 8.0);
      expect(row['sunlight_granted'], 8.0);
      expect(row['status'], 0);
      expect(row['session_id'], 's_old');
    });

    test('③ 新装库（v30 直建）：check_ins 直接就有 actual_focus_min 列', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      expect(database.schemaVersion, 30);
      expect(await _hasColumn(database, 'check_ins', 'actual_focus_min'), isTrue);
    });

    test('④ 幂等：二次访问不报错、列仍在、行数不变', () async {
      final db.AppDatabase database = await _openV29();
      addTearDown(database.close);

      final int before = await _countCheckIns(database);
      await database.customSelect('SELECT 1').get();
      expect(await _countCheckIns(database), before,
          reason: '二次访问不得重复建列 / 重复拷贝');
      expect(await _hasColumn(database, 'check_ins', 'actual_focus_min'), isTrue);
    });

    test('⑤ 新列可读可写：DAO 读回的领域实体带 actualFocusMin（null 与值两条路径）',
        () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      final DateTime now = DateTime.now();
      await database.taskDao.insertCheckIn(
        db.CheckInsCompanion.insert(
          id: 'c_partial',
          taskId: 't_focus',
          date: now,
          completedAt: now,
          isPerfectDay: false,
          status: const Value<int>(0),
          sunlightGross: const Value<double>(4.0),
          sunlightGranted: const Value<double>(4.0),
          actualFocusMin: const Value<double?>(10.0),
        ),
      );

      final db.CheckIn? row = await database.taskDao.checkInById('c_partial');
      expect(row, isNotNull);
      expect(row!.actualFocusMin, 10.0);

      // 未写该字段的新行 → null（= 未记录，不是 0）。
      await database.taskDao.insertCheckIn(
        db.CheckInsCompanion.insert(
          id: 'c_plain',
          taskId: 't_plain',
          date: now,
          completedAt: now,
          isPerfectDay: false,
        ),
      );
      expect((await database.taskDao.checkInById('c_plain'))!.actualFocusMin,
          isNull);
    });
  });
}
