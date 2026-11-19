/// 迁移回归测试 v31 → v32（**许愿树数据底座**）。
///
/// 本批改动（schemaVersion 31 → 32）：
///  · 🆕 新表 `wishes`（**22 列** + 单列 uuid 主键 `id` + **3 条复合索引**）；
///    🔴 v0.3.0：迁移链恢复为唯一一跳 **v31 → v32**（v33 已随推送机制整体回退）；
///  · 既有表 `tasks` **加一列** `wish_id`（`null` = 普通成长任务）+
///    **加一条索引** `idx_tasks_wish`；
///  · Drift 字段名 `text` → **`wishText`**（DB 列名仍是 `text`）——
///    根因见架构 A26.11.2：drift 2.34 的 `Table.text()` 是**继承来的实例方法**，
///    子类定义同名字段会被 Dart **语言级**拒绝 ⇒ 只能用 `.named('text')` 保住
///    DB 列名。
///
/// 🔴 本批踩到并修掉的**两个真缺陷**（本测试即它们的回归钉子）：
///  ① **建索引早于补列** ⇒ `no such column: wish_id`；
///  ② **索引已存在时 `createAll()` 仍无条件重建** ⇒
///     `index idx_tasks_wish already exists` ——
///     根因：drift 的 `Migrator.createAll()` 把索引当**独立的 schema entity**，
///     生成物是 `CREATE INDEX <name> ON ...`，🔴 **不带 `IF NOT EXISTS`**；
///     本项目此前**没有任何「既有表」带 `@TableIndex`**（表级索引只出现在新表上），
///     v32 首次给既有表 `tasks` 加索引，打破了这一前提。
///     修法：`onUpgrade` ⓿ 步「先补列 → 再 `DROP INDEX IF EXISTS` → 再
///     `createAll()` 按当前 schema 重建」。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion == 32`（版本号与建表改动不许脱节）；
///  ② v31 老库（**没有** `wishes` 表 / **没有** `tasks.wish_id` 列 / **没有** 4 条索引）
///     升级后：`wishes` 表出现、**22 列逐列逐序**、主键 `['id']`、3 条复合索引齐全、
///     `tasks.wish_id` 列存在、`idx_tasks_wish` 存在；
///  ③ 🔴 `wishText` ↔ DB 列名 `text` 的映射（drift 侧驼峰 / DB 侧原名）；
///  ④ 迁移不动既有业务数据（植物 / 设置 / 阳光账本 / 任务行逐位不变）；
///  ⑤ 新装库（v32 直建）：`wishes` 表 + 22 列 + 4 条索引齐全；
///  ⑥ 幂等：已迁移库二次打开不报错、行数不变、索引仍在；
///  ⑦ 🔴 **老库里索引已存在**时升级不报错（本轮修的根因，防回归）；
///  ⑧ 索引真的会被 SQLite 选中（`EXPLAIN QUERY PLAN`）。
library migration_v32_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// `wishes` 表列集（迁移后的期望 schema；**顺序即建表顺序**，逐列逐序比对）。
const List<String> _expectedWishColumns = <String>[
  'id',
  'child_id',
  'text',
  'category',
  'status',
  'created_at',
  'committed_at',
  'commit_due_date',
  'fulfilled_at',
  'fulfill_source',
  'abandoned_at',
  'parent_seen_at',
  'reminded_at',
  'parent_reply',
  'replaced_text',
  'tree_slot',
  'target_mode',
  'target_value',
  'progress_value',
  'tag_key',
  'tagged_at',
  'released_at',
];

/// `wishes` 的 3 条复合索引 ⇒ 期望的索引列。
const Map<String, List<String>> _expectedWishIndexes = <String, List<String>>{
  'idx_wishes_child_status': <String>['child_id', 'status'],
  'idx_wishes_child_created': <String>['child_id', 'created_at'],
  'idx_wishes_child_slot': <String>['child_id', 'tree_slot'],
};

/// `tasks` 上本批新增的索引。
const Map<String, List<String>> _expectedTaskIndexes = <String, List<String>>{
  'idx_tasks_wish': <String>['wish_id'],
};

/// 某表是否存在（`sqlite_master` 判据，与 drift 内部建表方式无关）。
Future<bool> _hasTable(db.AppDatabase d, String table) async {
  final List<QueryRow> rows = await d
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
        variables: <Variable<Object>>[Variable<String>(table)],
      )
      .get();
  return rows.isNotEmpty;
}

/// 某表的列名列表（`PRAGMA table_info`）。
Future<List<String>> _columnsOf(db.AppDatabase d, String table) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA table_info($table);').get();
  return rows.map((QueryRow r) => r.read<String>('name')).toList();
}

/// 复合主键的列名（按主键序号排序；空列表 = 无主键）。
Future<List<String>> _primaryKeyOf(db.AppDatabase d, String table) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA table_info($table);').get();
  final List<({int seq, String name})> pk = <({int seq, String name})>[
    for (final QueryRow r in rows)
      if (r.read<int>('pk') > 0)
        (seq: r.read<int>('pk'), name: r.read<String>('name')),
  ]..sort((({int seq, String name}) a, ({int seq, String name}) b) =>
      a.seq.compareTo(b.seq));
  return pk.map((({int seq, String name}) e) => e.name).toList();
}

/// 某张表上的**显式索引**名集合（`PRAGMA index_list`；`origin = 'c'` = 用户创建）。
Future<List<String>> _indexNamesOf(db.AppDatabase d, String table) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA index_list($table);').get();
  return rows
      .where((QueryRow r) => r.read<String>('origin') == 'c')
      .map((QueryRow r) => r.read<String>('name'))
      .toList()
    ..sort();
}

/// 某条索引覆盖的列名（`PRAGMA index_info`）。
Future<List<String>> _indexColumnsOf(db.AppDatabase d, String index) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA index_info($index);').get();
  return rows.map((QueryRow r) => r.read<String>('name')).toList();
}

Future<int> _count(db.AppDatabase d, String table) async =>
    (await d.customSelect('SELECT COUNT(*) AS n FROM $table;').getSingle())
        .read<int>('n');

/// 写入一点「既有业务数据」（植物 / 设置 / 阳光账本 / 任务行），
/// 供「迁移不得动老数据」断言用。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，DateTime 落库为 unix 秒 INTEGER。
Future<void> _seedBusinessData(db.AppDatabase d) async {
  const int t = 1729000000;
  await d.customStatement(
    'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
    'status, planted_at) VALUES (?, ?, ?, ?, ?, ?, ?);',
    <Object>['p_keep', 'species_sunflower', 0, 3, t, 3, t],
  );
  await d.customStatement(
    'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
    'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget) '
    'VALUES (1, 1, 120, 60, 2, 10, 8, 300);',
  );
  await d.customStatement(
    'INSERT INTO sunlight_ledgers (id, ts, type, gross, net, balance_after, '
    'ref_type, ref_id, day_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
    <Object>['led_keep', t, 0, 1.0, 1.0, 1.0, 'plant_weed', 'p_keep', '2024-10-15'],
  );
  await d.customStatement(
    'INSERT INTO tasks (id, name, subject, requires_focus, is_custom, '
    'min_focus_min, category) VALUES (?, ?, ?, ?, ?, ?, ?);',
    <Object>['t_keep', '练字', 0, 0, 0, 15, 0],
  );
}

/// 造一个「**真 v31 老库**」：列集/数据与 v31 真库一致 —— 即
/// **没有 `wishes` 表 / 没有 `tasks.wish_id` 列 / 没有 4 条索引**。
///
/// 做法：先建全量 v32 库并灌既有业务数据，再把 v32 的产物**逐一撤掉**
/// （DROP TABLE wishes 会连带删掉它的 3 条索引；`tasks.wish_id` 因被索引引用，
/// 必须先 DROP INDEX 再 ALTER TABLE DROP COLUMN），最后 `PRAGMA user_version = 31`。
Future<File> _makeV31File(Directory dir) async {
  final File file = File('${dir.path}/legacy_v31.sqlite');
  final db.AppDatabase fresh = db.AppDatabase(NativeDatabase(file));
  await fresh.customSelect('SELECT 1').get();
  expect(await _hasTable(fresh, 'wishes'), isTrue,
      reason: '前置：全新 v32 库必须自带 wishes 表，否则本用例失去意义');
  await _seedBusinessData(fresh);
  // 撤掉 v32 的三样产物 ⇒ 得到「列集与数据与 v31 真库一致」的库。
  await fresh.customStatement('DROP TABLE wishes;');
  await fresh.customStatement('DROP INDEX IF EXISTS idx_tasks_wish;');
  await fresh.customStatement('ALTER TABLE tasks DROP COLUMN wish_id;');
  await fresh.customStatement('PRAGMA user_version = 31;');
  await fresh.close();
  return file;
}

/// 造一个「**索引已存在**的 v31 老库」：用全量 v32 库建出来（索引齐），
/// 只把 `user_version` 改成 31 —— 用来钉死
/// 「`createAll()` 遇到已存在索引会炸」这个本轮修掉的根因。
Future<File> _makeV31FileWithIndexes(Directory dir) async {
  final File file = File('${dir.path}/legacy_v31_idx.sqlite');
  final db.AppDatabase fresh = db.AppDatabase(NativeDatabase(file));
  await fresh.customSelect('SELECT 1').get();
  await _seedBusinessData(fresh);
  await fresh.customStatement('PRAGMA user_version = 31;');
  await fresh.close();
  return file;
}

void main() {
  group('迁移 v31->v32：许愿树数据底座（wishes 表 + tasks.wish_id + 4 条索引）', () {
    test('① schemaVersion 必须为最新 32（版本号与建表改动不许脱节）', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v32');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db.AppDatabase database =
          db.AppDatabase(NativeDatabase(await _makeV31File(dir)));
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      expect(database.schemaVersion, 32);
    });

    test('② v31 老库升级后：wishes 22 列逐列逐序 + 主键 [id] + 4 条索引齐全',
        () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v32');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = await _makeV31File(dir);
      final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      // 表存在 + 22 列逐列逐序。
      expect(await _hasTable(database, 'wishes'), isTrue,
          reason: 'v32 必须建出 wishes（onUpgrade 首步 createAll）');
      expect(await _columnsOf(database, 'wishes'), _expectedWishColumns);
      expect(_expectedWishColumns.length, 22,
          reason: '22 列（A15.3 定稿清单；v0.3.0 已回退 v0.2 的 shared_to_parent）'
              '是权威契约，列数漂移即为契约破坏');

      // 主键 = 单列 uuid id（架构 A30.2 裁决：childId 只做过滤列，不进主键）。
      expect(await _primaryKeyOf(database, 'wishes'), <String>['id']);

      // 3 条 wishes 复合索引 + 既有 tasks 上的 idx_tasks_wish。
      final List<String> wishIndexes =
          await _indexNamesOf(database, 'wishes');
      expect(wishIndexes, containsAll(_expectedWishIndexes.keys.toList()));
      for (final MapEntry<String, List<String>> e in _expectedWishIndexes.entries) {
        expect(await _indexColumnsOf(database, e.key), e.value,
            reason: '${e.key} 的列必须是 ${e.value}');
      }
      final List<String> taskIndexes =
          await _indexNamesOf(database, 'tasks');
      expect(taskIndexes, containsAll(_expectedTaskIndexes.keys.toList()));
      for (final MapEntry<String, List<String>> e
          in _expectedTaskIndexes.entries) {
        expect(await _indexColumnsOf(database, e.key), e.value,
            reason: '${e.key} 的列必须是 ${e.value}');
      }

      // tasks.wish_id 列已补（可空）。
      expect(await _columnsOf(database, 'tasks'), contains('wish_id'));
      expect(await _count(database, 'wishes'), 0,
          reason: '全新表 → 迁移后 0 行（不得凭空造出愿望）');
    });

    test('③ wishText ↔ DB 列名 text：drift 侧驼峰、DB 侧原名（架构 A26.11.2）',
        () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v32');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      // DB 列名必须是 `text`（不是 `wish_text`）—— DB 侧零改动。
      expect(await _columnsOf(database, 'wishes'), contains('text'));
      expect(await _columnsOf(database, 'wishes'),
          isNot(contains('wish_text')));

      // drift 侧字段名是 `wishText`，写入后落到 DB 的 `text` 列。
      await database.into(database.wishes).insert(
            db.WishesCompanion.insert(
              id: 'w1',
              wishText: '去海边',
              status: 0,
              createdAt: DateTime(2026, 11, 17),
            ),
          );
      final Map<String, Object?> row = (await database
              .customSelect("SELECT * FROM wishes WHERE id = 'w1';")
              .getSingle())
          .data;
      expect(row['text'], '去海边');
      expect(row['wish_text'], isNull);
    });

    test('④ 迁移不动既有业务数据：植物 / 设置 / 阳光账本 / 任务行逐位不变',
        () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v32');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = await _makeV31File(dir);
      final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      final Map<String, Object?> plant = (await database
              .customSelect("SELECT * FROM plants WHERE id = 'p_keep';")
              .getSingle())
          .data;
      expect(plant['species_id'], 'species_sunflower');
      expect(plant['pot_index'], 0);
      expect(plant['child_id'], kChildIdDefault,
          reason: 'C90 期 2：历史行归属默认孩子，迁移不得改写');

      final Map<String, Object?> ledger = (await database
              .customSelect("SELECT * FROM sunlight_ledgers WHERE id = 'led_keep';")
              .getSingle())
          .data;
      expect(ledger['net'], 1.0);
      expect(ledger['ref_type'], 'plant_weed');

      final Map<String, Object?> settings =
          (await database.customSelect('SELECT * FROM settings WHERE id = 1;')
                  .getSingle())
              .data;
      expect(settings['daily_focus_cap'], 120);
      expect(settings['monthly_pool_budget'], 300);

      // 既有任务行逐位不变，且 `wish_id` 为 NULL（= 普通成长任务，历史行零感知）。
      final Map<String, Object?> task = (await database
              .customSelect("SELECT * FROM tasks WHERE id = 't_keep';")
              .getSingle())
          .data;
      expect(task['name'], '练字');
      expect(task['min_focus_min'], 15);
      expect(task['wish_id'], isNull,
          reason: '历史任务不得被挂到任何愿望下');
    });

    test('⑤ 新装库（v32 直建）：wishes 表 + 22 列 + 4 条索引齐全', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      expect(database.schemaVersion, 32);
      expect(await _hasTable(database, 'wishes'), isTrue);
      expect(await _columnsOf(database, 'wishes'), _expectedWishColumns);
      expect(await _primaryKeyOf(database, 'wishes'), <String>['id']);
      expect(await _indexNamesOf(database, 'wishes'),
          containsAll(_expectedWishIndexes.keys.toList()));
      expect(await _indexNamesOf(database, 'tasks'),
          containsAll(_expectedTaskIndexes.keys.toList()));
    });

    test('⑥ 幂等：已迁移库二次打开不报错、行数不变、索引仍在', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v32');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = await _makeV31File(dir);

      final db.AppDatabase first = db.AppDatabase(NativeDatabase(file));
      await first.customSelect('SELECT 1').get();
      expect(await _hasTable(first, 'wishes'), isTrue);
      await first.into(first.wishes).insert(
            db.WishesCompanion.insert(
              id: 'w_keep',
              wishText: '养一只恐龙',
              status: 0,
              createdAt: DateTime(2026, 11, 17),
            ),
          );
      final int before = await _count(first, 'wishes');
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 32);
      expect(await _count(second, 'wishes'), before,
          reason: '已迁移库不再进 onUpgrade，createAll 幂等 → 行数不变');
      expect(await _hasTable(second, 'wishes'), isTrue);
      expect(await _indexNamesOf(second, 'wishes'),
          containsAll(_expectedWishIndexes.keys.toList()));
      expect(await _indexNamesOf(second, 'tasks'),
          containsAll(_expectedTaskIndexes.keys.toList()));
    });

    test('⑦ 老库里索引已存在时升级不报错（本轮修的根因，防回归）', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v32');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = await _makeV31FileWithIndexes(dir);
      final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
      addTearDown(database.close);

      // 🔴 本条在修复前会抛
      //   `index idx_tasks_wish already exists, SQL logic error (code 1)`。
      await database.customSelect('SELECT 1').get();

      expect(database.schemaVersion, 32);
      expect(await _hasTable(database, 'wishes'), isTrue);
      expect(await _indexNamesOf(database, 'wishes'),
          containsAll(_expectedWishIndexes.keys.toList()));
      expect(await _indexNamesOf(database, 'tasks'), contains('idx_tasks_wish'));
    });

    test('⑧ 索引真的会被 SQLite 选中（EXPLAIN QUERY PLAN 命中复合索引）',
        () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      final List<QueryRow> plan = await database
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT id FROM wishes '
            'WHERE child_id = ? AND created_at = ?;',
            variables: <Variable<Object>>[
              const Variable<String>(kChildIdDefault),
              const Variable<int>(1729000000),
            ],
          )
          .get();
      final String text = plan.map((QueryRow r) => r.data.values.join(' ')).join(' | ');
      expect(text, contains('idx_wishes_child_created'),
          reason: '收藏箱按 (child_id, created_at) 倒序取数 ⇒ 必须吃这条索引');
    });
  });
}
