/// 迁移回归测试 v8 → v9（M5，成长项/奖励内容分类）：
/// `tasks` 新增 `category` 列（[TaskCategory]）+ `reward_templates` 新增 `content_category` 列
/// （[RewardContentCategory]）。
///
/// 两列均为 `IntColumn` 带默认值 0（=other）的 `ALTER TABLE ADD COLUMN`，历史行取默认值 0
/// → 读作「其他」，避免历史数据被误判成具体分类（学习/运动/生活 / 零食/游玩/娱乐）。
///
/// 本测试钉死四件事（**必须把历史行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 9`；
///  ② v8 → v9 后 `tasks` 表存在 `category` 列、`reward_templates` 表存在 `content_category` 列；
///  ③ 历史成长项 / 奖励（v8 无该列）的**其它字段原样保留**，新列取默认值 0（= other）；
///  ④ 幂等：已迁移到 v9 的库重复打开不报错、列仍在、数据不丢；
///     以及跨版本跳跃（v6 → v9）也要覆盖（中间版本补列逻辑仍须执行）。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**，
///    故「老库」DDL 的日期列一律用 `INTEGER`（秒），否则读回会因类型不匹配而失败。
library migration_v8_to_v9_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// 按版本特征拼「老库」建表 DDL。v8 与 v7 的 `tasks` / `reward_templates` 结构一致
/// （v8 只在 `plants` 加了 bloomed_at，与本次分类列无关），故这里给出 v8 的
/// `tasks`（**无** category 列）/ `reward_templates`（**无** content_category 列）。
List<String> _schemaDdl({required bool withLegacyRows}) {
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
        'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, '
        'PRIMARY KEY (id));',
    'CREATE TABLE plants ('
        'id TEXT NOT NULL, species_id TEXT NOT NULL, pot_index INTEGER NOT NULL, '
        'stage INTEGER NOT NULL, stage_started_at INTEGER NOT NULL, '
        'growth_progress REAL NOT NULL DEFAULT 0.0, growth_factor REAL NOT NULL DEFAULT 1.0, '
        'water_used INTEGER NOT NULL DEFAULT 0, fertilizer_used INTEGER NOT NULL DEFAULT 0, '
        'status INTEGER NOT NULL, planted_at INTEGER NOT NULL, '
        'last_water_at INTEGER, wilted_at INTEGER, dead_at INTEGER, bloomed_at INTEGER, '
        'mood INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
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
        'PRIMARY KEY (id));',
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
        'repeat_rule TEXT, is_custom INTEGER NOT NULL, PRIMARY KEY (id));',
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
    if (withLegacyRows) ...<String>[
      'INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, '
          'sunlight_reward, repeat_rule, is_custom) '
          'VALUES (\'t_old\', \'老成长项\', ${TaskSubject.math.index}, 0, 15, 12, \'daily\', 0);',
      'INSERT INTO reward_templates (id, name, category, base_cost, cooldown_rule, enabled) '
          'VALUES (\'r_old\', \'老奖励\', ${RewardCategory.parentHandled.index}, 30, 1, 1);',
    ],
  ];
}

/// 读取某表当前所有列名（PRAGMA table_info）。
Future<Set<String>> _columns(db.AppDatabase database, String table) async {
  final List<QueryRow> rows =
      await database.customSelect('PRAGMA table_info($table);').get();
  return rows.map((QueryRow r) => r.read<String>('name')).toSet();
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
  await database.customSelect('SELECT 1').get(); // 触发迁移
  addTearDown(() => database.close());
  return database;
}

/// 读历史成长项的 category 列（直接读物理列，避免依赖 DAO 字段名）。
Future<int> _taskCategory(db.AppDatabase database, String id) async {
  final List<QueryRow> rows = await database
      .customSelect('SELECT category FROM tasks WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(id)])
      .get();
  return rows.first.read<int>('category');
}

/// 读历史奖励的 content_category 列。
Future<int> _rewardContentCategory(db.AppDatabase database, String id) async {
  final List<QueryRow> rows = await database
      .customSelect('SELECT content_category FROM reward_templates WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(id)])
      .get();
  return rows.first.read<int>('content_category');
}

void main() {
  group('迁移 v8->v9：tasks.category + reward_templates.content_category', () {
    test('schemaVersion 必须为 9（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyRows: true),
        8,
      );
      expect(database.schemaVersion, 9);
    });

    test('迁移后 tasks 出现 category 列、reward_templates 出现 content_category 列',
        () async {
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyRows: true),
        8,
      );
      expect(await _columns(database, 'tasks'), contains('category'));
      expect(await _columns(database, 'reward_templates'),
          contains('content_category'));
    });

    test('历史成长项/奖励其它字段原样保留，新列取默认值 0（= other）', () async {
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyRows: true),
        8,
      );
      // 历史成长项：category 默认 0 = TaskCategory.other。
      expect(await _taskCategory(database, 't_old'), TaskCategory.other.index);
      // 历史奖励：content_category 默认 0 = RewardContentCategory.other。
      expect(await _rewardContentCategory(database, 'r_old'),
          RewardContentCategory.other.index);
      // 其它字段未丢失。
      final QueryRow task = (await database
              .customSelect('SELECT name, subject FROM tasks WHERE id = ?',
                  variables: <Variable<Object>>[const Variable<String>('t_old')])
              .get())
          .first;
      expect(task.read<String>('name'), '老成长项');
      expect(task.read<int>('subject'), TaskSubject.math.index);
    });

    test('迁移后可写入/读回带分类的行（往返不炸）', () async {
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyRows: false),
        8,
      );
      await database.customStatement(
        'INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, '
        'sunlight_reward, repeat_rule, is_custom, category) '
        'VALUES (\'t_new\', \'新成长项\', ${TaskSubject.chinese.index}, 1, 20, 18, '
        '\'daily\', 0, ${TaskCategory.learning.index});',
      );
      await database.customStatement(
        'INSERT INTO reward_templates (id, name, category, base_cost, '
        'cooldown_rule, enabled, content_category) '
        'VALUES (\'r_new\', \'新奖励\', ${RewardCategory.selfService.index}, 25, 1, '
        '1, ${RewardContentCategory.snacks.index});',
      );
      expect(await _taskCategory(database, 't_new'), TaskCategory.learning.index);
      expect(await _rewardContentCategory(database, 'r_new'),
          RewardContentCategory.snacks.index);
    });

    test('幂等：已迁移到 v9 的库重复打开不报错、列仍在、历史行原样保留', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v9');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _schemaDdl(withLegacyRows: true)) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 8;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 9);
      expect(await _columns(first, 'tasks'), contains('category'));
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();

      expect(await _columns(second, 'tasks'), contains('category'));
      expect(await _columns(second, 'reward_templates'),
          contains('content_category'));
      expect(await _taskCategory(second, 't_old'), TaskCategory.other.index);
      expect(await _rewardContentCategory(second, 'r_old'),
          RewardContentCategory.other.index);
    });

    test('跨版本跳跃升级 v6 → v9：中间补列逻辑仍执行', () async {
      final db.AppDatabase database = await _openMigrated(
        _schemaDdl(withLegacyRows: true),
        6,
      );
      expect(database.schemaVersion, 9);
      // v8→v9 补列分支执行：category / content_category 列存在。
      expect(await _columns(database, 'tasks'), contains('category'));
      expect(await _columns(database, 'reward_templates'),
          contains('content_category'));
      // 历史行默认 other。
      expect(await _taskCategory(database, 't_old'), TaskCategory.other.index);
      expect(await _rewardContentCategory(database, 'r_old'),
          RewardContentCategory.other.index);
    });
  });
}
