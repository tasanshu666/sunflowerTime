/// 迁移回归测试 v7 → v8（§5 验收证据）：**plants 新增 bloomed_at 列（花谢循环计时起点）**。
///
/// 背景（玄参大人 2026-09-23 拍板「花谢循环」玩法）：成株盛开 [kBloomDurationDays] 天后
/// 花朵凋谢、退回成株(growing)，由时间/养护重新养满后再度盛开。需要记录每次进入盛开的
/// 时刻 → 在 [Plant] 实体与 `plants` 表新增可空 `bloomed_at` 列（unix 秒 INTEGER）。
///
/// 本测试钉死四件事（**必须把历史行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 8`；
///  ② v7 → v8 后 `plants` 表存在 `bloomed_at` 列（PRAGMA table_info 验证）；
///  ③ 历史植物（growing / bloomed / wilting / dead）的**其它字段原样保留**，`bloomed_at` 取 NULL
///     （老库无此列，ALERT TABLE ADD COLUMN 后历史行默认 NULL，首次 tick 自动补计时）；
///  ④ 幂等：已迁移到 v8 的库重复打开不报错、列仍在、数据不丢；
///     以及跨版本跳跃（6→8）也要覆盖（中间版本 v7 的清零逻辑仍须执行 + v8 补列）。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**，
///    故「老库」DDL 的日期列一律用 `INTEGER`（秒），否则读回会因类型不匹配而失败。
library migration_v7_to_v8_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

final DateTime _legacyStageStarted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyPlanted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyBloomedStarted = DateTime(2026, 8, 20, 10, 0);
final DateTime _legacyWiltingStarted = DateTime(2026, 8, 25, 12, 0);
final DateTime _legacyDeadStarted = DateTime(2026, 8, 10, 9, 0);

/// 按版本特征拼「老库」建表 DDL。v7 与 v6 的 plants 表结构一致（v7 只跑了一次
/// 进度重置 UPDATE，未改 schema），故这里给出 v7 的 plants（**无** bloomed_at 列）。
List<String> _schemaDdl({required bool withLegacyPlants}) {
  return <String>[
    'CREATE TABLE settings ('
        'id INTEGER NOT NULL, '
        'age_tier INTEGER NOT NULL, '
        'night_boundary_hour INTEGER NOT NULL DEFAULT 21, '
        'night_boundary_minute INTEGER NOT NULL DEFAULT 0, '
        'daily_focus_cap INTEGER NOT NULL, '
        'daily_app_cap_minutes INTEGER NOT NULL, '
        'rest_after_sessions INTEGER NOT NULL, '
        'rest_minutes INTEGER NOT NULL, '
        'task_sunlight INTEGER NOT NULL, '
        'monthly_pool_budget INTEGER NOT NULL, '
        'quiet_mode INTEGER NOT NULL DEFAULT 0, '
        'sound_on INTEGER NOT NULL DEFAULT 1, '
        'bgm_on INTEGER NOT NULL DEFAULT 0, '
        'detection_on INTEGER NOT NULL DEFAULT 1, '
        'auto_confirm_single_high INTEGER NOT NULL DEFAULT 130, '
        'auto_confirm_single_low INTEGER NOT NULL DEFAULT 50, '
        'auto_confirm_monthly_pct REAL NOT NULL DEFAULT 0.25, '
        'currency_rate REAL NOT NULL DEFAULT 0.25, '
        'theme_dark INTEGER NOT NULL DEFAULT 1, '
        'autonomous_mode INTEGER NOT NULL DEFAULT 0, '
        'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, '
        'PRIMARY KEY (id));',
    'CREATE TABLE plants ('
        'id TEXT NOT NULL, '
        'species_id TEXT NOT NULL, '
        'pot_index INTEGER NOT NULL, '
        'stage INTEGER NOT NULL, '
        'stage_started_at INTEGER NOT NULL, ' // ← v7 无 bloomed_at（v8 才加）
        'growth_progress REAL NOT NULL DEFAULT 0.0, '
        'growth_factor REAL NOT NULL DEFAULT 1.0, '
        'water_used INTEGER NOT NULL DEFAULT 0, '
        'fertilizer_used INTEGER NOT NULL DEFAULT 0, '
        'status INTEGER NOT NULL, '
        'planted_at INTEGER NOT NULL, '
        'last_water_at INTEGER, '
        'wilted_at INTEGER, '
        'dead_at INTEGER, '
        'mood INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (id));',
    'CREATE TABLE focus_sessions ('
        'id TEXT NOT NULL, start INTEGER NOT NULL, end INTEGER, '
        'planned_min INTEGER NOT NULL, actual_focus_min REAL NOT NULL, '
        'status INTEGER NOT NULL, sunlight_earned REAL NOT NULL, '
        'created_at INTEGER NOT NULL, PRIMARY KEY (id));',
    'CREATE TABLE sunlight_ledgers ('
        'id TEXT NOT NULL, ts INTEGER NOT NULL, type INTEGER NOT NULL, '
        'gross REAL NOT NULL, net REAL NOT NULL, balance_after REAL NOT NULL, '
        'ref_type TEXT, ref_id TEXT, day_key TEXT NOT NULL, PRIMARY KEY (id));',
    'CREATE TABLE reward_templates ('
        'id TEXT NOT NULL, name TEXT NOT NULL, category INTEGER NOT NULL, '
        'base_cost INTEGER NOT NULL DEFAULT 50, freq_limit INTEGER, '
        'cooldown_rule INTEGER NOT NULL DEFAULT 1, enabled INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id));',
    'CREATE TABLE redemption_requests ('
        'id TEXT NOT NULL, template_id TEXT NOT NULL, requested_at INTEGER NOT NULL, '
        'cost INTEGER NOT NULL, status INTEGER NOT NULL, auto_approved INTEGER NOT NULL DEFAULT 0, '
        'queue_position INTEGER, verified_at INTEGER, parent_note TEXT, '
        'child_id TEXT NOT NULL DEFAULT \'single-child\', PRIMARY KEY (id));',
    'CREATE TABLE monthly_pools ('
        'month_key TEXT NOT NULL, budget INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0, '
        'auto_released INTEGER NOT NULL DEFAULT 0, reset_at INTEGER NOT NULL, PRIMARY KEY (month_key));',
    'CREATE TABLE tasks ('
        'id TEXT NOT NULL, name TEXT NOT NULL, subject INTEGER NOT NULL, '
        'custom_subject TEXT, requires_focus INTEGER NOT NULL, '
        'min_focus_min INTEGER NOT NULL DEFAULT 15, sunlight_reward INTEGER NOT NULL DEFAULT 12, '
        'repeat_rule TEXT, is_custom INTEGER NOT NULL, PRIMARY KEY (id));',
    'CREATE TABLE check_ins ('
        'id TEXT NOT NULL, task_id TEXT NOT NULL, date INTEGER NOT NULL, '
        'completed_at INTEGER NOT NULL, session_id TEXT, is_perfect_day INTEGER NOT NULL, '
        'status INTEGER NOT NULL DEFAULT 0, sunlight_gross REAL NOT NULL DEFAULT 0.0, '
        'sunlight_granted REAL NOT NULL DEFAULT 0.0, resolved_at INTEGER, '
        'parent_note TEXT, PRIMARY KEY (id));',
    'CREATE TABLE cooldown_counters ('
        'template_id TEXT NOT NULL, period INTEGER NOT NULL, used_count INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (template_id, period));',
    'CREATE TABLE tracking_events ('
        'id TEXT NOT NULL, name TEXT NOT NULL DEFAULT \'\', type INTEGER NOT NULL, '
        'ts INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY (id));',
    if (withLegacyPlants) ...<String>[
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, mood) '
          'VALUES (\'p_growing\', \'species_sunflower\', 0, '
          '${PlantStage.adult.index}, ${_secs(_legacyStageStarted)}, 0.6, 1.0, '
          '1, 1, ${PlantStatus.growing.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, 0);',
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, mood) '
          'VALUES (\'p_bloomed\', \'species_daisy\', 1, '
          '${PlantStage.adult.index}, ${_secs(_legacyBloomedStarted)}, 1.0, 1.0, '
          '1, 1, ${PlantStatus.bloomed.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, 0);',
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, mood) '
          'VALUES (\'p_wilting\', \'species_cactus\', 2, '
          '${PlantStage.sprout.index}, ${_secs(_legacyWiltingStarted)}, 0.35, '
          '1.0, 0, 0, ${PlantStatus.wilting.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, ${_secs(_legacyWiltingStarted)}, NULL, 2);',
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, mood) '
          'VALUES (\'p_dead\', \'species_sunflower\', 3, '
          '${PlantStage.seed.index}, ${_secs(_legacyDeadStarted)}, 0.1, 1.0, '
          '0, 0, ${PlantStatus.dead.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, ${_secs(_legacyDeadStarted)}, 0);',
    ],
  ];
}

/// 读取某表当前所有列名（PRAGMA table_info）。
Future<Set<String>> _columns(db.AppDatabase database, String table) async {
  final List<QueryRow> rows =
      await database.customSelect('PRAGMA table_info($table);').get();
  return rows.map((QueryRow r) => r.read<String>('name')).toSet();
}

/// 手工构造「老库」并让 AppDatabase 触发迁移（内存库）。
Future<db.AppDatabase> _openMigrated(
  List<String> legacyDdl,
  int userVersion,
) async {
  final NativeDatabase executor = NativeDatabase.memory(
    setup: (rawDb) {
      for (final String sql in legacyDdl) {
        rawDb.execute(sql);
      }
      rawDb.execute('PRAGMA user_version = $userVersion;');
    },
  );
  final db.AppDatabase database = db.AppDatabase(executor);
  await database.customSelect('SELECT 1').get(); // 触发迁移
  addTearDown(() => database.close());
  return database;
}

void main() {
  group('迁移 v7->v8：plants 新增 bloomed_at 列（花谢循环计时）', () {
    test('schemaVersion 必须为 8（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyPlants: true),
        7,
      );
      expect(database.schemaVersion, 8);
    });

    test('plants 表迁移后出现 bloomed_at 列', () async {
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyPlants: true),
        7,
      );
      final Set<String> cols = await _columns(database, 'plants');
      expect(cols, contains('bloomed_at'));
    });

    test('历史植物其它字段原样保留，bloomed_at 取 NULL', () async {
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyPlants: true),
        7,
      );

      final db.Plant bloomed = (await database.plantDao.byId('p_bloomed'))!;
      expect(bloomed.status, PlantStatus.bloomed.index);
      expect(bloomed.stage, PlantStage.adult.index);
      expect(bloomed.growthProgress, 1.0);
      expect(bloomed.speciesId, 'species_daisy');
      expect(bloomed.bloomedAt, isNull,
          reason: '老库无 bloomed_at 列，历史行应取 NULL');

      final db.Plant growing = (await database.plantDao.byId('p_growing'))!;
      expect(growing.status, PlantStatus.growing.index);
      expect(growing.growthProgress, 0.6);
      expect(growing.bloomedAt, isNull);

      final db.Plant wilting = (await database.plantDao.byId('p_wilting'))!;
      expect(wilting.status, PlantStatus.wilting.index);
      expect(wilting.bloomedAt, isNull);

      final db.Plant dead = (await database.plantDao.byId('p_dead'))!;
      expect(dead.status, PlantStatus.dead.index);
      expect(dead.bloomedAt, isNull);
    });

    test('迁移后 DAO 可写入/读回带 bloomedAt 的植物（往返不炸）', () async {
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyPlants: false),
        7,
      );
      final DateTime t = DateTime(2026, 9, 23, 12, 0);
      await database.plantDao.upsert(
        db.PlantsCompanion(
          id: const Value('p_new'),
          speciesId: const Value('species_sunflower'),
          potIndex: const Value(0),
          stage: Value(PlantStage.adult.index),
          stageStartedAt: Value(t),
          growthProgress: const Value(1.0),
          status: Value(PlantStatus.bloomed.index),
          plantedAt: Value(t),
          bloomedAt: Value(t),
        ),
      );
      final db.Plant p = (await database.plantDao.byId('p_new'))!;
      expect(p.status, PlantStatus.bloomed.index);
      expect(p.bloomedAt, t);
    });
  });

  group('幂等：已迁移到 v8 的库重复打开不报错、不丢数据', () {
    test('重新打开文件库：bloomed_at 列仍在、历史行原样保留', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v8');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _schemaDdl(withLegacyPlants: true)) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 7;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 8);
      expect(await _columns(first, 'plants'), contains('bloomed_at'));
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();

      final Set<String> cols = await _columns(second, 'plants');
      expect(cols, contains('bloomed_at'));
      expect((await second.plantDao.byId('p_bloomed'))!.status,
          PlantStatus.bloomed.index);
      expect((await second.plantDao.byId('p_wilting'))!.status,
          PlantStatus.wilting.index);
    });
  });

  group('跨版本跳跃升级', () {
    test('v6 → v8：v7 清零逻辑仍执行 + v8 补列', () async {
      // 用 v6 的 plants（同样无 bloomed_at）模拟从 v6 直接升到 v8。
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyPlants: true),
        6,
      );
      expect(database.schemaVersion, 8);

      // ① v7 的清零分支（from<7）执行：growing 植物被清零。
      final db.Plant growing = (await database.plantDao.byId('p_growing'))!;
      expect(growing.stage, PlantStage.seed.index);
      expect(growing.growthProgress, 0.0);

      // ② v8 补列分支执行：bloomed_at 列存在。
      expect(await _columns(database, 'plants'), contains('bloomed_at'));

      // ③ 非 growing 植物不受影响。
      expect((await database.plantDao.byId('p_bloomed'))!.growthProgress, 1.0);
      expect((await database.plantDao.byId('p_dead'))!.growthProgress, 0.1);
    });
  });
}
