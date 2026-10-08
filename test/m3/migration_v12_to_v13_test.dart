/// 迁移回归测试 v12 → v13（**花园氛围音默认开启**，玄参 2026-09-29 拍板）。
///
/// v13 变更：把存量 `settings` 行的 `bgm_on` **翻为 1**（`UPDATE settings SET bgm_on = 1`）。
///
/// 背景（为什么必须迁移、光改列默认值不够）：
///  · 此前 `bgm_on` 默认 0，且 **代码从未把设置接到音频服务**（`AudioService.applySettings`
///    全项目无调用点）→ 花园 BGM 从来不会响（玄参实测「做完测试好像就没听到」）；
///  · 玄参拍板「默认开启」后，只改列默认值救不了**已存在的行**（老设备仍是 0），
///    故用一次显式迁移把存量行翻值；新库由列默认值 `Constant(true)` 覆盖。
///
/// 本测试钉死四件事（**必须把历史行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 15`；
///  ② 老库 `bgm_on = 0` 的历史行 → 迁移后读回 **true**（氛围音默认开）；
///  ③ 其它表数据（植物 / 待收集奖励）原样保留；
///  ④ 幂等：已迁移到 v13 的库二次打开不报错、值稳定为 1。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**。
library migration_v12_to_v13_test;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

final DateTime _legacyPlanted = DateTime(2026, 9, 1, 8, 0);

/// v12 线上 schema（= v11 + pending_bloom_rewards 的 3 个奖励内容列）。
/// 关键：历史 settings 行**显式** `bgm_on = 0`（老语义：默认关）。
List<String> _v12Ddl() => <String>[
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
          'theme_dark INTEGER NOT NULL DEFAULT 0, '
          'autonomous_mode INTEGER NOT NULL DEFAULT 0, '
          'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, '
          'PRIMARY KEY (id));',
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
      // 历史设置行：**显式 bgm_on = 0**（老默认关）→ 迁移后必须变成 1。
      'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
          'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget, '
          'sound_on, bgm_on, garden_pot_capacity) '
          'VALUES (1, ${AgeTier.low.index}, 90, 30, 2, 10, 12, 160, 1, 0, 8);',
      'INSERT INTO premium_fragments (id, balance) VALUES (1, 7);',
      'INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed) '
          'VALUES (\'pr_legacy\', \'p_sunflower\', ${_secs(_legacyPlanted)}, \'normal\', 0);',
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
          'VALUES (\'p_sunflower\', \'species_sunflower\', 0, '
          '${0}, ${_secs(_legacyPlanted)}, 0.5, 1.0, 1, 1, 0, '
          '${_secs(_legacyPlanted)}, ${_secs(_legacyPlanted)}, NULL, NULL, NULL, 0, 0);',
    ];

Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row =
      await database.customSelect('SELECT COUNT(*) AS c FROM $table;').getSingle();
  return row.read<int>('c');
}

/// 手工构造「老库」并让 AppDatabase 触发迁移（内存库）。
Future<db.AppDatabase> _openMigrated(int userVersion) async {
  final NativeDatabase executor = NativeDatabase.memory(
    setup: (rawDb) {
      for (final String sql in _v12Ddl()) {
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
  group('迁移 v12->v13：花园氛围音默认开启（bgm_on → 1）', () {
    test('schemaVersion 必须为最新 14（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(12);
      expect(database.schemaVersion, 17);
    });

    test('老库 bgm_on = 0 的历史行 → 迁移后读回 true（默认开启）', () async {
      final db.AppDatabase database = await _openMigrated(12);
      final SettingsLocalRepository repo = SettingsLocalRepository(database);
      final bool bgmOn = (await repo.getSettings()).bgmOn;
      expect(bgmOn, isTrue,
          reason: '存量库存量行必须由迁移翻为「背景音乐开」，否则花园 BGM 永不响');
    });

    test('其它表数据原样保留（植物 / 待收集奖励 / 碎片 / 设置行数）', () async {
      final db.AppDatabase database = await _openMigrated(12);
      expect(await _count(database, 'settings'), 1);
      expect(await _count(database, 'plants'), 1);
      expect(await _count(database, 'pending_bloom_rewards'), 1);
      expect(await database.bloomRewardDao.fragmentBalance(), 7);
      expect((await database.plantDao.byId('p_sunflower'))!.speciesId,
          'species_sunflower');
    });

    test('幂等：已迁移到 v13 的库二次打开不报错、bgm_on 稳定为 1', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v13');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v12Ddl()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 12;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 17);
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 17);
      expect((await SettingsLocalRepository(second).getSettings()).bgmOn, isTrue,
          reason: '二次打开不得把 bgm_on 又翻回去');
      expect(await _count(second, 'plants'), 1);
    });
  });
}
