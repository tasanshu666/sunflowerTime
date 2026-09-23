/// 迁移回归测试 v4 → v5（§5 验收证据）：`tasks.custom_subject` 补列。
///
/// 背景（真机踩坑，必读）：M3 修订给任务加「自定义科目」，`Tasks` 表新增
/// `custom_subject` 列、`schemaVersion` 应为 5。首次打包时 **`schemaVersion`
/// 仍停留在 4**（编辑被静默吞掉），于是 drift 认为无需升级、`onUpgrade` 根本不跑，
/// 列永远补不上 → 真机保存自定义科目时报：
///   `SqliteException(1): table tasks has no column named custom_subject`
///
/// 关键教训：**光升 `schemaVersion` 不够，光加 `_ensureColumn` 也不够，两者缺一不可**；
/// 而且 `flutter analyze` 与常规单测都抓不到（4 和 5 都是合法 Dart），
/// 只能靠「拿老库真跑一次迁移」来验。故本测试钉死三件事：
///  ① `AppDatabase.schemaVersion == 5`（版本号与建表改动不许脱节）；
///  ② v4 老库升级后 `custom_subject` 存在、历史行取 NULL、写入/读回成功；
///  ③ **跨版本跳跃**（v3 直跳 v5）也补得齐（plants 表 + garden_pot_capacity + custom_subject）。
library migration_v4_to_v5_test;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// 按版本特征拼「老库」建表 DDL。
///
/// 三个开关对应三代 schema 的增量，组合即可还原 v3 / v4：
///  · [withPlantsTable] / [withGardenPotCapacity]：M3（v4）新增的植物表与花园容量列；
///  · [withCustomSubject]：本次修订（v5）新增的自定义科目列。
///
/// 库内预置一条 v3/v4 时代的历史任务，用于断言「迁移不丢数据、新列为 NULL」。
List<String> _schemaDdl({
  required bool withPlantsTable,
  required bool withGardenPotCapacity,
  required bool withCustomSubject,
}) {
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
        '${withGardenPotCapacity ? 'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, ' : ''}'
        'PRIMARY KEY (id));',
    if (withPlantsTable)
      'CREATE TABLE plants ('
          'id TEXT NOT NULL, '
          'species_id TEXT NOT NULL, '
          'pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, '
          'stage_started_at TEXT NOT NULL, '
          'growth_progress REAL NOT NULL DEFAULT 0.0, '
          'growth_factor REAL NOT NULL DEFAULT 1.0, '
          'water_used INTEGER NOT NULL DEFAULT 0, '
          'fertilizer_used INTEGER NOT NULL DEFAULT 0, '
          'status INTEGER NOT NULL, '
          'planted_at TEXT NOT NULL, '
          'last_water_at TEXT, '
          'wilted_at TEXT, '
          'dead_at TEXT, '
          'mood INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id));',
    'CREATE TABLE focus_sessions ('
        'id TEXT NOT NULL, '
        'start TEXT NOT NULL, '
        'end TEXT, '
        'planned_min INTEGER NOT NULL, '
        'actual_focus_min REAL NOT NULL, '
        'status INTEGER NOT NULL, '
        'sunlight_earned REAL NOT NULL, '
        'created_at TEXT NOT NULL, '
        'PRIMARY KEY (id));',
    'CREATE TABLE sunlight_ledgers ('
        'id TEXT NOT NULL, '
        'ts TEXT NOT NULL, '
        'type INTEGER NOT NULL, '
        'gross REAL NOT NULL, '
        'net REAL NOT NULL, '
        'balance_after REAL NOT NULL, '
        'ref_type TEXT, '
        'ref_id TEXT, '
        'day_key TEXT NOT NULL, '
        'PRIMARY KEY (id));',
    'CREATE TABLE reward_templates ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'category INTEGER NOT NULL, '
        'base_cost INTEGER NOT NULL DEFAULT 50, '
        'freq_limit INTEGER, '
        'cooldown_rule INTEGER NOT NULL DEFAULT 1, '
        'enabled INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id));',
    'CREATE TABLE redemption_requests ('
        'id TEXT NOT NULL, '
        'template_id TEXT NOT NULL, '
        'requested_at TEXT NOT NULL, '
        'cost INTEGER NOT NULL, '
        'status INTEGER NOT NULL, '
        'auto_approved INTEGER NOT NULL DEFAULT 0, '
        'queue_position INTEGER, '
        'verified_at TEXT, '
        'parent_note TEXT, '
        'child_id TEXT NOT NULL DEFAULT \'single-child\', '
        'PRIMARY KEY (id));',
    'CREATE TABLE monthly_pools ('
        'month_key TEXT NOT NULL, '
        'budget INTEGER NOT NULL, '
        'used INTEGER NOT NULL DEFAULT 0, '
        'auto_released INTEGER NOT NULL DEFAULT 0, '
        'reset_at TEXT NOT NULL, '
        'PRIMARY KEY (month_key));',
    // tasks：v5 之前无 custom_subject
    'CREATE TABLE tasks ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'subject INTEGER NOT NULL, '
        '${withCustomSubject ? 'custom_subject TEXT, ' : ''}'
        'requires_focus INTEGER NOT NULL, '
        'min_focus_min INTEGER NOT NULL DEFAULT 15, '
        'sunlight_reward INTEGER NOT NULL DEFAULT 12, '
        'repeat_rule TEXT, '
        'is_custom INTEGER NOT NULL, '
        'PRIMARY KEY (id));',
    'CREATE TABLE check_ins ('
        'id TEXT NOT NULL, '
        'task_id TEXT NOT NULL, '
        'date TEXT NOT NULL, '
        'completed_at TEXT NOT NULL, '
        'session_id TEXT, '
        'is_perfect_day INTEGER NOT NULL, '
        'PRIMARY KEY (id));',
    'CREATE TABLE cooldown_counters ('
        'template_id TEXT NOT NULL, '
        'period INTEGER NOT NULL, '
        'used_count INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (template_id, period));',
    'CREATE TABLE tracking_events ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL DEFAULT \'\', '
        'type INTEGER NOT NULL, '
        'ts TEXT NOT NULL, '
        'payload TEXT NOT NULL, '
        'PRIMARY KEY (id));',
    // 历史任务：迁移后 custom_subject 应为 NULL，名字/科目不得被改动。
    'INSERT INTO tasks (id, name, subject, requires_focus, min_focus_min, '
        'sunlight_reward, repeat_rule, is_custom) '
        'VALUES (\'legacy_task\', \'背诵古诗\', 0, 1, 15, 12, \'daily\', 1);',
  ];
}

/// 读取某表当前所有列名（PRAGMA table_info）。
Future<Set<String>> _columns(db.AppDatabase database, String table) async {
  final List<QueryRow> rows =
      await database.customSelect('PRAGMA table_info($table);').get();
  return rows.map((QueryRow r) => r.read<String>('name')).toSet();
}

/// 某表是否存在（sqlite_master）。
Future<bool> _tableExists(db.AppDatabase database, String table) async {
  final List<QueryRow> rows = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';",
      )
      .get();
  return rows.isNotEmpty;
}

/// 手工构造「老库」并让 AppDatabase 触发迁移。
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
  // 触发迁移：首次访问数据库会执行 onUpgrade。
  await database.customSelect('SELECT 1').get();
  addTearDown(() => database.close());
  return database;
}

void main() {
  group('迁移 v4->v5：tasks.custom_subject 补列', () {
    test('schemaVersion 必须为最新 7（版本号与建表改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(_v4Ddl(), 4);
      // 护栏：版本号若停在旧值，onUpgrade 不跑，下面所有列断言都会红。
      // 注：M4（v6）给 check_ins 补 5 列后，最新版本号已上移到 6
      //（见 test/m4/migration_v5_to_v6_test.dart）；植物成长 V2（v7，玄参大人
      // 2026-09-22）给成长中植物做重置清零后上移到 7
      //（见 test/m3/migration_v6_to_v7_test.dart），本护栏随之跟进。
      expect(database.schemaVersion, 8);
    });

    test('v4 老库迁移后 tasks 含 custom_subject，历史行取 NULL 且数据不丢', () async {
      final db.AppDatabase database = await _openMigrated(_v4Ddl(), 4);

      final Set<String> cols = await _columns(database, 'tasks');
      expect(cols, contains('custom_subject'));
      // 不误伤既有列
      expect(cols, contains('subject'));
      expect(cols, contains('is_custom'));

      final List<db.Task> all = await database.taskDao.allTasks();
      expect(all, hasLength(1));
      expect(all.single.id, 'legacy_task');
      expect(all.single.name, '背诵古诗');
      expect(all.single.customSubject, isNull);
    });

    test('迁移后可写入 / 读回自定义科目（复现真机报错的验收点）', () async {
      final db.AppDatabase database = await _openMigrated(_v4Ddl(), 4);

      // 旧代码在这步必炸：SqliteException(1) table tasks has no column
      // named custom_subject（真机报错原样复现）。
      await database.taskDao.upsertTask(
        db.TasksCompanion(
          id: const Value('t_custom'),
          name: const Value('观察绿豆发芽'),
          subject: const Value(4), // TaskSubject.custom
          customSubject: const Value('科学'),
          requiresFocus: const Value(true),
          minFocusMin: const Value(15),
          sunlightReward: const Value(20),
          isCustom: const Value(true),
        ),
      );

      final List<db.Task> all = await database.taskDao.allTasks();
      expect(all, hasLength(2));
      final db.Task custom = all.firstWhere((db.Task t) => t.id == 't_custom');
      expect(custom.customSubject, '科学');
      expect(custom.subject, 4);
    });
  });

  group('迁移 v3->v5：跨两个版本跳跃升级', () {
    test('v3 老库直跳 v5：植物表、花园容量列、自定义科目列全部补齐', () async {
      // 场景：玄参大人跳过了 M3 那版安装，库还停在 v3（无 plants 表、
      // 无 garden_pot_capacity、无 custom_subject），直接升到 v5。
      final db.AppDatabase database = await _openMigrated(_v3Ddl(), 3);

      // ① 表：plants 由 m.createAll() 建出来。
      expect(await _tableExists(database, 'plants'), isTrue);
      // ② 列：settings.garden_pot_capacity（v4 新增）+ tasks.custom_subject（v5 新增）。
      expect(await _columns(database, 'settings'),
          contains('garden_pot_capacity'));
      expect(await _columns(database, 'tasks'), contains('custom_subject'));

      // ③ 端到端：两处新列都能真正写入（旧代码在任一列缺失时都会抛）。
      await database.taskDao.upsertTask(
        db.TasksCompanion(
          id: const Value('t_custom'),
          name: const Value('书法练习'),
          subject: const Value(4),
          customSubject: const Value('书法'),
          requiresFocus: const Value(false),
          minFocusMin: const Value(15),
          sunlightReward: const Value(10),
          isCustom: const Value(true),
        ),
      );
      final db.Task saved = (await database.taskDao.allTasks())
          .firstWhere((db.Task t) => t.id == 't_custom');
      expect(saved.customSubject, '书法');

      await database.settingsDao.upsert(
        db.SettingsCompanion(
          id: const Value(1),
          ageTier: const Value(0),
          dailyFocusCap: const Value(90),
          dailyAppCapMinutes: const Value(30),
          restAfterSessions: const Value(2),
          restMinutes: const Value(10),
          taskSunlight: const Value(12),
          monthlyPoolBudget: const Value(160),
          gardenPotCapacity: const Value(6),
        ),
      );
      final db.Setting? row = await database.settingsDao.getRow();
      expect(row?.gardenPotCapacity, 6);
    });
  });
}

/// v4 线上 schema：有 plants 表与 garden_pot_capacity，**无** custom_subject。
List<String> _v4Ddl() => _schemaDdl(
      withPlantsTable: true,
      withGardenPotCapacity: true,
      withCustomSubject: false,
    );

/// v3 线上 schema：无 plants 表、无 garden_pot_capacity、无 custom_subject。
List<String> _v3Ddl() => _schemaDdl(
      withPlantsTable: false,
      withGardenPotCapacity: false,
      withCustomSubject: false,
    );
