/// 迁移回归测试 v20 → v21（**默认种子数据替换**：成长任务 3 → 9、奖励 5 → 6，C52）。
///
/// 背景（玄参 2026-10-10 截图拍板）：旧种子（3 任务 + 5 奖励）是 M3 占位版，
/// 换成玄参默认版（9 任务 + 6 奖励，价格/科目/分类/联动专注/周限全按截图）。
/// 分类枚举追加（习惯/玩具/阅读）纯 Dart 层、无 DDL 变更，故 v21 为**纯数据迁移**。
///
/// 本测试钉死六件事：
///  ① `AppDatabase.schemaVersion == 23`（打开即连锁跑 v21 / v22 / v23 / v24）；
///  ② 旧种子**无**历史引用 → 删除，新 9+6 默认行就位（含价格/联动/分类值）；
///  ③ 旧种子**有**打卡/兑换历史引用 → 保留（id 不断链），同 id 新默认值覆盖；
///  ④ 不在新种子 id 集内的被引用旧奖励 → v22 重定向引用到新奖励并**清除残留**；
///  ⑤ 用户自建项（is_custom=1 / 其他 id）一律不动；
///  ⑥ 幂等：最新库二次打开不报错、数据稳定。
///  ⚠️ 本测试经 v20 库**直通最新版**（v21 + v22 两个迁移都会执行），故断言均反映
///     **最终态**；v22 的清理细节另见 `migration_v21_to_v22_test.dart`。
library migration_v20_to_v21_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// v20 schema DDL：与 `migration_v19_to_v20_test.dart` 标定的 DDL 一致
/// （v20 / v21 均无 DDL 变更）。
List<String> _v20Ddl() => <String>[
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

/// 旧种子（v20 及之前 ensure* 播的占位版）。
const List<String> _oldSeedSqls = <String>[
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
      "sunlight_reward, repeat_rule, is_custom, category) "
      "VALUES ('seed_task_homework', '完成学校作业', 3, 1, 15, 12, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
      "sunlight_reward, repeat_rule, is_custom, category) "
      "VALUES ('seed_task_read', '阅读 20 分钟', 0, 0, 15, 12, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
      "sunlight_reward, repeat_rule, is_custom, category) "
      "VALUES ('seed_task_math', '练习数学口算', 1, 1, 15, 12, 'weekly', 0, 1);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, "
      "cooldown_rule, enabled, content_category) "
      "VALUES ('seed_snack', '小零食', 1, 20, 1, 1, 1, 1);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, "
      "cooldown_rule, enabled, content_category) "
      "VALUES ('seed_cartoon_tonight', '选今晚动画片', 1, 40, 1, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, "
      "cooldown_rule, enabled, content_category) "
      "VALUES ('seed_extra_10min', '多玩10分钟', 1, 60, 1, 1, 1, 2);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, "
      "cooldown_rule, enabled, content_category) "
      "VALUES ('seed_weekend_outing', '周末出去玩', 1, 120, 1, 1, 1, 2);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, "
      "cooldown_rule, enabled, content_category) "
      "VALUES ('seed_extra_episode', '多看一集动画片', 0, 50, 1, 1, 1, 3);",
];

/// 打开一个「v20 旧库」：v20 DDL + 种子 + `user_version = 20`，打开即触发迁移。
Future<db.AppDatabase> _openV20({List<String> seedSqls = _oldSeedSqls}) async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        for (final String sql in _v20Ddl()) {
          rawDb.execute(sql);
        }
        for (final String sql in seedSqls) {
          rawDb.execute(sql);
        }
        rawDb.execute('PRAGMA user_version = 20;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get(); // 触发迁移
  return database;
}

Future<List<Map<String, Object?>>> _taskRows(db.AppDatabase database) async {
  final List<QueryRow> rows = await database.customSelect(
    'SELECT id, name, subject, requires_focus, min_focus_min, sunlight_reward, '
    'repeat_rule, is_custom, category FROM tasks ORDER BY id;',
  ).get();
  return rows.map((QueryRow r) => r.data).toList();
}

Future<List<Map<String, Object?>>> _rewardRows(db.AppDatabase database) async {
  final List<QueryRow> rows = await database.customSelect(
    'SELECT id, name, category, base_cost, freq_limit, cooldown_rule, enabled, '
    'content_category FROM reward_templates ORDER BY id;',
  ).get();
  return rows.map((QueryRow r) => r.data).toList();
}

Map<String, Object?>? _byId(List<Map<String, Object?>> rows, String id) {
  for (final Map<String, Object?> r in rows) {
    if (r['id'] == id) return r;
  }
  return null;
}

void main() {
  group('迁移 v20->v21：默认种子数据替换（C52）', () {
    test('schemaVersion 必须为最新 24（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV20(seedSqls: const <String>[]);
      addTearDown(database.close);
      expect(database.schemaVersion, 24);
    });

    test('旧种子无历史引用 → 删除，新 9+6 默认行就位（含价格/联动/分类值）', () async {
      final db.AppDatabase database = await _openV20();
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _taskRows(database);
      final List<Map<String, Object?>> rewards = await _rewardRows(database);
      expect(tasks, hasLength(9), reason: '旧 3 条种子被删、新 9 条就位');
      expect(rewards, hasLength(6), reason: '旧 5 条种子被删、新 6 条就位');

      // 旧 id（不在新集合的）确认消失。
      expect(_byId(tasks, 'seed_task_math'), isNotNull,
          reason: 'seed_task_math 同 id 进新集合，应被新默认值覆盖');
      expect(_byId(tasks, 'seed_task_english_read'), isNotNull);
      expect(_byId(rewards, 'seed_cartoon_tonight'), isNull,
          reason: '旧「选今晚动画片」被删');
      expect(_byId(rewards, 'seed_extra_10min'), isNull);
      expect(_byId(rewards, 'seed_extra_episode'), isNull);

      // 新默认值抽查（玄参截图口径）。
      final Map<String, Object?>? homework = _byId(tasks, 'seed_task_homework');
      expect(homework, isNotNull);
      expect(homework!['sunlight_reward'], 8);
      expect(homework['requires_focus'], 1);
      expect(homework['min_focus_min'], 20);
      expect(homework['category'], 1); // learning
      expect(homework['repeat_rule'], 'daily');

      final Map<String, Object?>? rope = _byId(tasks, 'seed_task_rope_skip');
      expect(rope, isNotNull);
      expect(rope!['sunlight_reward'], 10);
      expect(rope['category'], 2); // sports

      final Map<String, Object?>? chores = _byId(tasks, 'seed_task_chores');
      expect(chores, isNotNull);
      expect(chores!['category'], 3); // life
      expect(chores['sunlight_reward'], 5);

      final Map<String, Object?>? snack = _byId(rewards, 'seed_snack');
      expect(snack, isNotNull);
      expect(snack!['base_cost'], 30);
      expect(snack['freq_limit'], 3);
      expect(snack['content_category'], 1); // snacks
      expect(snack['category'], 1); // parentHandled

      final Map<String, Object?>? outing = _byId(rewards, 'seed_weekend_outing');
      expect(outing, isNotNull);
      expect(outing!['base_cost'], 200);
      expect(outing['freq_limit'], 1);
      expect(outing['content_category'], 2); // play

      final Map<String, Object?>? toy = _byId(rewards, 'seed_toy');
      expect(toy, isNotNull);
      expect(toy!['base_cost'], 100);
      expect(toy['content_category'], 3); // entertainment
    });

    test('被打卡引用的旧种子保留（id 不断链），同 id 行更新为新默认值', () async {
      final db.AppDatabase database = await _openV20(seedSqls: <String>[
        ..._oldSeedSqls,
        "INSERT INTO check_ins (id, task_id, date, completed_at, "
            "is_perfect_day) VALUES ('ci_1', 'seed_task_homework', "
            "1700000000000, 1700000000000, 0);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _taskRows(database);
      final Map<String, Object?>? homework = _byId(tasks, 'seed_task_homework');
      expect(homework, isNotNull, reason: '被 check_ins 引用，id 必须保留');
      // 同 id 进新集合 → REPLACE 为新默认值（历史行引用的 id 不变，不断链）。
      expect(homework!['sunlight_reward'], 8);
      expect(homework['min_focus_min'], 20);

      // 打卡历史行原样保留。
      final List<QueryRow> ci = await database.customSelect(
        'SELECT id, task_id FROM check_ins;',
      ).get();
      expect(ci, hasLength(1));
      expect(ci.single.data['task_id'], 'seed_task_homework');
    });

    test('被兑换引用的旧奖励 → v22 重定向引用并清除残留（不断链）', () async {
      final db.AppDatabase database = await _openV20(seedSqls: <String>[
        ..._oldSeedSqls,
        "INSERT INTO redemption_requests (id, template_id, requested_at, "
            "cost, status) VALUES ('rr_1', 'seed_extra_episode', "
            "1700000000000, 50, 0);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> rewards = await _rewardRows(database);
      // v21 曾保留被引用的旧奖励；v22 把它清除、并把引用重定向到新奖励。
      expect(_byId(rewards, 'seed_extra_episode'), isNull,
          reason: 'v22 起旧奖励残留被清除，不再与新种子并存');
      expect(rewards, hasLength(6), reason: '最终恰好 6 条默认奖励');

      // 兑换历史重定向到新奖励 id —— 历史链接不断。
      final List<QueryRow> rr = await database.customSelect(
        'SELECT template_id FROM redemption_requests WHERE id = ?;',
        variables: <Variable>[const Variable<String>('rr_1')],
      ).get();
      expect(rr.single.data['template_id'], 'seed_cartoon');

      // 其余旧种子（无引用）仍被正常替换。
      expect(_byId(rewards, 'seed_cartoon_tonight'), isNull);
      expect(_byId(rewards, 'seed_snack')!['base_cost'], 30);
    });

    test('用户自建项（is_custom=1 / 其他 id）一律不动', () async {
      final db.AppDatabase database = await _openV20(seedSqls: <String>[
        ..._oldSeedSqls,
        "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
            "sunlight_reward, repeat_rule, is_custom, category) "
            "VALUES ('custom_my_task', '练钢琴30分钟', 4, 0, 30, 9, 'daily', 1, 0);",
        "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, "
            "cooldown_rule, enabled, content_category) "
            "VALUES ('custom_my_reward', '去海洋馆', 1, 500, 1, 2, 1, 2);",
      ]);
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _taskRows(database);
      final Map<String, Object?>? mine = _byId(tasks, 'custom_my_task');
      expect(mine, isNotNull);
      expect(mine!['name'], '练钢琴30分钟');
      expect(mine['sunlight_reward'], 9);
      expect(mine['is_custom'], 1);

      final List<Map<String, Object?>> rewards = await _rewardRows(database);
      final Map<String, Object?>? myReward = _byId(rewards, 'custom_my_reward');
      expect(myReward, isNotNull);
      expect(myReward!['name'], '去海洋馆');
      expect(myReward['base_cost'], 500);
      expect(myReward['cooldown_rule'], 2); // monthly 原值
    });

    test('幂等：v21 库二次打开不报错、数据稳定', () async {
      final db.AppDatabase database = await _openV20();
      await database.customSelect('SELECT 1').get(); // 二次访问触发 schema 校验
      expect(database.schemaVersion, 24);
      final List<Map<String, Object?>> tasks = await _taskRows(database);
      final List<Map<String, Object?>> rewards = await _rewardRows(database);
      expect(tasks, hasLength(9));
      expect(rewards, hasLength(6));
      await database.close();
    });
  });
}
