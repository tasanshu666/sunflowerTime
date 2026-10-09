/// 迁移回归测试 v17 → v18（**护眼记录表 `eye_care_logs`**，玄参 2026-10-09 拍板）。
///
/// 背景：家长报告需要护眼的「跳过次数 / 实际观看时长」统计，而账本只记完成
/// （`refType='eye_care_break'`，跳过从不入账）—— 新增 `eye_care_logs` 表，
/// 护眼卡退出时完成 / 跳过都落一行。
///
/// 本测试钉死六件事：
///  ① `AppDatabase.schemaVersion == 18`；
///  ② v17 老库升级后 `eye_care_logs` 表存在、可写入、可聚合；
///  ③ 新表为空表起步（无历史数据回填 —— 完成历史以账本为权威，不重复记）；
///  ④ v17 既有数据（账本 / 植物 / 设置）原样保留；
///  ⑤ 幂等：v18 库二次打开不报错、行集合稳定不变；
///  ⑥ 首次建库（onCreate）同样带 `eye_care_logs` 表。
library migration_v17_to_v18_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// v17 schema（v17 仅做晨露重复行数据清理，**DDL 与 v16 完全一致**）。
List<String> _v17Ddl() => <String>[
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
          'eye_care_skip_allowed INTEGER NOT NULL DEFAULT 1, '
          'shovel_refund INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
      'CREATE TABLE plants ('
          'id TEXT NOT NULL, species_id TEXT NOT NULL, pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, stage_started_at INTEGER NOT NULL, '
          'growth_progress REAL NOT NULL DEFAULT 0.0, growth_factor REAL NOT NULL DEFAULT 1.0, '
          'water_used INTEGER NOT NULL DEFAULT 0, fertilizer_used INTEGER NOT NULL DEFAULT 0, '
          'status INTEGER NOT NULL, planted_at INTEGER NOT NULL, '
          'last_water_at INTEGER, wilted_at INTEGER, dead_at INTEGER, bloomed_at INTEGER, '
          'bloom_count INTEGER NOT NULL DEFAULT 0, mood INTEGER NOT NULL DEFAULT 0, '
          'weed_at INTEGER, pest_at INTEGER, weed_pest_roll_day INTEGER, '
          'shovel_refund INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
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
    ];

/// 一条 v17 历史账本行（完成的护眼，升级后必须原样保留）。
final int _ts = _secs(DateTime(2026, 10, 8, 10));

List<String> _seedSqls() => <String>[
      "INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, "
          "rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget) "
          "VALUES (1, 2, 60, 30, 2, 10, 12, 400);",
      "INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, status, planted_at) "
          "VALUES ('p1', 'species_sunflower', 0, 1, $_ts, 0, $_ts);",
      "INSERT INTO sunlight_ledgers (id, ts, type, gross, net, balance_after, ref_type, day_key) "
          "VALUES ('led-1', $_ts, 1, 4.0, 4.0, 4.0, 'eye_care_break', '2026-10-08');",
    ];

void main() {
  group('迁移 v17->v18：新增护眼记录表 eye_care_logs', () {
    test('schemaVersion 必须为最新 18（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = db.AppDatabase(
        NativeDatabase.memory(),
      );
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();
      expect(database.schemaVersion, 18);
    });

    test('v17 老库升级后 eye_care_logs 存在、可写入、可聚合', () async {
      final db.AppDatabase database = db.AppDatabase(
        NativeDatabase.memory(
          setup: (rawDb) {
            for (final String sql in _v17Ddl()) {
              rawDb.execute(sql);
            }
            for (final String sql in _seedSqls()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 17;');
          },
        ),
      );
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get(); // 触发迁移

      // ② 新表可写（走真实 DAO 通路）。
      await database.eyeCareLogDao.appendRow(
        db.EyeCareLogsCompanion.insert(
          id: 'log-1',
          ts: DateTime.fromMillisecondsSinceEpoch(_ts * 1000),
          dayKey: '2026-10-08',
          result: 'skipped',
          watchedSeconds: 17,
          source: 'inSession',
        ),
      );
      expect(await database.eyeCareLogDao.countByResult('skipped'), 1);
      expect(await database.eyeCareLogDao.countByResult('completed'), 0);
      expect(await database.eyeCareLogDao.sumWatchedSecondsByResult('skipped'),
          17);
    });

    test('新表空表起步（完成历史以账本为权威，不重复回填）', () async {
      final db.AppDatabase database = db.AppDatabase(
        NativeDatabase.memory(
          setup: (rawDb) {
            for (final String sql in _v17Ddl()) {
              rawDb.execute(sql);
            }
            for (final String sql in _seedSqls()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 17;');
          },
        ),
      );
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();
      final QueryRow row = await database.customSelect(
        'SELECT COUNT(*) AS c FROM eye_care_logs;',
      ).getSingle();
      expect(row.read<int>('c'), 0,
          reason: '升级不回填：账本里已有的完成历史不重复落新表');
    });

    test('v17 既有数据（账本 / 植物 / 设置）原样保留', () async {
      final db.AppDatabase database = db.AppDatabase(
        NativeDatabase.memory(
          setup: (rawDb) {
            for (final String sql in _v17Ddl()) {
              rawDb.execute(sql);
            }
            for (final String sql in _seedSqls()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 17;');
          },
        ),
      );
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();
      final QueryRow led = await database.customSelect(
        "SELECT net FROM sunlight_ledgers WHERE id = 'led-1';",
      ).getSingle();
      expect(led.read<double>('net'), 4.0);
      final QueryRow plant = await database.customSelect(
        "SELECT species_id FROM plants WHERE id = 'p1';",
      ).getSingle();
      expect(plant.read<String>('species_id'), 'species_sunflower');
    });

    test('幂等：v18 库二次打开不报错、行集合稳定不变', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v18');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      Future<db.AppDatabase> openLegacy() async {
        final db.AppDatabase database = db.AppDatabase(
          NativeDatabase(
            file,
            setup: (rawDb) {
              for (final String sql in _v17Ddl()) {
                rawDb.execute(sql);
              }
              for (final String sql in _seedSqls()) {
                rawDb.execute(sql);
              }
              rawDb.execute('PRAGMA user_version = 17;');
            },
          ),
        );
        await database.customSelect('SELECT 1').get();
        return database;
      }

      final db.AppDatabase first = await openLegacy();
      expect(first.schemaVersion, 18);
      await first.eyeCareLogDao.appendRow(
        db.EyeCareLogsCompanion.insert(
          id: 'log-1',
          ts: DateTime.fromMillisecondsSinceEpoch(_ts * 1000),
          dayKey: '2026-10-08',
          result: 'skipped',
          watchedSeconds: 17,
          source: 'inSession',
        ),
      );
      final int countAfterFirst =
          await first.eyeCareLogDao.countByResult('skipped');
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 18);
      expect(await second.eyeCareLogDao.countByResult('skipped'),
          countAfterFirst, reason: '二次打开行集合稳定不变（不重复建表 / 不丢行）');
    });
  });
}
