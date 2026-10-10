/// 迁移回归测试 v21 → v22（**清除 v21 遗留的旧内置种子残留**，C53）。
///
/// 背景（玄参 2026-10-10 真机实证「家长天地默认条目重复」）：v21 换默认种子时，
/// 对「被 check_ins / redemption_requests 引用过的旧种子」采取**保留不断链**策略，
/// 于是 3 条旧奖励残留（选今晚动画片 / 多看一集动画片 / 多玩10分钟），与新种子
/// （看一集动画片 / 睡前多玩10分钟）语义重复。v22 把「内置种子」集合强制对齐到
/// 新 9 任务 + 6 奖励，并把兑换历史重定向到对应新奖励 id。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion == 23`（打开即连锁跑 v22 / v23 / v24）；
///  ② 3 条旧奖励残留（无论有无引用）→ 一律删除，最终恰好 6 条；
///  ③ 被兑换引用的旧奖励 id → 重定向到对应新奖励 id（历史不断链）；
///  ④ 任务侧：is_custom=0 且非新 9 集合的脏行 → 删除；新 9 条原样保留；
///  ⑤ 用户自建项（任务 is_custom=1 / 奖励 UUID id）一律不动；
///  ⑥ 幂等：v22 库二次打开（连锁到 v23 / v24）不报错、数据稳定。
library migration_v21_to_v22_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// v21 schema DDL（与 v20 相同：v21 / v22 均无 DDL 变更）。
List<String> _v21Ddl() => <String>[
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

/// v21 库状态：新 9 条成长任务 + 新 6 条奖励 + **3 条旧奖励残留**（v21 保留所致）。
const List<String> _v21SeedSqls = <String>[
  // ── 新 9 条成长任务（v21 默认版）──
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_homework', '完成学校作业', 3, 1, 20, 8, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_read', '阅读 20 分钟', 0, 0, 15, 8, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_math', '练习数学口算', 1, 1, 15, 6, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_english_read', '指读英语20分钟', 2, 0, 15, 8, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_english_listen', '早上听英语听力15分钟', 2, 0, 15, 6, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_rope_skip', '1分钟跳绳170个以上', 3, 0, 15, 10, 'daily', 0, 2);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_homework_first', '放学后优先完成作业', 3, 0, 15, 5, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_pushup', '10个俯卧撑+10个仰卧起坐', 3, 0, 15, 5, 'daily', 0, 2);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_chores', '帮助家长打扫卫生', 3, 0, 15, 5, 'daily', 0, 3);",
  // ── 新 6 条奖励（v21 默认版）──
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_snack', '小零食', 1, 30, 3, 1, 1, 1);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_cartoon', '看一集动画片', 1, 100, 1, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_extra_play', '睡前多玩10分钟', 1, 20, 3, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_weekend_outing', '周末出去玩', 1, 200, 1, 1, 1, 2);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_toy', '买一个小玩具', 1, 100, 1, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_story', '睡前多听1个故事', 1, 30, 3, 1, 1, 3);",
  // ── 3 条旧奖励残留（v21「保留被引用旧种子」所致）──
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_cartoon_tonight', '选今晚动画片', 1, 40, 1, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_extra_10min', '多玩10分钟', 1, 60, 1, 1, 1, 2);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_extra_episode', '多看一集动画片', 0, 50, 1, 1, 1, 3);",
];

/// 打开一个「v21 旧库」：v21 DDL + 种子 + `user_version = 21`，打开即触发 v22 迁移。
Future<db.AppDatabase> _openV21({List<String> seedSqls = _v21SeedSqls}) async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        for (final String sql in _v21Ddl()) {
          rawDb.execute(sql);
        }
        for (final String sql in seedSqls) {
          rawDb.execute(sql);
        }
        rawDb.execute('PRAGMA user_version = 21;');
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
    'SELECT id, name, base_cost, freq_limit, content_category '
    'FROM reward_templates ORDER BY id;',
  ).get();
  return rows.map((QueryRow r) => r.data).toList();
}

Future<String?> _redemptionTemplateId(
  db.AppDatabase database,
  String requestId,
) async {
  final List<QueryRow> rows = await database.customSelect(
    'SELECT template_id FROM redemption_requests WHERE id = ?;',
    variables: <Variable>[Variable<String>(requestId)],
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
  group('迁移 v21->v22：清除旧内置种子残留（C53）', () {
    test('schemaVersion 必须为最新 24（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV21(seedSqls: const <String>[]);
      addTearDown(database.close);
      expect(database.schemaVersion, 24);
    });

    test('3 条旧奖励残留一律删除（含被引用者），最终恰好 6 条', () async {
      final db.AppDatabase database = await _openV21(seedSqls: <String>[
        ..._v21SeedSqls,
        "INSERT INTO redemption_requests (id, template_id, requested_at, "
            "cost, status) VALUES ('rr_1', 'seed_extra_episode', "
            "1700000000000, 50, 0);",
        "INSERT INTO redemption_requests (id, template_id, requested_at, "
            "cost, status) VALUES ('rr_2', 'seed_extra_10min', "
            "1700000000000, 60, 0);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> rewards = await _rewardRows(database);
      expect(rewards, hasLength(6), reason: '旧 3 条残留被清、新 6 条保留');
      expect(_byId(rewards, 'seed_cartoon_tonight'), isNull);
      expect(_byId(rewards, 'seed_extra_10min'), isNull);
      expect(_byId(rewards, 'seed_extra_episode'), isNull);
      expect(_byId(rewards, 'seed_cartoon'), isNotNull);
      expect(_byId(rewards, 'seed_extra_play'), isNotNull);
      expect(_byId(rewards, 'seed_toy'), isNotNull);
      expect(_byId(rewards, 'seed_story'), isNotNull);

      // 兑换历史重定向到新奖励 id —— 历史链接不断。
      expect(await _redemptionTemplateId(database, 'rr_1'), 'seed_cartoon',
          reason: '多看一集动画片 → 看一集动画片');
      expect(await _redemptionTemplateId(database, 'rr_2'), 'seed_extra_play',
          reason: '多玩10分钟 → 睡前多玩10分钟');
    });

    test('无引用的旧奖励残留同样被清除', () async {
      final db.AppDatabase database = await _openV21();
      addTearDown(database.close);

      final List<Map<String, Object?>> rewards = await _rewardRows(database);
      expect(rewards, hasLength(6));
      expect(_byId(rewards, 'seed_cartoon_tonight'), isNull);
      expect(_byId(rewards, 'seed_extra_episode'), isNull);
    });

    test('任务：is_custom=0 旧脏行删除、新 9 条原样保留', () async {
      final db.AppDatabase database = await _openV21(seedSqls: <String>[
        ..._v21SeedSqls,
        "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
            "sunlight_reward, repeat_rule, is_custom, category) "
            "VALUES ('seed_task_legacy_x', '旧版遗留任务', 3, 0, 15, 5, "
            "'daily', 0, 1);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _taskRows(database);
      expect(tasks, hasLength(9), reason: '旧脏行被清、新 9 条保留');
      expect(_byId(tasks, 'seed_task_legacy_x'), isNull);
      expect(_byId(tasks, 'seed_task_homework'), isNotNull);
      expect(_byId(tasks, 'seed_task_chores'), isNotNull);
    });

    test('用户自建项（任务 is_custom=1 / 奖励 UUID id）一律不动', () async {
      final db.AppDatabase database = await _openV21(seedSqls: <String>[
        ..._v21SeedSqls,
        "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
            "sunlight_reward, repeat_rule, is_custom, category) "
            "VALUES ('6a1e7d20-1111-4c33-9a55-abcdef012345', '练钢琴30分钟', "
            "4, 0, 30, 9, 'daily', 1, 0);",
        "INSERT INTO reward_templates (id, name, category, base_cost, "
            "freq_limit, cooldown_rule, enabled, content_category) "
            "VALUES ('7b2f8e31-2222-4d44-8b66-bcdef0123456', '去海洋馆', "
            "1, 500, 1, 2, 1, 2);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _taskRows(database);
      final List<Map<String, Object?>> rewards = await _rewardRows(database);
      final Map<String, Object?>? mineTask =
          _byId(tasks, '6a1e7d20-1111-4c33-9a55-abcdef012345');
      final Map<String, Object?>? mineReward =
          _byId(rewards, '7b2f8e31-2222-4d44-8b66-bcdef0123456');
      expect(mineTask, isNotNull, reason: '自建任务（is_custom=1）不动');
      expect(mineTask!['name'], '练钢琴30分钟');
      expect(mineReward, isNotNull, reason: '自建奖励（UUID id）不动');
      expect(mineReward!['base_cost'], 500);
      expect(tasks, hasLength(10), reason: '9 种子 + 1 自建');
      expect(rewards, hasLength(7), reason: '6 种子 + 1 自建');
    });

    test('幂等：v22 库二次打开（连锁到 v23 / v24）不报错、数据稳定', () async {
      final db.AppDatabase database = await _openV21();
      await database.customSelect('SELECT 1').get(); // 二次访问触发 schema 校验
      expect(database.schemaVersion, 24);
      expect(await _taskRows(database), hasLength(9));
      expect(await _rewardRows(database), hasLength(6));
      await database.close();
    });
  });
}
