/// 迁移回归测试 v26 → v27（**C90 期 2：六表加 child_id 列**，玄参 2026-10-17）。
///
/// 背景（C90 期 2 拍板口径）：数据按「当前孩子」隔离第一批 —— 六张「简单加列即可」
/// 的业务表各新增 `child_id` TEXT NOT NULL DEFAULT 'single-child'：
/// plants / focus_sessions / sunlight_ledgers / tasks / check_ins / eye_care_logs。
/// 历史行全部归属默认孩子 `kChildIdDefault`（= 'single-child'，老用户升级无缝）。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion == 27`；
///  ② v26 旧库（六表 v26 形态 DDL + 历史行）→ 迁移后六表**新列全部 = 'single-child'**；
///  ③ 历史行可读、字段值逐位不变；
///  ④ 新插入行不指定 childId 时落列默认值；
///  ⑤ 幂等：二次访问不报错（_ensureColumn 幂等）；
///  ⑥ 新装库（v27 直建）六列存在且默认值正确。
library migration_v27_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// v26 时期 plants 表 DDL（= 现 schema 减 child_id）。
const String _plantsV26Ddl = 'CREATE TABLE "plants" ('
    '"id" TEXT NOT NULL, "species_id" TEXT NOT NULL, '
    '"pot_index" INTEGER NOT NULL, "stage" INTEGER NOT NULL, '
    '"stage_started_at" INTEGER NOT NULL, '
    '"growth_progress" REAL NOT NULL DEFAULT 0.0, '
    '"growth_factor" REAL NOT NULL DEFAULT 1.0, '
    '"water_used" INTEGER NOT NULL DEFAULT 0, '
    '"fertilizer_used" INTEGER NOT NULL DEFAULT 0, '
    '"status" INTEGER NOT NULL, "planted_at" INTEGER NOT NULL, '
    '"last_water_at" INTEGER NULL, "wilted_at" INTEGER NULL, '
    '"dead_at" INTEGER NULL, "bloomed_at" INTEGER NULL, '
    '"bloom_count" INTEGER NOT NULL DEFAULT 0, "mood" INTEGER NOT NULL DEFAULT 0, '
    '"weed_at" INTEGER NULL, "pest_at" INTEGER NULL, '
    '"weed_pest_roll_day" INTEGER NULL, '
    '"shovel_refund" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));';

/// v26 时期 focus_sessions 表 DDL。
const String _focusV26Ddl = 'CREATE TABLE "focus_sessions" ('
    '"id" TEXT NOT NULL, "start" INTEGER NOT NULL, "end" INTEGER NULL, '
    '"planned_min" INTEGER NOT NULL, "actual_focus_min" REAL NOT NULL, '
    '"status" INTEGER NOT NULL, "sunlight_earned" REAL NOT NULL, '
    '"created_at" INTEGER NOT NULL, PRIMARY KEY ("id"));';

/// v26 时期 sunlight_ledgers 表 DDL。
const String _ledgersV26Ddl = 'CREATE TABLE "sunlight_ledgers" ('
    '"id" TEXT NOT NULL, "ts" INTEGER NOT NULL, "type" INTEGER NOT NULL, '
    '"gross" REAL NOT NULL, "net" REAL NOT NULL, '
    '"balance_after" REAL NOT NULL, "ref_type" TEXT NULL, "ref_id" TEXT NULL, '
    '"day_key" TEXT NOT NULL, PRIMARY KEY ("id"));';

/// v26 时期 tasks 表 DDL。
const String _tasksV26Ddl = 'CREATE TABLE "tasks" ('
    '"id" TEXT NOT NULL, "name" TEXT NOT NULL, "subject" INTEGER NOT NULL, '
    '"custom_subject" TEXT NULL, "requires_focus" INTEGER NOT NULL, '
    '"min_focus_min" INTEGER NOT NULL DEFAULT 15, '
    '"sunlight_reward" INTEGER NOT NULL DEFAULT 12, '
    '"repeat_rule" TEXT NULL, "is_custom" INTEGER NOT NULL, '
    '"category" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));';

/// v26 时期 check_ins 表 DDL。
const String _checkInsV26Ddl = 'CREATE TABLE "check_ins" ('
    '"id" TEXT NOT NULL, "task_id" TEXT NOT NULL, "date" INTEGER NOT NULL, '
    '"completed_at" INTEGER NOT NULL, "session_id" TEXT NULL, '
    '"is_perfect_day" INTEGER NOT NULL, '
    '"status" INTEGER NOT NULL DEFAULT 0, '
    '"sunlight_gross" REAL NOT NULL DEFAULT 0.0, '
    '"sunlight_granted" REAL NOT NULL DEFAULT 0.0, '
    '"resolved_at" INTEGER NULL, "parent_note" TEXT NULL, PRIMARY KEY ("id"));';

/// v26 时期 eye_care_logs 表 DDL。
const String _eyeCareV26Ddl = 'CREATE TABLE "eye_care_logs" ('
    '"id" TEXT NOT NULL, "ts" INTEGER NOT NULL, "day_key" TEXT NOT NULL, '
    '"result" TEXT NOT NULL, "watched_seconds" INTEGER NOT NULL, '
    '"source" TEXT NOT NULL, PRIMARY KEY ("id"));';

/// 打开一个「v26 旧库」：六张目标表（v26 列集，无 child_id）+ 历史行 +
/// `user_version = 26`，打开即触发 v27 迁移（六列经 _ensureColumn 幂等补齐；
/// 其余表由 onUpgrade 首步 `m.createAll()` 幂等补齐）。
Future<db.AppDatabase> _openV26() async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute(_plantsV26Ddl);
        rawDb.execute(_focusV26Ddl);
        rawDb.execute(_ledgersV26Ddl);
        rawDb.execute(_tasksV26Ddl);
        rawDb.execute(_checkInsV26Ddl);
        rawDb.execute(_eyeCareV26Ddl);
        // 每表各一条历史行（最小列集，其余列吃 DDL 默认值）。
        // ⚠️ 本仓未开 storeDateTimesAsText，DateTime 落库为 unix 秒 INTEGER。
        rawDb.execute("INSERT INTO plants (id, species_id, pot_index, stage, "
            "stage_started_at, status, planted_at) VALUES "
            "('p1', 'sunflower', 0, 0, 1729000000, 0, 1729000000);");
        rawDb.execute("INSERT INTO focus_sessions (id, start, planned_min, "
            "actual_focus_min, status, sunlight_earned, created_at) VALUES "
            "('f1', 1729000000, 25, 25.0, 1, 12.0, 1729000100);");
        rawDb.execute("INSERT INTO sunlight_ledgers (id, ts, type, gross, net, "
            "balance_after, ref_type, ref_id, day_key) VALUES "
            "('l1', 1729000000, 0, 12.0, 12.0, 12.0, 'task_checkin', 't1', "
            "'2026-10-10');");
        rawDb.execute("INSERT INTO tasks (id, name, subject, requires_focus, "
            "is_custom) VALUES ('t1', '阅读 20 分钟', 0, 0, 0);");
        rawDb.execute("INSERT INTO check_ins (id, task_id, date, completed_at, "
            "is_perfect_day) VALUES ('c1', 't1', 1729000000, 1729000100, 0);");
        rawDb.execute("INSERT INTO eye_care_logs (id, ts, day_key, result, "
            "watched_seconds, source) VALUES "
            "('e1', 1729000000, '2026-10-10', 'completed', 60, 'inSession');");
        rawDb.execute('PRAGMA user_version = 26;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get(); // 首次访问触发迁移
  return database;
}

/// 某表 child_id 列取值集合（历史行应恰为 {'single-child'}）。
Future<Set<String>> _childIds(db.AppDatabase d, String table) async {
  final List<QueryRow> rows =
      await d.customSelect('SELECT child_id AS c FROM $table;').get();
  return rows.map((QueryRow r) => r.read<String>('c')).toSet();
}

Future<bool> _hasColumn(db.AppDatabase d, String table, String column) async {
  final List<QueryRow> rows = await d
      .customSelect('PRAGMA table_info($table);')
      .get();
  return rows.any((QueryRow r) => r.read<String>('name') == column);
}

void main() {
  group('迁移 v26->v27：六表加 child_id（C90 期 2）', () {
    test('① schemaVersion 必须为最新 27（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV26();
      addTearDown(database.close);
      expect(database.schemaVersion, 30);
    });

    test('② 六表均补出 child_id 列，历史行全部 = kChildIdDefault', () async {
      final db.AppDatabase database = await _openV26();
      addTearDown(database.close);

      const List<String> tables = <String>[
        'plants',
        'focus_sessions',
        'sunlight_ledgers',
        'tasks',
        'check_ins',
        'eye_care_logs',
      ];
      for (final String t in tables) {
        expect(await _hasColumn(database, t, 'child_id'), isTrue,
            reason: 'v27 必须给 $t 补 child_id 列');
        expect(await _childIds(database, t), <String>{kChildIdDefault},
            reason: '$t 历史行必须默认归属默认孩子（老用户升级数据无缝）');
      }
    });

    test('③ 历史行可读、字段值逐位不变', () async {
      final db.AppDatabase database = await _openV26();
      addTearDown(database.close);

      final Map<String, Object?> p =
          (await database.customSelect("SELECT * FROM plants WHERE id = 'p1';")
              .getSingle())
          .data;
      expect(p['species_id'], 'sunflower');
      expect(p['stage'], 0);
      expect(p['status'], 0);
      expect(p['shovel_refund'], 0);
      expect(p['child_id'], 'single-child');

      final Map<String, Object?> f = (await database
              .customSelect("SELECT * FROM focus_sessions WHERE id = 'f1';")
              .getSingle())
          .data;
      expect(f['planned_min'], 25);
      expect(f['actual_focus_min'], 25.0);
      expect(f['sunlight_earned'], 12.0);
      expect(f['child_id'], 'single-child');

      final Map<String, Object?> l = (await database
              .customSelect("SELECT * FROM sunlight_ledgers WHERE id = 'l1';")
              .getSingle())
          .data;
      expect(l['ref_type'], 'task_checkin');
      expect(l['balance_after'], 12.0);
      expect(l['day_key'], '2026-10-10');
      expect(l['child_id'], 'single-child');

      final Map<String, Object?> t =
          (await database.customSelect("SELECT * FROM tasks WHERE id = 't1';")
              .getSingle())
          .data;
      expect(t['name'], '阅读 20 分钟');
      expect(t['subject'], 0);
      expect(t['is_custom'], 0);
      expect(t['child_id'], 'single-child');

      final Map<String, Object?> c = (await database
              .customSelect("SELECT * FROM check_ins WHERE id = 'c1';")
              .getSingle())
          .data;
      expect(c['task_id'], 't1');
      expect(c['is_perfect_day'], 0);
      expect(c['status'], 0, reason: '历史打卡必须保持「已核销」（v6 口径不变）');
      expect(c['child_id'], 'single-child');

      final Map<String, Object?> e = (await database
              .customSelect("SELECT * FROM eye_care_logs WHERE id = 'e1';")
              .getSingle())
          .data;
      expect(e['result'], 'completed');
      expect(e['watched_seconds'], 60);
      expect(e['source'], 'inSession');
      expect(e['child_id'], 'single-child');
    });

    test('④ 经 drift 查询读回历史行成功（迁移后表结构可被正常访问）', () async {
      final db.AppDatabase database = await _openV26();
      addTearDown(database.close);

      final db.Plant? plant = await (database.select(database.plants)
            ..where((t) => t.id.equals('p1')))
          .getSingleOrNull();
      expect(plant, isNotNull);
      expect(plant!.speciesId, 'sunflower');
      expect(plant.childId, kChildIdDefault);

      final db.Task? task = await (database.select(database.tasks)
            ..where((t) => t.id.equals('t1')))
          .getSingleOrNull();
      expect(task, isNotNull);
      expect(task!.name, '阅读 20 分钟');
      expect(task.childId, kChildIdDefault);

      final db.CheckIn? checkIn = await (database.select(database.checkIns)
            ..where((t) => t.id.equals('c1')))
          .getSingleOrNull();
      expect(checkIn, isNotNull);
      expect(checkIn!.childId, kChildIdDefault);

      final db.SunlightLedger? ledger =
          await (database.select(database.sunlightLedgers)
                ..where((t) => t.id.equals('l1')))
              .getSingleOrNull();
      expect(ledger, isNotNull);
      expect(ledger!.childId, kChildIdDefault);

      final db.FocusSession? session =
          await (database.select(database.focusSessions)
                ..where((t) => t.id.equals('f1')))
              .getSingleOrNull();
      expect(session, isNotNull);
      expect(session!.childId, kChildIdDefault);

      final db.EyeCareLogRow? eyeCare =
          await (database.select(database.eyeCareLogs)
                ..where((t) => t.id.equals('e1')))
              .getSingleOrNull();
      expect(eyeCare, isNotNull);
      expect(eyeCare!.childId, kChildIdDefault);
    });

    test('⑤ 幂等：二次访问不报错、无重复建列', () async {
      final db.AppDatabase database = await _openV26();
      addTearDown(database.close);

      await database.customSelect('SELECT COUNT(*) FROM plants;').getSingle();
      await database.customSelect('SELECT COUNT(*) FROM eye_care_logs;')
          .getSingle();
      expect(await _childIds(database, 'plants'), <String>{kChildIdDefault});
    });

    test('⑥ 新装库（v27 直建）六列存在，不指定 childId 的写入落默认值', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      expect(database.schemaVersion, 30);

      await database.plantDao.upsert(
        db.PlantsCompanion.insert(
          id: 'p_new',
          speciesId: 'sunflower',
          potIndex: 0,
          stage: 0,
          stageStartedAt: DateTime.fromMillisecondsSinceEpoch(
            1729000000 * 1000,
          ),
          status: 0,
          plantedAt: DateTime.fromMillisecondsSinceEpoch(1729000000 * 1000),
        ),
      );
      await database.eyeCareLogDao.appendRow(
        db.EyeCareLogsCompanion.insert(
          id: 'e_new',
          ts: DateTime.fromMillisecondsSinceEpoch(1729000000 * 1000),
          dayKey: '2026-10-10',
          result: 'completed',
          watchedSeconds: 60,
          source: 'inSession',
        ),
      );

      expect(await _childIds(database, 'plants'), <String>{kChildIdDefault});
      expect(
          await _childIds(database, 'eye_care_logs'), <String>{kChildIdDefault});
    });
  });
}
