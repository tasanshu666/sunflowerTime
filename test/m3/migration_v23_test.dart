/// 迁移回归测试 v22 → v23（**清掉「与内置种子同名」的重复行**，C54）。
///
/// 背景（玄参 2026-10-10 真机实证「家长天地成长任务默认条目重复」）：v21 / v22 只按
/// **固定 id** 识别内置行 —— 一条「名字与内置种子一字不差、id 却是别的（自建 / 历史
/// 脏数据）」的行不会被 v22 的 `is_custom = 0` 白名单清理命中 → 家长天地同名两条
///（截图实证：帮助家长打扫卫生 ×2）。v23 把内置种子集合强制定死为 9 任务 + 6 奖励，
/// 同名重复行**先重定向历史引用再删行**（不断链）。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion == 23`；
///  ② 成长任务同名重复行 → 删除；其打卡历史重定向到内置 id；
///  ③ is_custom=0 且不在 9 条白名单内的脏行 → 删除（v23 兜底口径）；
///  ④ 奖励模板同名重复行 → 删除；其兑换历史重定向到内置 id；
///  ⑤ 不同名的用户自建项（任务 / 奖励）一律不动；
///  ⑥ 幂等：v23 库二次打开不报错、数据稳定。
library migration_v23_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// v22 schema DDL（v22 / v23 均无 DDL 变更，与 v21 相同）。
List<String> _v22Ddl() => <String>[
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

/// v22 库状态：新 9 条成长任务 + 新 6 条奖励（干净库）。
const List<String> _v22SeedSqls = <String>[
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_homework', '完成学校作业', 3, 1, 20, 8, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_read', '阅读 20 分钟', 0, 0, 15, 8, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_math', '练习数学口算', 1, 1, 15, 6, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_english_read', '指读英语20分钟', 2, 0, 15, 8, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_english_listen', '早上听英语听力15分钟', 2, 0, 15, 6, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_rope_skip', '1分钟跳绳170个以上', 3, 0, 15, 10, 'daily', 0, 2);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_homework_first', '放学后优先完成作业', 3, 0, 15, 5, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_pushup', '10个俯卧撑+10个仰卧起坐', 3, 0, 15, 5, 'daily', 0, 2);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_chores', '帮助家长打扫卫生', 3, 0, 15, 5, 'daily', 0, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_snack', '小零食', 1, 30, 3, 1, 1, 1);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_cartoon', '看一集动画片', 1, 100, 1, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_extra_play', '睡前多玩10分钟', 1, 20, 3, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_weekend_outing', '周末出去玩', 1, 200, 1, 1, 1, 2);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_toy', '买一个小玩具', 1, 100, 1, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_story', '睡前多听1个故事', 1, 30, 3, 1, 1, 3);",
];

/// 打开一个「v22 旧库」：v22 DDL + 种子 + `user_version = 22`，打开即触发 v23 迁移。
Future<db.AppDatabase> _openV22({List<String> seedSqls = _v22SeedSqls}) async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        for (final String sql in _v22Ddl()) {
          rawDb.execute(sql);
        }
        for (final String sql in seedSqls) {
          rawDb.execute(sql);
        }
        rawDb.execute('PRAGMA user_version = 22;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get(); // 触发迁移
  return database;
}

Future<List<Map<String, Object?>>> _taskRows(db.AppDatabase database) async {
  final List<QueryRow> rows = await database.customSelect(
    'SELECT id, name, is_custom, category FROM tasks ORDER BY id;',
  ).get();
  return rows.map((QueryRow r) => r.data).toList();
}

Future<List<Map<String, Object?>>> _rewardRows(db.AppDatabase database) async {
  final List<QueryRow> rows = await database.customSelect(
    'SELECT id, name, base_cost FROM reward_templates ORDER BY id;',
  ).get();
  return rows.map((QueryRow r) => r.data).toList();
}

Future<String?> _checkInTaskId(db.AppDatabase database, String id) async {
  final List<QueryRow> rows = await database.customSelect(
    'SELECT task_id FROM check_ins WHERE id = ?;',
    variables: <Variable>[Variable<String>(id)],
  ).get();
  return rows.isEmpty ? null : rows.single.data['task_id'] as String?;
}

Future<String?> _redemptionTemplateId(
  db.AppDatabase database,
  String id,
) async {
  final List<QueryRow> rows = await database.customSelect(
    'SELECT template_id FROM redemption_requests WHERE id = ?;',
    variables: <Variable>[Variable<String>(id)],
  ).get();
  return rows.isEmpty ? null : rows.single.data['template_id'] as String?;
}

Map<String, Object?>? _byId(List<Map<String, Object?>> rows, String id) {
  for (final Map<String, Object?> r in rows) {
    if (r['id'] == id) return r;
  }
  return null;
}

void main() {
  group('迁移 v22->v23：清掉与内置种子同名的重复行（C54）', () {
    test('schemaVersion 必须为最新 24（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV22(seedSqls: const <String>[]);
      addTearDown(database.close);
      expect(database.schemaVersion, 24);
    });

    test('成长任务同名重复行 → 删除 + 打卡历史重定向到内置 id', () async {
      final db.AppDatabase database = await _openV22(seedSqls: <String>[
        ..._v22SeedSqls,
        // 同名重复行（模拟「用户按同名自建」/ 历史脏数据，is_custom = 1）。
        "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
            "sunlight_reward, repeat_rule, is_custom, category) VALUES "
            "('dup-chores-0001', '帮助家长打扫卫生', 3, 0, 15, 5, "
            "'daily', 1, 3);",
        // 该重复行上有打卡历史 → 必须重定向、不许断链。
        "INSERT INTO check_ins (id, task_id, date, completed_at, "
            "is_perfect_day, status) VALUES ('ci_1', 'dup-chores-0001', "
            "1700000000000, 1700000000000, 0, 0);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _taskRows(database);
      expect(tasks, hasLength(9), reason: '同名重复行被清、9 条内置保留');
      expect(_byId(tasks, 'dup-chores-0001'), isNull);
      expect(_byId(tasks, 'seed_task_chores'), isNotNull);
      expect(await _checkInTaskId(database, 'ci_1'), 'seed_task_chores',
          reason: '打卡历史改挂到内置 id，不断链');
    });

    test('is_custom=0 且不在 9 条白名单内的脏行 → 删除（v23 兜底口径）', () async {
      final db.AppDatabase database = await _openV22(seedSqls: <String>[
        ..._v22SeedSqls,
        "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
            "sunlight_reward, repeat_rule, is_custom, category) VALUES "
            "('seed_task_legacy_y', '旧版遗留任务', 3, 0, 15, 5, "
            "'daily', 0, 1);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _taskRows(database);
      expect(tasks, hasLength(9));
      expect(_byId(tasks, 'seed_task_legacy_y'), isNull);
    });

    test('奖励模板同名重复行 → 删除 + 兑换历史重定向到内置 id', () async {
      final db.AppDatabase database = await _openV22(seedSqls: <String>[
        ..._v22SeedSqls,
        "INSERT INTO reward_templates (id, name, category, base_cost, "
            "freq_limit, cooldown_rule, enabled, content_category) VALUES "
            "('dup-cartoon-0002', '看一集动画片', 1, 90, 1, 1, 1, 3);",
        "INSERT INTO redemption_requests (id, template_id, requested_at, "
            "cost, status) VALUES ('rr_1', 'dup-cartoon-0002', "
            "1700000000000, 90, 0);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> rewards = await _rewardRows(database);
      expect(rewards, hasLength(6), reason: '同名重复行被清、6 条内置保留');
      expect(_byId(rewards, 'dup-cartoon-0002'), isNull);
      expect(await _redemptionTemplateId(database, 'rr_1'), 'seed_cartoon',
          reason: '兑换历史改挂到内置 id，不断链');
    });

    test('不同名的用户自建项（任务 is_custom=1 / 奖励 UUID id）一律不动', () async {
      final db.AppDatabase database = await _openV22(seedSqls: <String>[
        ..._v22SeedSqls,
        "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
            "sunlight_reward, repeat_rule, is_custom, category) VALUES "
            "('6a1e7d20-1111-4c33-9a55-abcdef012345', '练钢琴30分钟', "
            "4, 0, 30, 9, 'daily', 1, 0);",
        "INSERT INTO reward_templates (id, name, category, base_cost, "
            "freq_limit, cooldown_rule, enabled, content_category) VALUES "
            "('7b2f8e31-2222-4d44-8b66-bcdef0123456', '去海洋馆', "
            "1, 500, 1, 2, 1, 2);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _taskRows(database);
      final List<Map<String, Object?>> rewards = await _rewardRows(database);
      expect(_byId(tasks, '6a1e7d20-1111-4c33-9a55-abcdef012345'), isNotNull);
      expect(_byId(rewards, '7b2f8e31-2222-4d44-8b66-bcdef0123456'), isNotNull);
      expect(tasks, hasLength(10), reason: '9 内置 + 1 自建');
      expect(rewards, hasLength(7), reason: '6 内置 + 1 自建');
    });

    test('幂等：v23 库二次打开不报错、数据稳定', () async {
      final db.AppDatabase database = await _openV22();
      await database.customSelect('SELECT 1').get(); // 二次访问触发 schema 校验
      expect(database.schemaVersion, 24);
      expect(await _taskRows(database), hasLength(9));
      expect(await _rewardRows(database), hasLength(6));
      await database.close();
    });
  });
}
