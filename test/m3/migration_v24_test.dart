/// 迁移回归测试 v23 → v24（**补齐内置种子**，C55）。
///
/// 背景（玄参 2026-10-10 真机实证，离线解密真机库确认、非推测）：该设备上 C52 的
/// 9 任务 + 6 奖励新增项**从未落库**（内置集合仍是早期 3 任务 + 4 奖励，字段值与新
/// 默认一字不差、仅缺行）；玄参为凑齐手动补了同名条目，而 v23 的「同名去重」假设
/// 「同名内置行一定存在」→ 删掉手动条目后只剩内置那 3 + 4。
///
/// v24 口径（**只补不删、不覆盖**）：对 9 条成长任务 / 6 条奖励逐条 `INSERT OR IGNORE`
/// —— id 已存在则整行跳过（家长改过的价 / 名 / 删一律尊重），id 缺失才补默认行。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion == 24`；
///  ② 真机态（仅 3 任务 + 4 奖励）→ 打开后补齐为 9 + 6，且补入行字段值正确；
///  ③ 已存在的内置行**不被覆盖**（家长改过的值原样保留）；
///  ④ 用户自建项（UUID id）一律不动；
///  ⑤ 幂等：v24 库二次打开数据稳定；
///  ⑥ 端到端：v20 旧库（3 任务 + 5 奖励）直通最新 → 9 + 6。
library migration_v24_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// v23 schema DDL（v21 起无 DDL 变更，与 v22 / v23 相同）。
List<String> _ddl() => <String>[
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

/// **真机态** v23 库：仅早期 3 条成长任务 + 4 条奖励（字段值与新默认一致，只是缺行）。
const List<String> _deviceStateSeed = <String>[
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_homework', '完成学校作业', 3, 1, 20, 8, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_read', '阅读 20 分钟', 0, 0, 15, 8, 'daily', 0, 1);",
  "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_math', '练习数学口算', 1, 1, 15, 6, 'daily', 0, 1);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_snack', '小零食', 1, 30, 3, 1, 1, 1);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_cartoon', '看一集动画片', 1, 100, 1, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_extra_play', '睡前多玩10分钟', 1, 20, 3, 1, 1, 3);",
  "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_weekend_outing', '周末出去玩', 1, 200, 1, 1, 1, 2);",
];

/// v24 应补齐的 6 任务 / 2 奖励 id。
const List<String> _expectedMissingTaskIds = <String>[
  'seed_task_english_read',
  'seed_task_english_listen',
  'seed_task_rope_skip',
  'seed_task_homework_first',
  'seed_task_pushup',
  'seed_task_chores',
];
const List<String> _expectedMissingRewardIds = <String>['seed_toy', 'seed_story'];

/// 打开一个「v23 旧库」：v23 DDL + 种子 + `user_version = 23`，打开即触发 v24 迁移。
Future<db.AppDatabase> _openV23({List<String> seedSqls = _deviceStateSeed}) async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        for (final String sql in _ddl()) {
          rawDb.execute(sql);
        }
        for (final String sql in seedSqls) {
          rawDb.execute(sql);
        }
        rawDb.execute('PRAGMA user_version = 23;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get();
  return database;
}

Future<List<Map<String, Object?>>> _tasks(db.AppDatabase d) async {
  final List<QueryRow> rows = await d
      .customSelect('SELECT id, name, is_custom, sunlight_reward, category '
          'FROM tasks ORDER BY id;')
      .get();
  return rows.map((QueryRow r) => r.data).toList();
}

Future<List<Map<String, Object?>>> _rewards(db.AppDatabase d) async {
  final List<QueryRow> rows = await d
      .customSelect('SELECT id, name, base_cost, content_category '
          'FROM reward_templates ORDER BY id;')
      .get();
  return rows.map((QueryRow r) => r.data).toList();
}

Map<String, Object?>? _byId(List<Map<String, Object?>> rows, String id) {
  for (final Map<String, Object?> r in rows) {
    if (r['id'] == id) return r;
  }
  return null;
}

void main() {
  group('迁移 v23->v24：补齐内置种子（C55）', () {
    test('schemaVersion 必须为最新 24（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database =
          await _openV23(seedSqls: const <String>[]);
      addTearDown(database.close);
      expect(database.schemaVersion, 24);
    });

    test('真机态（3 任务 + 4 奖励）→ 补齐为 9 + 6，且补入行字段值正确', () async {
      final db.AppDatabase database = await _openV23();
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _tasks(database);
      final List<Map<String, Object?>> rewards = await _rewards(database);
      expect(tasks, hasLength(9), reason: '3 条内置 + 补 6 条 = 9');
      expect(rewards, hasLength(6), reason: '4 条内置 + 补 2 条 = 6');

      for (final String id in _expectedMissingTaskIds) {
        expect(_byId(tasks, id), isNotNull, reason: '应补齐 $id');
      }
      for (final String id in _expectedMissingRewardIds) {
        expect(_byId(rewards, id), isNotNull, reason: '应补齐 $id');
      }

      // 抽查补入行字段值（与 task_seed / reward_seed 新默认一致）。
      final Map<String, Object?> chores = _byId(tasks, 'seed_task_chores')!;
      expect(chores['name'], '帮助家长打扫卫生');
      expect(chores['is_custom'], 0);
      expect(chores['sunlight_reward'], 5);
      expect(chores['category'], 3);
      final Map<String, Object?> rope =
          _byId(tasks, 'seed_task_rope_skip')!;
      expect(rope['sunlight_reward'], 10);
      expect(rope['category'], 2);
      final Map<String, Object?> story = _byId(rewards, 'seed_story')!;
      expect(story['name'], '睡前多听1个故事');
      expect(story['base_cost'], 30);
      final Map<String, Object?> toy = _byId(rewards, 'seed_toy')!;
      expect(toy['base_cost'], 100);
    });

    test('已存在的内置行不被覆盖（家长改过的值原样保留）', () async {
      final db.AppDatabase database = await _openV23(seedSqls: <String>[
        // 内置 id，但家长改过名 + 改过阳光奖励。
        "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, "
            "sunlight_reward, repeat_rule, is_custom, category) VALUES "
            "('seed_task_homework', '作业（家长改名）', 3, 1, 25, 99, "
            "'daily', 0, 1);",
        // 内置奖励 id，但家长改过价格。
        "INSERT INTO reward_templates (id, name, category, base_cost, "
            "freq_limit, cooldown_rule, enabled, content_category) VALUES "
            "('seed_snack', '小零食', 1, 88, 3, 1, 1, 1);",
      ]);
      await database.customSelect('SELECT 1').get(); // 触发 v24
      addTearDown(database.close);

      final List<Map<String, Object?>> tasks = await _tasks(database);
      final List<Map<String, Object?>> rewards = await _rewards(database);
      final Map<String, Object?> hw = _byId(tasks, 'seed_task_homework')!;
      expect(hw['name'], '作业（家长改名）', reason: '既有行不被 v24 覆盖');
      expect(hw['sunlight_reward'], 99);
      final Map<String, Object?> snack = _byId(rewards, 'seed_snack')!;
      expect(snack['base_cost'], 88, reason: '既有奖励价格不被覆盖');
      // 其余缺失项仍补齐。
      expect(tasks, hasLength(9));
      expect(rewards, hasLength(6));
    });

    test('用户自建项（UUID id）一律不动', () async {
      final db.AppDatabase database = await _openV23(seedSqls: <String>[
        ..._deviceStateSeed,
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

      final List<Map<String, Object?>> tasks = await _tasks(database);
      final List<Map<String, Object?>> rewards = await _rewards(database);
      expect(_byId(tasks, '6a1e7d20-1111-4c33-9a55-abcdef012345'), isNotNull);
      expect(_byId(rewards, '7b2f8e31-2222-4d44-8b66-bcdef0123456'), isNotNull);
      expect(tasks, hasLength(10), reason: '9 内置 + 1 自建');
      expect(rewards, hasLength(7), reason: '6 内置 + 1 自建');
    });

    test('幂等：v24 库二次打开不报错、数据稳定', () async {
      final db.AppDatabase database = await _openV23();
      await database.customSelect('SELECT 1').get(); // 二次访问触发 schema 校验
      expect(database.schemaVersion, 24);
      expect(await _tasks(database), hasLength(9));
      expect(await _rewards(database), hasLength(6));
      await database.close();
    });

    test('端到端：v20 旧库（3 任务 + 5 奖励）直通最新 → 9 + 6', () async {
      final db.AppDatabase database = db.AppDatabase(
        NativeDatabase.memory(
          setup: (rawDb) {
            for (final String sql in _ddl()) {
              rawDb.execute(sql);
            }
            for (final String sql in <String>[
              "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_homework', '完成学校作业', 3, 1, 15, 12, 'daily', 0, 1);",
              "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_read', '阅读 20 分钟', 0, 0, 15, 12, 'daily', 0, 1);",
              "INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, sunlight_reward, repeat_rule, is_custom, category) VALUES ('seed_task_math', '练习数学口算', 1, 1, 15, 12, 'weekly', 0, 1);",
              "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_snack', '小零食', 1, 30, 3, 1, 1, 1);",
              "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_cartoon_tonight', '选今晚动画片', 1, 100, 1, 1, 1, 3);",
              "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_extra_10min', '多玩10分钟', 1, 20, 3, 1, 1, 3);",
              "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_weekend_outing', '周末出去玩', 1, 200, 1, 1, 1, 2);",
              "INSERT INTO reward_templates (id, name, category, base_cost, freq_limit, cooldown_rule, enabled, content_category) VALUES ('seed_extra_episode', '多看一集动画片', 1, 100, 1, 1, 1, 3);",
            ]) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 20;');
          },
        ),
      );
      await database.customSelect('SELECT 1').get();
      addTearDown(database.close);

      expect(database.schemaVersion, 24);
      expect(await _tasks(database), hasLength(9));
      expect(await _rewards(database), hasLength(6));
    });
  });
}
