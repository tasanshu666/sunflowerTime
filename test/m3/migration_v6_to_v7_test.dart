/// 迁移回归测试 v6 → v7（§5 验收证据）：**植物成长 V2 → 成长中植物全部重置清零**。
///
/// 背景（为什么必须重置）：V2 修掉了 `_advanceGrowth` 的成长进度**重复累加**（非幂等）
/// bug——旧实现里 `stage_started_at` 只在跨阶段时更新，于是每次 tick 都会把
/// 「stage_started_at → now」整段时间重新加到已有进度上，真机表现为「浇水标注
/// +12%、实际阶段进度跳 21%」。旧进度是按旧的 24h/阶段 + 非幂等累加堆出来的，
/// **数值本身已经不可信、无法与新口径平滑对齐**。玄参大人 2026-09-22 在
/// 「平滑衔接 / 老植物沿用旧参数 / 全部重置清零」三选项中明确选 **全部重置清零**。
///
/// 本测试钉死四件事（**必须把历史行读回来断言**，不能只断言「没抛异常」——本项目
/// 吃过亏：以前只看迁移跑过，导致 DateTime 类型不一致长期没暴露）：
///  ① `AppDatabase.schemaVersion == 7`；
///  ② v6 → v7 后 growing 植物 `stage = seed`、`growth_progress = 0.0`、
///     `stage_started_at` ≈ 迁移时刻，其余字段（species_id / pot_index / planted_at）不丢；
///  ③ bloomed / wilting / dead 植物**字段原样不受影响**；
///  ④ 幂等：已迁移到 v7 的库重复打开不会报错、不会二次清零；
///     以及相邻版本（6→7）与跨版本跳跃（5→7、3→7）都要覆盖。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**，
///    故「老库」DDL 的日期列一律用 `INTEGER`（秒），否则读回会因类型不匹配而失败。
library migration_v6_to_v7_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// 历史植物的旧时间戳（远早于迁移时刻，便于断言 stage_started_at 被推进）。
final DateTime _legacyStageStarted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyPlanted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyBloomedStarted = DateTime(2026, 8, 20, 10, 0);
final DateTime _legacyWiltingStarted = DateTime(2026, 8, 25, 12, 0);
final DateTime _legacyDeadStarted = DateTime(2026, 8, 10, 9, 0);

/// 按版本特征拼「老库」建表 DDL。
///
/// 五个开关对应各代 schema 的增量，组合即可还原 v3 / v5 / v6：
///  · [withPlantsTable] / [withGardenPotCapacity]：M3（v4）新增；
///  · [withCustomSubject]：M3 修订（v5）新增；
///  · [withCheckInColumns]：M4（v6）新增的 check_ins 5 列；
///  · [withLegacyPlants]：预置 4 株历史植物（growing / bloomed / wilting / dead）。
List<String> _schemaDdl({
  required bool withPlantsTable,
  required bool withGardenPotCapacity,
  required bool withCustomSubject,
  required bool withCheckInColumns,
  required bool withLegacyPlants,
}) {
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
        '${withGardenPotCapacity ? 'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, ' : ''}'
        'PRIMARY KEY (id));',
    if (withPlantsTable)
      'CREATE TABLE plants ('
          'id TEXT NOT NULL, '
          'species_id TEXT NOT NULL, '
          'pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, '
          'stage_started_at INTEGER NOT NULL, '
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
        'id TEXT NOT NULL, '
        'start INTEGER NOT NULL, '
        'end INTEGER, '
        'planned_min INTEGER NOT NULL, '
        'actual_focus_min REAL NOT NULL, '
        'status INTEGER NOT NULL, '
        'sunlight_earned REAL NOT NULL, '
        'created_at INTEGER NOT NULL, '
        'PRIMARY KEY (id));',
    'CREATE TABLE sunlight_ledgers ('
        'id TEXT NOT NULL, '
        'ts INTEGER NOT NULL, '
        'type INTEGER NOT NULL, '
        'gross REAL NOT NULL, '
        'net REAL NOT NULL, '
        'balance_after REAL NOT NULL, '
        'ref_type TEXT, '
        'ref_id TEXT, '
        'day_key TEXT NOT NULL, '
        'PRIMARY KEY (id));',
    'CREATE TABLE reward_templates ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'category INTEGER NOT NULL, '
        'base_cost INTEGER NOT NULL DEFAULT 50, '
        'freq_limit INTEGER, '
        'cooldown_rule INTEGER NOT NULL DEFAULT 1, '
        'enabled INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id));',
    'CREATE TABLE redemption_requests ('
        'id TEXT NOT NULL, '
        'template_id TEXT NOT NULL, '
        'requested_at INTEGER NOT NULL, '
        'cost INTEGER NOT NULL, '
        'status INTEGER NOT NULL, '
        'auto_approved INTEGER NOT NULL DEFAULT 0, '
        'queue_position INTEGER, '
        'verified_at INTEGER, '
        'parent_note TEXT, '
        'child_id TEXT NOT NULL DEFAULT \'single-child\', '
        'PRIMARY KEY (id));',
    'CREATE TABLE monthly_pools ('
        'month_key TEXT NOT NULL, '
        'budget INTEGER NOT NULL, '
        'used INTEGER NOT NULL DEFAULT 0, '
        'auto_released INTEGER NOT NULL DEFAULT 0, '
        'reset_at INTEGER NOT NULL, '
        'PRIMARY KEY (month_key));',
    // tasks：v5 起含 custom_subject
    'CREATE TABLE tasks ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'subject INTEGER NOT NULL, '
        '${withCustomSubject ? 'custom_subject TEXT, ' : ''}'
        'requires_focus INTEGER NOT NULL, '
        'min_focus_min INTEGER NOT NULL DEFAULT 15, '
        'sunlight_reward INTEGER NOT NULL DEFAULT 12, '
        'repeat_rule TEXT, '
        'is_custom INTEGER NOT NULL, '
        'PRIMARY KEY (id));',
    // check_ins：v6 起含 5 个核销列；v5 及以前没有。
    'CREATE TABLE check_ins ('
        'id TEXT NOT NULL, '
        'task_id TEXT NOT NULL, '
        'date INTEGER NOT NULL, '
        'completed_at INTEGER NOT NULL, '
        'session_id TEXT, '
        'is_perfect_day INTEGER NOT NULL, '
        '${withCheckInColumns ? 'status INTEGER NOT NULL DEFAULT 0, '
            'sunlight_gross REAL NOT NULL DEFAULT 0.0, '
            'sunlight_granted REAL NOT NULL DEFAULT 0.0, '
            'resolved_at INTEGER, '
            'parent_note TEXT, ' : ''}'
        'PRIMARY KEY (id));',
    'CREATE TABLE cooldown_counters ('
        'template_id TEXT NOT NULL, '
        'period INTEGER NOT NULL, '
        'used_count INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (template_id, period));',
    'CREATE TABLE tracking_events ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL DEFAULT \'\', '
        'type INTEGER NOT NULL, '
        'ts INTEGER NOT NULL, '
        'payload TEXT NOT NULL, '
        'PRIMARY KEY (id));',
    // ── 历史植物：4 株，覆盖四种状态 ──────────────────────────────────────
    if (withLegacyPlants) ...<String>[
      // ① 成长中：应被重置清零。
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, mood) '
          'VALUES (\'p_growing\', \'species_sunflower\', 0, '
          '${PlantStage.adult.index}, ${_secs(_legacyStageStarted)}, 0.6, 1.0, '
          '1, 1, ${PlantStatus.growing.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, 0);',
      // ② 已开花：不受影响。
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, mood) '
          'VALUES (\'p_bloomed\', \'species_daisy\', 1, '
          '${PlantStage.adult.index}, ${_secs(_legacyBloomedStarted)}, 1.0, 1.0, '
          '1, 1, ${PlantStatus.bloomed.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, 0);',
      // ③ 枯萎中：不受影响。
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, mood) '
          'VALUES (\'p_wilting\', \'species_cactus\', 2, '
          '${PlantStage.sprout.index}, ${_secs(_legacyWiltingStarted)}, 0.35, '
          '1.0, 0, 0, ${PlantStatus.wilting.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, ${_secs(_legacyWiltingStarted)}, NULL, 2);',
      // ④ 已死亡：不受影响。
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

/// 某表是否存在（sqlite_master）。
Future<bool> _tableExists(db.AppDatabase database, String table) async {
  final List<QueryRow> rows = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';",
      )
      .get();
  return rows.isNotEmpty;
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
  // 触发迁移：首次访问数据库会执行 onUpgrade。
  await database.customSelect('SELECT 1').get();
  addTearDown(() => database.close());
  return database;
}

/// v6 线上 schema：plants / garden_pot_capacity / custom_subject / check_ins 5 列全在。
List<String> _v6Ddl() => _schemaDdl(
      withPlantsTable: true,
      withGardenPotCapacity: true,
      withCustomSubject: true,
      withCheckInColumns: true,
      withLegacyPlants: true,
    );

/// v5 线上 schema：有 plants / capacity / custom_subject，**无** check_ins 5 列。
List<String> _v5Ddl() => _schemaDdl(
      withPlantsTable: true,
      withGardenPotCapacity: true,
      withCustomSubject: true,
      withCheckInColumns: false,
      withLegacyPlants: true,
    );

/// v3 线上 schema：无 plants 表、无 garden_pot_capacity、无 custom_subject、
/// 无 check_ins 5 列。
List<String> _v3Ddl() => _schemaDdl(
      withPlantsTable: false,
      withGardenPotCapacity: false,
      withCustomSubject: false,
      withCheckInColumns: false,
      withLegacyPlants: false,
    );

void main() {
  group('迁移 v6->v7：植物成长 V2，成长中植物重置清零', () {
    test('schemaVersion 必须为 7（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(_v6Ddl(), 6);
      // 护栏：版本号若停在 6，onUpgrade 不跑，下面所有清零断言都会红。
      expect(database.schemaVersion, 7);
    });

    test('growing 植物：stage 回 seed、progress=0、stage_started_at≈迁移时刻，其余字段不丢',
        () async {
      final DateTime before = DateTime.now();
      final db.AppDatabase database = await _openMigrated(_v6Ddl(), 6);
      final DateTime after = DateTime.now();

      final db.Plant? p = await database.plantDao.byId('p_growing');
      expect(p, isNotNull);

      // ① 清零三件套。
      expect(p!.stage, PlantStage.seed.index);
      expect(p.growthProgress, 0.0);
      // ② stage_started_at 被推进到迁移时刻（既不是旧的 9-01，也不是 1970 年）。
      expect(
        p.stageStartedAt.isAfter(before.subtract(const Duration(seconds: 2))),
        isTrue,
        reason: 'stage_started_at 应≈迁移时刻，实测 ${p.stageStartedAt}（起点 $before）',
      );
      expect(
        p.stageStartedAt.isBefore(after.add(const Duration(seconds: 2))),
        isTrue,
        reason: 'stage_started_at 不应超过迁移时刻，实测 ${p.stageStartedAt}',
      );
      expect(p.stageStartedAt.isAfter(_legacyStageStarted), isTrue);

      // ③ 其余字段不丢（只重置成长三件套，不动身份/花盆/种植时间）。
      expect(p.speciesId, 'species_sunflower');
      expect(p.potIndex, 0);
      expect(p.plantedAt, _legacyPlanted);
      expect(p.status, PlantStatus.growing.index);
    });

    test('bloomed / wilting / dead 植物：字段原样不受影响', () async {
      final db.AppDatabase database = await _openMigrated(_v6Ddl(), 6);

      final db.Plant bloomed = (await database.plantDao.byId('p_bloomed'))!;
      expect(bloomed.status, PlantStatus.bloomed.index);
      expect(bloomed.stage, PlantStage.adult.index);
      expect(bloomed.growthProgress, 1.0);
      expect(bloomed.stageStartedAt, _legacyBloomedStarted);
      expect(bloomed.speciesId, 'species_daisy');
      expect(bloomed.potIndex, 1);

      final db.Plant wilting = (await database.plantDao.byId('p_wilting'))!;
      expect(wilting.status, PlantStatus.wilting.index);
      expect(wilting.stage, PlantStage.sprout.index);
      expect(wilting.growthProgress, 0.35);
      expect(wilting.stageStartedAt, _legacyWiltingStarted);
      expect(wilting.speciesId, 'species_cactus');

      final db.Plant dead = (await database.plantDao.byId('p_dead'))!;
      expect(dead.status, PlantStatus.dead.index);
      expect(dead.stage, PlantStage.seed.index);
      expect(dead.growthProgress, 0.1);
      expect(dead.stageStartedAt, _legacyDeadStarted);
      expect(dead.deadAt, _legacyDeadStarted);
    });

    test('迁移后仍可正常写入 / 读回植物（DAO 往返不炸）', () async {
      final db.AppDatabase database = await _openMigrated(_v6Ddl(), 6);

      await database.plantDao.upsert(
        db.PlantsCompanion(
          id: const Value('p_new'),
          speciesId: const Value('species_cactus'),
          potIndex: const Value(7),
          stage: Value(PlantStage.sprout.index),
          stageStartedAt: Value(DateTime(2026, 9, 22, 10, 0)),
          growthProgress: const Value(0.42),
          status: Value(PlantStatus.growing.index),
          plantedAt: Value(DateTime(2026, 9, 22, 9, 0)),
        ),
      );

      final db.Plant p = (await database.plantDao.byId('p_new'))!;
      expect(p.speciesId, 'species_cactus');
      expect(p.stage, PlantStage.sprout.index);
      expect(p.growthProgress, closeTo(0.42, 1e-9));
      expect(p.stageStartedAt, DateTime(2026, 9, 22, 10, 0));
    });
  });

  group('幂等：已迁移到 v7 的库重复打开不报错、不二次清零', () {
    test('重新打开文件库：迁移后写入的进度原样保留（不会被第二次 UPDATE 抹掉）', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v7');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      // ① 首次打开：老库 v6 → 迁移到 v7（growing 被清零）。
      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v6Ddl()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 6;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 7);
      expect(
        (await first.plantDao.byId('p_growing'))!.growthProgress,
        0.0,
      );

      // ② 迁移后人为给该株写入新进度（模拟用户又开始养护）。
      await first.plantDao.upsert(
        db.PlantsCompanion(
          id: const Value('p_growing'),
          speciesId: const Value('species_sunflower'),
          potIndex: const Value(0),
          stage: Value(PlantStage.sprout.index),
          growthProgress: const Value(0.55),
          status: Value(PlantStatus.growing.index),
          plantedAt: Value(_legacyPlanted),
          stageStartedAt: Value(DateTime(2026, 9, 22, 12, 0)),
        ),
      );
      expect(
        (await first.plantDao.byId('p_growing'))!.growthProgress,
        closeTo(0.55, 1e-9),
      );
      await first.close();

      // ③ 二次打开（不带 setup，库已是 v7）：不得报错，也不得二次清零。
      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();

      final db.Plant reopened = (await second.plantDao.byId('p_growing'))!;
      expect(
        reopened.growthProgress,
        closeTo(0.55, 1e-9),
        reason: '二次打开被二次清零 → 0.55 变成了 ${reopened.growthProgress}',
      );
      expect(reopened.stage, PlantStage.sprout.index);

      // 非 growing 的植物同样原样保留。
      expect(
        (await second.plantDao.byId('p_bloomed'))!.growthProgress,
        1.0,
      );
    });
  });

  group('跨版本跳跃升级', () {
    test('v5 → v7：植物同样清零，且 check_ins 5 列补齐', () async {
      final db.AppDatabase database = await _openMigrated(_v5Ddl(), 5);
      expect(database.schemaVersion, 7);

      // ① v6 的补列分支仍然执行（跨版本跳跃不能漏掉中间版本）。
      final Set<String> cols = await _columns(database, 'check_ins');
      expect(
        cols,
        containsAll(<String>[
          'status',
          'sunlight_gross',
          'sunlight_granted',
          'resolved_at',
          'parent_note',
        ]),
      );

      // ② v7 的清零分支执行。
      final db.Plant growing = (await database.plantDao.byId('p_growing'))!;
      expect(growing.stage, PlantStage.seed.index);
      expect(growing.growthProgress, 0.0);

      // ③ 非 growing 不受影响。
      expect((await database.plantDao.byId('p_bloomed'))!.growthProgress, 1.0);
      expect((await database.plantDao.byId('p_dead'))!.growthProgress, 0.1);
    });

    test('v3 → v7：plants 表由 createAll 建出，迁移不报错', () async {
      // 场景：玄参大人跳过了中间几版安装，库还停在 v3（无 plants 表），直接升到 v7。
      final db.AppDatabase database = await _openMigrated(_v3Ddl(), 3);

      expect(database.schemaVersion, 7);
      expect(await _tableExists(database, 'plants'), isTrue);
      expect(await _columns(database, 'settings'),
          contains('garden_pot_capacity'));
      expect(await _columns(database, 'tasks'), contains('custom_subject'));

      // 空表上的 UPDATE 不应报错，也不应有残留行。
      expect(await database.plantDao.all(), isEmpty);
    });
  });
}
