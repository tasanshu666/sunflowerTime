/// 迁移回归测试 v19 → v20（**「允许孩子跳过护眼」默认口径 true → false**，C48）。
///
/// 背景（玄参 2026-10-10 拍板）：护眼是硬性休息，「允许跳过」默认口子应关闭。
/// 既有库在 v15 补列时按旧默认落了 true（家长未显式动过也是 true），仅改 Dart
/// 常量对已有设备不生效 —— v20 迁移无条件把 settings 行翻为 false。
///
/// 口径变更语义：家长此前**显式开启**过的设置同样被重置（当前验收阶段仅玄参
/// 一台设备，接受重置；正式发布后不得再做同类重置）。
///
/// 本测试钉死五件事：
///  ① `AppDatabase.schemaVersion == 20`；
///  ② settings 行 true（历史默认 / 显式开启）升级后翻为 false；
///  ③ 已是 false 的行保持 false（幂等）；
///  ④ 无 settings 行时升级不崩（UPDATE 空表）；
///  ⑤ 幂等：v20 库二次打开不报错、值稳定。
library migration_v19_to_v20_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// v19 schema：与 v18 DDL 一致（v19 仅数据清理、无 DDL 变更），直接复用
/// `migration_v18_to_v19_test.dart` 里标定的 DDL（settings 表含
/// `eye_care_skip_allowed INTEGER NOT NULL DEFAULT 1` 旧默认）。
List<String> _v19Ddl() => <String>[
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
      'CREATE TABLE eye_care_logs ('
          'id TEXT NOT NULL, ts INTEGER NOT NULL, day_key TEXT NOT NULL, '
          'result TEXT NOT NULL, watched_seconds INTEGER NOT NULL, '
          'source TEXT NOT NULL, PRIMARY KEY (id));',
    ];

/// 打开一个「v19 旧库」：v19 DDL + 种子 + `user_version = 19`，打开即触发迁移。
///
/// [seedSqls] 可空 —— 传空即「无 settings 行」场景。
Future<db.AppDatabase> _openV19({List<String> seedSqls = const <String>[]}) async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        for (final String sql in _v19Ddl()) {
          rawDb.execute(sql);
        }
        for (final String sql in seedSqls) {
          rawDb.execute(sql);
        }
        rawDb.execute('PRAGMA user_version = 19;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get(); // 触发迁移
  return database;
}

/// settings 单行的 eye_care_skip_allowed 值（无行返回 null）。
Future<bool?> _skipAllowed(db.AppDatabase database) async {
  final List<QueryRow> rows = await database.customSelect(
    'SELECT eye_care_skip_allowed AS v FROM settings WHERE id = 1;',
  ).get();
  if (rows.isEmpty) return null;
  return rows.single.read<bool>('v');
}

void main() {
  group('迁移 v19->v20：允许跳过护眼默认口径 true → false（C48）', () {
    test('schemaVersion 必须为最新 21（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV19();
      addTearDown(database.close);
      expect(database.schemaVersion, 24);
    });

    test('settings 行 true（历史默认落值 / 显式开启）升级后翻为 false', () async {
      final db.AppDatabase database = await _openV19(seedSqls: <String>[
        'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
            'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget, '
            'eye_care_skip_allowed) VALUES (1, 2, 60, 30, 2, 10, 12, 400, 1);',
      ]);
      addTearDown(database.close);
      expect(await _skipAllowed(database), isFalse,
          reason: '新默认口径：不允许孩子跳过护眼');
    });

    test('已是 false 的行保持 false（不被翻转回 true）', () async {
      final db.AppDatabase database = await _openV19(seedSqls: <String>[
        'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
            'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget, '
            'eye_care_skip_allowed) VALUES (1, 2, 60, 30, 2, 10, 12, 400, 0);',
      ]);
      addTearDown(database.close);
      expect(await _skipAllowed(database), isFalse);
    });

    test('无 settings 行时升级不崩（UPDATE 空表幂等通过）', () async {
      final db.AppDatabase database = await _openV19();
      addTearDown(database.close);
      expect(await _skipAllowed(database), isNull,
          reason: '迁移不 seed 行；默认值由 SettingsLocalRepository 兜底');
    });

    test('幂等：v20 库二次打开不报错、值稳定', () async {
      final db.AppDatabase database = await _openV19(seedSqls: <String>[
        'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
            'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget) '
            'VALUES (1, 2, 60, 30, 2, 10, 12, 400);',
      ]);
      await database.customSelect('SELECT 1').get(); // 二次访问触发 schema 校验
      expect(database.schemaVersion, 24);
      expect(await _skipAllowed(database), isFalse);
      await database.close();
    });
  });
}
