/// 迁移回归测试 v30 → v31（**F155-B：新增 `empty_pot_disturbances` 表**，
/// 玄参 2026-10-27 拍板）。
///
/// 背景（F155-B 口径）：空花盆每天也独立 roll 杂草 / 害虫（频率为植物的一半
/// 0.20 / 0.15），清理奖励与植物完全一致（1 ☀ / 2 ☀，含称号加成）。空盆没有
/// `Plants` 行可挂干扰物，故按**盆**落一张独立状态表：
///  · 列：`child_id` / `pot_index` / `weed_at` / `pest_at` / `roll_day`；
///  · 主键：**复合 (child_id, pot_index)** —— 每个孩子各盆互不影响；
///  · `weed_at` / `pest_at` / `roll_day` 语义**逐字对齐** `Plants` 的同名三列
///    （存「当天零点」，零点判等即天然跨天失效，不需要额外清理任务）。
///
/// 迁移方式：**纯新增表**，不需要表重建、不需要手工建表分支 ——
/// `onUpgrade` 首步 `m.createAll()` 的 `CREATE TABLE IF NOT EXISTS` 即可建成
/// （见 `app_database.dart` 的 ㉛ 段）。schemaVersion 30 → 31。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion == 31`（版本号与建表改动不许脱节）；
///  ② v30 老库（**没有**该表 + 已有植物 / 设置 / 账本数据）升级后：
///     表出现、四列 + 复合主键齐全、**既有数据逐位不变**；
///  ③ 新装库（v31 直建）直接就有该表（列集一致）；
///  ④ 幂等：已迁移库二次打开不报错、表仍在、行数不变；
///  ⑤ 复合主键真的生效：同 `potIndex` 不同孩子可共存；同 (孩子, 盆) upsert 只留一行。
library migration_v31_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// 空盆表列集（迁移后的期望 schema；顺序即建表顺序）。
const List<String> _expectedColumns = <String>[
  'child_id',
  'pot_index',
  'weed_at',
  'pest_at',
  'roll_day',
];

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

/// 复合主键的列名（按主键序号排序的空列表 = 无主键）。
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

Future<int> _count(db.AppDatabase d, String table) async =>
    (await d.customSelect('SELECT COUNT(*) AS n FROM $table;').getSingle())
        .read<int>('n');

/// 在 v31 全新库里写入一点「既有业务数据」（植物 / 设置 / 阳光账本），
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
}

/// 打开一个「v30 老库」：先在临时文件里建全量 v31 库、灌入既有业务数据，
/// 再把**本批次新增的空盆表** DROP 掉并 `PRAGMA user_version = 30`
/// —— 得到一个「列集/数据与 v30 真库一致、只缺本批次新表」的库。
///
/// 之所以这样造库（而不是手写 v30 全套 DDL）：本仓表数已 17 张，
/// 「除本批次新表外一切照旧」用 DROP 表达最忠实，也不会因手抄 DDL 漂移而假绿。
Future<File> _makeV30File(Directory dir) async {
  final File file = File('${dir.path}/legacy_v30.sqlite');
  final db.AppDatabase fresh = db.AppDatabase(NativeDatabase(file));
  await fresh.customSelect('SELECT 1').get();
  expect(await _hasTable(fresh, 'empty_pot_disturbances'), isTrue,
      reason: '前置：全新 v31 库必须自带空盆表，否则本用例失去意义');
  await _seedBusinessData(fresh);
  await fresh.customStatement('DROP TABLE empty_pot_disturbances;');
  await fresh.customStatement('PRAGMA user_version = 30;');
  await fresh.close();
  return file;
}

void main() {
  group('迁移 v30->v31：新增 empty_pot_disturbances 表（F155-B）', () {
    test('① schemaVersion 必须为最新 31（版本号与建表改动不许脱节）', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v31');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db.AppDatabase database =
          db.AppDatabase(NativeDatabase(await _makeV30File(dir)));
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      expect(database.schemaVersion, 31);
    });

    test('② v30 老库升级后空盆表存在：四列 + 复合主键 (child_id, pot_index)', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v31');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = await _makeV30File(dir);
      final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      expect(await _hasTable(database, 'empty_pot_disturbances'), isTrue,
          reason: 'v31 必须建出 empty_pot_disturbances（onUpgrade 首步 createAll）');
      expect(await _columnsOf(database, 'empty_pot_disturbances'),
          _expectedColumns);
      expect(await _primaryKeyOf(database, 'empty_pot_disturbances'),
          <String>['child_id', 'pot_index'],
          reason: '复合主键必须是 (child_id, pot_index)：每个孩子各盆互不影响');
      // 全新表 → 迁移后 0 行（不得凭空造出干扰物）。
      expect(await _count(database, 'empty_pot_disturbances'), 0);
    });

    test('③ 迁移不动既有业务数据：植物 / 设置 / 阳光账本逐位不变', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v31');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = await _makeV30File(dir);
      final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      final Map<String, Object?> plant = (await database
              .customSelect("SELECT * FROM plants WHERE id = 'p_keep';")
              .getSingle())
          .data;
      expect(plant['species_id'], 'species_sunflower');
      expect(plant['pot_index'], 0);
      expect(plant['shovel_refund'], 0, reason: 'v16 默认值列必须保持默认');
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
    });

    test('④ 新装库（v31 直建）：空盆表直接就有，列集与迁移后一致', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      expect(database.schemaVersion, 31);
      expect(await _hasTable(database, 'empty_pot_disturbances'), isTrue);
      expect(await _columnsOf(database, 'empty_pot_disturbances'),
          _expectedColumns);
      expect(await _primaryKeyOf(database, 'empty_pot_disturbances'),
          <String>['child_id', 'pot_index']);
    });

    test('⑤ 幂等：已迁移库二次打开不报错、表仍在、行数不变', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v31');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = await _makeV30File(dir);

      final db.AppDatabase first = db.AppDatabase(NativeDatabase(file));
      await first.customSelect('SELECT 1').get();
      expect(await _hasTable(first, 'empty_pot_disturbances'), isTrue);
      // 迁移后写一条，验证「二次打开不丢数据」。
      await first.emptyPotDisturbanceDao.upsert(
        db.EmptyPotDisturbancesCompanion.insert(potIndex: 1),
        childId: kChildIdDefault,
      );
      final int before = await _count(first, 'empty_pot_disturbances');
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 31);
      expect(await _count(second, 'empty_pot_disturbances'), before,
          reason: '已迁移库不再进 onUpgrade，createAll 幂等 → 行数不变');
      expect(await _hasTable(second, 'empty_pot_disturbances'), isTrue);
    });

    test('⑥ 复合主键语义：同盆不同孩子共存、同 (孩子, 盆) upsert 只留一行', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      final DateTime today = DateTime(2026, 10, 27);
      // 同一盆 3：孩子 A 有草、孩子 B 有虫 —— 互不覆盖。
      await database.emptyPotDisturbanceDao.upsert(
        db.EmptyPotDisturbancesCompanion.insert(
          potIndex: 3,
          weedAt: Value<DateTime?>(today),
          rollDay: Value<DateTime?>(today),
        ),
        childId: 'kid_a',
      );
      await database.emptyPotDisturbanceDao.upsert(
        db.EmptyPotDisturbancesCompanion.insert(
          potIndex: 3,
          pestAt: Value<DateTime?>(today),
          rollDay: Value<DateTime?>(today),
        ),
        childId: 'kid_b',
      );
      expect(await _count(database, 'empty_pot_disturbances'), 2);

      final db.EmptyPotDisturbanceRow? a =
          await database.emptyPotDisturbanceDao.byPot(3, childId: 'kid_a');
      final db.EmptyPotDisturbanceRow? b =
          await database.emptyPotDisturbanceDao.byPot(3, childId: 'kid_b');
      expect(a?.weedAt, isNotNull);
      expect(a?.pestAt, isNull);
      expect(b?.weedAt, isNull);
      expect(b?.pestAt, isNotNull);

      // 同 (孩子, 盆) 再写 → 冲突合并，仍 2 行（不是 3 行）。
      await database.emptyPotDisturbanceDao.upsert(
        db.EmptyPotDisturbancesCompanion.insert(
          potIndex: 3,
          weedAt: const Value<DateTime?>(null),
          pestAt: Value<DateTime?>(today),
        ),
        childId: 'kid_a',
      );
      expect(await _count(database, 'empty_pot_disturbances'), 2,
          reason: '复合主键 (child_id, pot_index) 冲突合并，不得插出第三行');
      final db.EmptyPotDisturbanceRow? a2 =
          await database.emptyPotDisturbanceDao.byPot(3, childId: 'kid_a');
      expect(a2?.weedAt, isNull, reason: 'upsert 后孩子 A 的草被清、虫写上');
      expect(a2?.pestAt, isNotNull);
    });
  });
}
