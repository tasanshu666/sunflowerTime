/// 迁移回归测试 v15 → v16（**铲除返还**，玄参 2026-10-05 拍板，口径 C29）。
///
/// v16 变更：`plants` 新增 1 列 ——
///  · `shovel_refund`：种下时即定好的「铲除返还阳光数」（INT NOT NULL DEFAULT 0）。
///    普通档 150（300×50%）/ 精英档 250（500×50%）由领域层在种下时写入；
///    **历史行（v16 前种下）与向日葵免费首株 = 0 = 铲除不返还**
///    （防「免费种 → 铲 → 循环刷阳光」的经济漏洞）。
///
/// 本测试钉死五件事（**必须把历史行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 16`；
///  ② 老库 plants 行补列后 `shovel_refund` 读得到、且为默认 0（历史株不返还）；
///  ③ 老行原有字段（物种 / 阶段 / 进度 / 干扰物三列）**一条没丢**；
///  ④ 幂等：已迁移到 v16 的库二次打开不报错、值稳定不变；
///  ⑤ 经 `PlantLocalRepository` 读回的领域 [Plant] 实体 `shovelRefund == 0`。
library migration_v15_to_v16_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// v15 线上 schema（plants **不含** v16 的 `shovel_refund` 列 —— 缺列正是本测试要修的状态）。
List<String> _v15Ddl() => <String>[
      'CREATE TABLE settings ('
          'id INTEGER NOT NULL, age_tier INTEGER NOT NULL, '
          'night_boundary_hour INTEGER NOT NULL DEFAULT 21, '
          'night_boundary_minute INTEGER NOT NULL DEFAULT 0, '
          'daily_focus_cap INTEGER NOT NULL, daily_app_cap_minutes INTEGER NOT NULL, '
          'rest_after_sessions INTEGER NOT NULL, rest_minutes INTEGER NOT NULL, '
          'task_sunlight INTEGER NOT NULL, monthly_pool_budget INTEGER NOT NULL, '
          'quiet_mode INTEGER NOT NULL DEFAULT 0, sound_on INTEGER NOT NULL DEFAULT 1, '
          'bgm_on INTEGER NOT NULL DEFAULT 1, detection_on INTEGER NOT NULL DEFAULT 1, '
          'auto_confirm_single_high INTEGER NOT NULL DEFAULT 130, '
          'auto_confirm_single_low INTEGER NOT NULL DEFAULT 50, '
          'auto_confirm_monthly_pct REAL NOT NULL DEFAULT 0.25, '
          'currency_rate REAL NOT NULL DEFAULT 0.25, theme_dark INTEGER NOT NULL DEFAULT 0, '
          'autonomous_mode INTEGER NOT NULL DEFAULT 0, '
          'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, '
          'eye_care_enabled INTEGER NOT NULL DEFAULT 1, '
          'eye_care_interval_min INTEGER NOT NULL DEFAULT 20, '
          'eye_care_skip_allowed INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (id));',
      // ⚠️ v16 新增的 shovel_refund 列**故意缺失**。
      'CREATE TABLE plants ('
          'id TEXT NOT NULL, species_id TEXT NOT NULL, pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, stage_started_at INTEGER NOT NULL, '
          'growth_progress REAL NOT NULL DEFAULT 0.0, growth_factor REAL NOT NULL DEFAULT 1.0, '
          'water_used INTEGER NOT NULL DEFAULT 0, fertilizer_used INTEGER NOT NULL DEFAULT 0, '
          'status INTEGER NOT NULL, planted_at INTEGER NOT NULL, '
          'last_water_at INTEGER, wilted_at INTEGER, dead_at INTEGER, bloomed_at INTEGER, '
          'bloom_count INTEGER NOT NULL DEFAULT 0, mood INTEGER NOT NULL DEFAULT 0, '
          'weed_at INTEGER, pest_at INTEGER, weed_pest_roll_day INTEGER, '
          'PRIMARY KEY (id));',
      'CREATE TABLE premium_fragments ('
          'id INTEGER NOT NULL, balance INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
      'CREATE TABLE pending_bloom_rewards ('
          'id TEXT NOT NULL, plant_id TEXT NOT NULL, due_at INTEGER NOT NULL, '
          'reward_kind TEXT NOT NULL, claimed INTEGER NOT NULL DEFAULT 0, '
          'reward_sunlight INTEGER NOT NULL DEFAULT 0, '
          'reward_fragments INTEGER NOT NULL DEFAULT 0, '
          'reward_species_id TEXT, PRIMARY KEY (id));',
      'CREATE TABLE unlocked_species ('
          'species_id TEXT NOT NULL, PRIMARY KEY (species_id));',
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
          'content_category INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
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
          'repeat_rule TEXT, is_custom INTEGER NOT NULL, '
          'category INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
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
      // 历史 settings 行（v15 已含护眼三列，自定义值迁移后必须原样保留）。
      'INSERT INTO settings (id, age_tier, night_boundary_hour, night_boundary_minute, '
          'daily_focus_cap, daily_app_cap_minutes, rest_after_sessions, rest_minutes, '
          'task_sunlight, monthly_pool_budget, sound_on, bgm_on, garden_pot_capacity, '
          'eye_care_enabled, eye_care_interval_min, eye_care_skip_allowed) '
          'VALUES (1, 1, 22, 30, 90, 30, 3, 15, 12, 480, 1, 1, 6, 0, 30, 0);',
    ];

/// 历史 plants 行（v15 老库里的存量株，含干扰物三列的自定义值）。
String _plantInsertSql() {
  final DateTime t = DateTime(2026, 10, 1, 9);
  return "INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, "
      "growth_progress, growth_factor, water_used, fertilizer_used, status, planted_at, "
      "last_water_at, bloom_count, mood, weed_at, pest_at, weed_pest_roll_day) "
      "VALUES ('legacy-plant', 'species_sunflower', 0, 1, ${_secs(t)}, 0.42, 1.0, "
      "1, 1, 0, ${_secs(t)}, ${_secs(t)}, 1, 1, ${_secs(t)}, NULL, ${_secs(t)});";
}

/// 逐列读出存量植物行（直接走 SQL，绕开 drift 数据类，专测「列补出来没有」）。
Future<Map<String, Object?>> _legacyPlantRow(db.AppDatabase database) async {
  final QueryRow row = await database
      .customSelect('SELECT species_id, growth_progress, shovel_refund, '
          'weed_at, pest_at, weed_pest_roll_day FROM plants '
          "WHERE id = 'legacy-plant';")
      .getSingle();
  return <String, Object?>{
    'species_id': row.data['species_id'],
    'growth_progress': row.data['growth_progress'],
    'shovel_refund': row.data['shovel_refund'],
    'weed_at': row.data['weed_at'],
    'pest_at': row.data['pest_at'],
    'weed_pest_roll_day': row.data['weed_pest_roll_day'],
  };
}

/// 手工构造「老库（v15）」并让 AppDatabase 触发迁移（内存库）。
Future<db.AppDatabase> _openMigrated(int userVersion) async {
  final NativeDatabase executor = NativeDatabase.memory(
    setup: (rawDb) {
      for (final String sql in _v15Ddl()) {
        rawDb.execute(sql);
      }
      rawDb.execute(_plantInsertSql());
      rawDb.execute('PRAGMA user_version = $userVersion;');
    },
  );
  final db.AppDatabase database = db.AppDatabase(executor);
  await database.customSelect('SELECT 1').get(); // 触发迁移
  addTearDown(() => database.close());
  return database;
}

Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row =
      await database.customSelect('SELECT COUNT(*) AS c FROM $table;').getSingle();
  return row.read<int>('c');
}

void main() {
  group('迁移 v15->v16：铲除返还列（C29）', () {
    test('schemaVersion 必须为最新 16（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(15);
      expect(database.schemaVersion, 24);
    });

    test('shovel_refund 列补出来且历史行为默认 0（历史株铲除不返还）', () async {
      final db.AppDatabase database = await _openMigrated(15);
      final Map<String, Object?> row = await _legacyPlantRow(database);
      expect(row['shovel_refund'], 0,
          reason: 'v16 前种下的历史株没有「返还额」记录，'
              '补列后必须落默认 0（防历史数据凭空长出返还额）');
    });

    test('老行原有字段一条不丢（物种 / 进度 / 干扰物三列）', () async {
      final db.AppDatabase database = await _openMigrated(15);
      final Map<String, Object?> row = await _legacyPlantRow(database);
      expect(row['species_id'], 'species_sunflower');
      expect(row['growth_progress'], 0.42);
      // 干扰物三列（v14 引入）语义保留： weed_at 有值 / pest_at null / roll_day 有值。
      expect(row['weed_at'], isNotNull);
      expect(row['pest_at'], isNull);
      expect(row['weed_pest_roll_day'], isNotNull);
    });

    test('经 PlantLocalRepository 读回领域实体 shovelRefund == 0', () async {
      final db.AppDatabase database = await _openMigrated(15);
      final Plant? p = await PlantLocalRepository(database).plant('legacy-plant');
      expect(p, isNotNull);
      expect(p!.shovelRefund, 0);
      expect(p.speciesId, 'species_sunflower');
      expect(p.hasWeed, isTrue, reason: '历史杂草语义不能被迁移洗掉');
      expect(p.hasPest, isFalse);
    });

    test('settings 历史行自定义值原样保留（迁移只补列、不许顺手改数据）', () async {
      final db.AppDatabase database = await _openMigrated(15);
      final QueryRow row = await database
          .customSelect('SELECT rest_after_sessions, garden_pot_capacity, '
              'eye_care_enabled, eye_care_interval_min, eye_care_skip_allowed '
              'FROM settings WHERE id = 1;')
          .getSingle();
      expect(row.read<int>('rest_after_sessions'), 3);
      expect(row.read<int>('garden_pot_capacity'), 6);
      expect(row.read<int>('eye_care_enabled'), 0,
          reason: '家长关闭的护眼开关不能被迁移洗回默认开');
      expect(row.read<int>('eye_care_interval_min'), 30);
      expect(row.read<int>('eye_care_skip_allowed'), 0);
    });

    test('其它表数据原样保留（账本 / 任务）', () async {
      final db.AppDatabase database = await _openMigrated(15);
      expect(await _count(database, 'settings'), 1);
      expect(await _count(database, 'plants'), 1);
      expect(await _count(database, 'sunlight_ledgers'), 0);
      expect(await _count(database, 'tasks'), 9,
          reason: 'C52 v21：空任务表由迁移补播 9 条默认成长任务');
    });

    test('幂等：已迁移到 v16 的库二次打开不报错、值稳定不变', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v16');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v15Ddl()) {
              rawDb.execute(sql);
            }
            rawDb.execute(_plantInsertSql());
            rawDb.execute('PRAGMA user_version = 15;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 24);
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 24);
      expect(await _count(second, 'plants'), 1);

      final Map<String, Object?> row = await _legacyPlantRow(second);
      expect(row['shovel_refund'], 0);
    });
  });
}
