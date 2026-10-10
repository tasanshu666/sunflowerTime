/// 迁移回归测试 v13 → v14（**花园干扰物「杂草 / 害虫」**，玄参 2026-09-30 拍板，口径 C26）。
///
/// v14 变更：`plants` 新增 3 列 ——
///  · `weed_at`：杂草出现的当天零点；非 null = 本盆当前有杂草；
///  · `pest_at`：害虫出现的当天零点；非 null = 本盆当前有害虫；
///  · `weed_pest_roll_day`：「杂草 / 害虫每日 roll」已执行的当天零点（幂等基准）。
///
/// 为什么必须迁移（光靠列默认值救不了存量库）：
///  · SQLite 的 `ALTER TABLE ADD COLUMN` 已由 `_ensureColumn` 幂等补列，新库天然有列；
///    但**老设备上已存在的 plants 行**不会自己长出新列，读取时必须由迁移补齐，
///    否则老用户一进花园页就撞上「no such column: weed_at」；
///  · 三列都是 nullable 且无语义默认值（null = 无杂草 / 无害虫 / 当日还没 roll），
///    因此历史行取 NULL 即可，不需要回填脚本。
///
/// 本测试钉死四件事（**必须把历史行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 15`；
///  ② 老库 plants 行的三条新列**读得到、且为 NULL**（历史语义 = 无杂草 / 无害虫）；
///  ③ 经 `PlantLocalRepository` 读回的 [Plant] 实体 `hasWeed` / `hasPest` 为 false，
///     且老行原有字段（进度 / 状态 / 花期起点）**一条没丢**；
///  ④ 幂等：已迁移到 v14 的库二次打开不报错、NULL 值稳定不变。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**。
library migration_v13_to_v14_test;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

final DateTime _legacyPlanted = DateTime(2026, 9, 20, 8, 0);
final DateTime _legacyBloomed = DateTime(2026, 9, 26, 12, 0);

/// v13 线上 schema（= v12 + `bgm_on` 默认开启的迁移，但**不含** v14 的三个新列）。
///
/// 关键：plants 表**故意不写** weed_at / pest_at / weed_pest_roll_day —— 这正是
/// 「老库」的形态，迁移后这三列必须被补出来且可读。
List<String> _v13Ddl() => <String>[
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
          'bgm_on INTEGER NOT NULL DEFAULT 1, '
          'detection_on INTEGER NOT NULL DEFAULT 1, '
          'auto_confirm_single_high INTEGER NOT NULL DEFAULT 130, '
          'auto_confirm_single_low INTEGER NOT NULL DEFAULT 50, '
          'auto_confirm_monthly_pct REAL NOT NULL DEFAULT 0.25, '
          'currency_rate REAL NOT NULL DEFAULT 0.25, '
          'theme_dark INTEGER NOT NULL DEFAULT 0, '
          'autonomous_mode INTEGER NOT NULL DEFAULT 0, '
          'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, '
          'PRIMARY KEY (id));',
      // ⚠️ v14 新增的三列**故意缺失** —— 缺列正是本测试要修的状态。
      'CREATE TABLE plants ('
          'id TEXT NOT NULL, species_id TEXT NOT NULL, pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, stage_started_at INTEGER NOT NULL, '
          'growth_progress REAL NOT NULL DEFAULT 0.0, growth_factor REAL NOT NULL DEFAULT 1.0, '
          'water_used INTEGER NOT NULL DEFAULT 0, fertilizer_used INTEGER NOT NULL DEFAULT 0, '
          'status INTEGER NOT NULL, planted_at INTEGER NOT NULL, '
          'last_water_at INTEGER, wilted_at INTEGER, dead_at INTEGER, bloomed_at INTEGER, '
          'bloom_count INTEGER NOT NULL DEFAULT 0, '
          'mood INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
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
      'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
          'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget, '
          'sound_on, bgm_on, garden_pot_capacity) '
          'VALUES (1, ${AgeTier.low.index}, 90, 30, 2, 10, 12, 160, 1, 1, 8);',
      // 历史植株：已盛开（第 2 阶段 adult）、进度 0.6、已浇水施肥、有花期起点。
      // 迁移后这些字段必须**一条不丢**，且三个新列为 NULL（= 无杂草 / 无害虫 / 未 roll）。
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
          'VALUES (\'p_sunflower\', \'species_sunflower\', 0, '
          '${2}, ${_secs(_legacyPlanted)}, 0.6, 1.3, 1, 1, ${PlantStatus.bloomed.index}, '
          '${_secs(_legacyPlanted)}, ${_secs(_legacyPlanted)}, NULL, NULL, '
          '${_secs(_legacyBloomed)}, 1, 0);',
    ];

Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row =
      await database.customSelect('SELECT COUNT(*) AS c FROM $table;').getSingle();
  return row.read<int>('c');
}

/// 逐列读出 plants 的三个新列（直接走 SQL，绕开 drift 数据类，专测「列补出来没有」）。
Future<Map<String, Object?>> _weedPestRow(db.AppDatabase database) async {
  final QueryRow row = await database
      .customSelect('SELECT weed_at, pest_at, weed_pest_roll_day FROM plants '
          'WHERE id = \'p_sunflower\';')
      .getSingle();
  return <String, Object?>{
    'weed_at': row.data['weed_at'],
    'pest_at': row.data['pest_at'],
    'weed_pest_roll_day': row.data['weed_pest_roll_day'],
  };
}

/// 手工构造「老库（v13）」并让 AppDatabase 触发迁移（内存库）。
Future<db.AppDatabase> _openMigrated(int userVersion) async {
  final NativeDatabase executor = NativeDatabase.memory(
    setup: (rawDb) {
      for (final String sql in _v13Ddl()) {
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
  group('迁移 v13->v14：花园干扰物杂草 / 害虫三列（C26）', () {
    test('schemaVersion 必须为最新 14（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(13);
      expect(database.schemaVersion, 20);
    });

    test('三列补出来且历史行为 NULL（= 无杂草 / 无害虫 / 当日未 roll）', () async {
      final db.AppDatabase database = await _openMigrated(13);
      final Map<String, Object?> row = await _weedPestRow(database);
      expect(row['weed_at'], equals(null),
          reason: '历史行不该凭空长出杂草（否则老用户一进花园就看到莫名其妙的花）');
      expect(row['pest_at'], equals(null));
      expect(row['weed_pest_roll_day'], equals(null));
    });

    test('读回的 Plant 实体：干扰物为 false，且原有字段一条不丢', () async {
      final db.AppDatabase database = await _openMigrated(13);
      final Plant? p = await PlantLocalRepository(database).plant('p_sunflower');
      expect(p, isNot(equals(null)));
      expect(p!.hasWeed, isFalse);
      expect(p.hasPest, isFalse);
      expect(p.hasPestOrWeed, isFalse);
      // 老字段完整性（迁移只补列、不许顺手改数据）
      expect(p.speciesId, 'species_sunflower');
      expect(p.stage, PlantStage.adult);
      expect(p.status, PlantStatus.bloomed);
      expect(p.growthProgress, closeTo(0.6, 1e-9));
      expect(p.growthFactor, closeTo(1.3, 1e-9));
      expect(p.bloomCount, 1);
      expect(p.bloomedAt, _legacyBloomed);
      expect(p.waterUsed, isTrue);
      expect(p.fertilizerUsed, isTrue);
    });

    test('其它表数据原样保留（设置 / 待收集奖励 / 碎片）', () async {
      final db.AppDatabase database = await _openMigrated(13);
      expect(await _count(database, 'settings'), 1);
      expect(await _count(database, 'plants'), 1);
      expect(await _count(database, 'pending_bloom_rewards'), 0);
      expect(await database.bloomRewardDao.fragmentBalance(), 0);
    });

    test('幂等：已迁移到 v14 的库二次打开不报错、NULL 值稳定不变', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v14');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v13Ddl()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 13;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 20);
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 20);
      expect(await _count(second, 'plants'), 1);
      final Map<String, Object?> row = await _weedPestRow(second);
      expect(row['weed_at'], equals(null));
      expect(row['pest_at'], equals(null));
      expect(row['weed_pest_roll_day'], equals(null));
      expect((await PlantLocalRepository(second).plant('p_sunflower'))!.hasWeed,
          isFalse);
    });

  });
}
