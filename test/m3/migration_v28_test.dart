/// 迁移回归测试 v27 → v28（**C90 期 2 第二批：四表复合主键重建**，玄参 2026-10-17）。
///
/// 背景（C90 期 2 第二批拍板口径）：premium_fragments（单例行 id=1 → 复合主键
/// (id, child_id)）、unlocked_species（PK species_id → (species_id, child_id)）、
/// monthly_pools（PK month_key → (month_key, child_id)）、cooldown_counters
///（PK(template_id, period) → (template_id, period, child_id)）各新增
/// `child_id TEXT NOT NULL DEFAULT 'single-child'` 并**并入主键**。
/// 主键变更 → SQLite 无法 ALTER，必须**表重建**：CREATE 新表 → INSERT SELECT
/// 拷贝（child_id 统一填 kChildIdDefault）→ DROP 旧 → RENAME，每表一个事务。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion == 28`；
///  ② v27 旧库（四表 v27 形态 DDL + 历史行）→ 迁移后四表**新列全部 = 'single-child'**；
///  ③ 历史行可读、业务字段值逐位不变；
///  ④ 同一旧主键 + 新 childId 可再插一行（复合主键生效）；同旧主键 + 同孩子再插被拒；
///  ⑤ 幂等：二次访问不报错；
///  ⑥ 新装库（v28 直建）四列存在且默认值正确，DAO 按孩子读写可用。
library migration_v28_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// v27 时期 premium_fragments 表 DDL（单例行，PK id）。
const String _fragmentsV27Ddl = 'CREATE TABLE "premium_fragments" ('
    '"id" INTEGER NOT NULL, "balance" INTEGER NOT NULL DEFAULT 0, '
    'PRIMARY KEY ("id"));';

/// v27 时期 unlocked_species 表 DDL（PK species_id）。
const String _unlockedV27Ddl = 'CREATE TABLE "unlocked_species" ('
    '"species_id" TEXT NOT NULL, PRIMARY KEY ("species_id"));';

/// v27 时期 monthly_pools 表 DDL（PK month_key）。
const String _poolsV27Ddl = 'CREATE TABLE "monthly_pools" ('
    '"month_key" TEXT NOT NULL, "budget" INTEGER NOT NULL, '
    '"used" INTEGER NOT NULL DEFAULT 0, '
    '"auto_released" INTEGER NOT NULL DEFAULT 0, '
    '"reset_at" INTEGER NOT NULL, PRIMARY KEY ("month_key"));';

/// v27 时期 cooldown_counters 表 DDL（PK(template_id, period)）。
const String _cooldownV27Ddl = 'CREATE TABLE "cooldown_counters" ('
    '"template_id" TEXT NOT NULL, "period" INTEGER NOT NULL, '
    '"used_count" INTEGER NOT NULL DEFAULT 0, '
    'PRIMARY KEY ("template_id", "period"));';

/// 打开一个「v27 旧库」：四张目标表（v27 列集，无 child_id）+ 历史行 +
/// `user_version = 27`，打开即触发 v28 表重建迁移（其余表由 onUpgrade 首步
/// `m.createAll()` 幂等补齐）。
Future<db.AppDatabase> _openV27() async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute(_fragmentsV27Ddl);
        rawDb.execute(_unlockedV27Ddl);
        rawDb.execute(_poolsV27Ddl);
        rawDb.execute(_cooldownV27Ddl);
        // 每表各一条历史行。⚠️ 本仓未开 storeDateTimesAsText，
        // DateTime 落库为 unix 秒 INTEGER。
        rawDb.execute(
            'INSERT INTO premium_fragments (id, balance) VALUES (1, 7);');
        rawDb.execute(
            "INSERT INTO unlocked_species (species_id) VALUES ('sunflower');");
        rawDb.execute(
          "INSERT INTO monthly_pools (month_key, budget, used, auto_released, "
          "reset_at) VALUES ('2026-10-05', 400, 120, 30, 1729000000);",
        );
        rawDb.execute(
          "INSERT INTO cooldown_counters (template_id, period, used_count) "
          "VALUES ('tpl_vacation', 0, 2);",
        );
        rawDb.execute('PRAGMA user_version = 27;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get(); // 首次访问触发迁移
  return database;
}

/// 某表 child_id 列取值集合（历史行应恰为 {'single-child'}）。
Future<Set<String>> _childIds(db.AppDatabase d, String table) async {
  final List<QueryRow> rows =
      await d.customSelect('SELECT child_id AS c FROM $table;').get();
  return rows.map((QueryRow r) => r.read<String>('c')).toSet();
}

Future<bool> _hasColumn(db.AppDatabase d, String table, String column) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA table_info($table);').get();
  return rows.any((QueryRow r) => r.read<String>('name') == column);
}

void main() {
  group('迁移 v27->v28：四表复合主键重建（C90 期 2 第二批）', () {
    test('① schemaVersion 必须为最新 28（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV27();
      addTearDown(database.close);
      expect(database.schemaVersion, 31);
    });

    test('② 四表均补出 child_id 列，历史行全部 = kChildIdDefault', () async {
      final db.AppDatabase database = await _openV27();
      addTearDown(database.close);

      const List<String> tables = <String>[
        'premium_fragments',
        'unlocked_species',
        'monthly_pools',
        'cooldown_counters',
      ];
      for (final String t in tables) {
        expect(await _hasColumn(database, t, 'child_id'), isTrue,
            reason: 'v28 必须给 $t 补 child_id 列（表重建）');
        expect(await _childIds(database, t), <String>{kChildIdDefault},
            reason: '$t 历史行必须默认归属默认孩子（老用户升级数据无缝）');
      }
    });

    test('③ 历史行可读、业务字段值逐位不变', () async {
      final db.AppDatabase database = await _openV27();
      addTearDown(database.close);

      final Map<String, Object?> f = (await database
              .customSelect("SELECT * FROM premium_fragments WHERE id = 1;")
              .getSingle())
          .data;
      expect(f['balance'], 7);
      expect(f['child_id'], 'single-child');

      final Map<String, Object?> u = (await database.customSelect(
              "SELECT * FROM unlocked_species WHERE species_id = 'sunflower';")
          .getSingle())
      .data;
      expect(u['child_id'], 'single-child');

      final Map<String, Object?> p = (await database
              .customSelect(
                  "SELECT * FROM monthly_pools WHERE month_key = '2026-10-05';")
              .getSingle())
          .data;
      expect(p['budget'], 400);
      expect(p['used'], 120);
      expect(p['auto_released'], 30);
      expect(p['reset_at'], 1729000000, reason: 'DateTime=unix 秒 INTEGER 不改写');
      expect(p['child_id'], 'single-child');

      final Map<String, Object?> c = (await database
              .customSelect(
                  "SELECT * FROM cooldown_counters WHERE "
                  "template_id = 'tpl_vacation' AND period = 0;")
              .getSingle())
          .data;
      expect(c['used_count'], 2);
      expect(c['child_id'], 'single-child');
    });

    test('④ 复合主键生效：同旧主键 + 新 childId 可再插一行；同旧主键 + 同孩子被拒',
        () async {
      final db.AppDatabase database = await _openV27();
      addTearDown(database.close);

      const String anotherChild = 'child_kid_b';

      // 同旧主键 + 不同孩子 → 各表均可再插一行（这正是按孩子隔离的物理基础）。
      await database.customStatement(
        'INSERT INTO premium_fragments (id, balance, child_id) '
        "VALUES (1, 99, '$anotherChild');",
      );
      await database.customStatement(
        "INSERT INTO unlocked_species (species_id, child_id) "
        "VALUES ('sunflower', '$anotherChild');",
      );
      await database.customStatement(
        "INSERT INTO monthly_pools (month_key, budget, used, auto_released, "
        "reset_at, child_id) VALUES ('2026-10-05', 400, 0, 0, 1729000000, "
        "'$anotherChild');",
      );
      await database.customStatement(
        "INSERT INTO cooldown_counters (template_id, period, used_count, "
        "child_id) VALUES ('tpl_vacation', 1, 0, '$anotherChild');",
      );
      expect(
          (await _childIds(database, 'unlocked_species'))
              .contains(anotherChild),
          isTrue);

      // 同旧主键 + 同孩子（默认孩子）再插 → 复合主键冲突必须被拒。
      expect(
        () => database.customStatement(
          'INSERT INTO premium_fragments (id, balance, child_id) '
          "VALUES (1, 1, '$kChildIdDefault');",
        ),
        throwsA(anything),
      );
      expect(
        () => database.customStatement(
          "INSERT INTO unlocked_species (species_id, child_id) "
          "VALUES ('sunflower', '$kChildIdDefault');",
        ),
        throwsA(anything),
      );
      expect(
        () => database.customStatement(
          "INSERT INTO monthly_pools (month_key, budget, used, auto_released, "
          "reset_at, child_id) VALUES ('2026-10-05', 1, 0, 0, 1729000000, "
          "'$kChildIdDefault');",
        ),
        throwsA(anything),
      );
      expect(
        () => database.customStatement(
          "INSERT INTO cooldown_counters (template_id, period, used_count, "
          "child_id) VALUES ('tpl_vacation', 0, 0, '$kChildIdDefault');",
        ),
        throwsA(anything),
      );
    });

    test('④b 经 drift DAO 读回历史行成功（迁移后表结构可被正常访问）', () async {
      final db.AppDatabase database = await _openV27();
      addTearDown(database.close);

      expect(
        await database.bloomRewardDao
            .fragmentBalance(childId: kChildIdDefault),
        7,
      );
      expect(
        await database.bloomRewardDao.unlockedSpeciesIds(
          childId: kChildIdDefault,
        ),
        <String>['sunflower'],
      );
      final db.MonthlyPool? pool = await database.monthlyPoolDao
          .of('2026-10-05', childId: kChildIdDefault);
      expect(pool, isNotNull);
      expect(pool!.budget, 400);
      expect(pool.used, 120);
      expect(
        await database.cooldownCounterDao
            .count('tpl_vacation', CooldownPeriod.weekly,
                childId: kChildIdDefault),
        2,
      );
    });

    test('⑤ 幂等：二次访问不报错、行数不变', () async {
      final db.AppDatabase database = await _openV27();
      addTearDown(database.close);

      final int before = (await database
              .customSelect('SELECT COUNT(*) AS n FROM premium_fragments;')
              .getSingle())
          .read<int>('n');
      await database.customSelect('SELECT 1').get();
      await database.customSelect('SELECT COUNT(*) AS n FROM cooldown_counters;')
          .getSingle();
      expect(
        (await database
                .customSelect('SELECT COUNT(*) AS n FROM premium_fragments;')
                .getSingle())
            .read<int>('n'),
        before,
        reason: '二次访问不得重复拷贝 / 重复建列',
      );
      expect(await _childIds(database, 'premium_fragments'),
          <String>{kChildIdDefault});
    });

    test('⑥ 新装库（v28 直建）四列存在，不指定 childId 的写入落默认值且 DAO 按孩子可用',
        () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();
      expect(database.schemaVersion, 31);

      // 不指定 childId → 落列默认 kChildIdDefault。
      await database.bloomRewardDao.setFragmentBalance(5);
      await database.bloomRewardDao.unlockSpecies('sunflower');
      expect(await _childIds(database, 'premium_fragments'),
          <String>{kChildIdDefault});
      expect(
          await _childIds(database, 'unlocked_species'), <String>{kChildIdDefault});

      // 指定 childId → 按孩子读写互不串。
      await database.bloomRewardDao.setFragmentBalance(99,
          childId: 'child_kid_b');
      expect(
          await database.bloomRewardDao
              .fragmentBalance(childId: 'child_kid_b'),
          99);
      expect(
          await database.bloomRewardDao
              .fragmentBalance(childId: kChildIdDefault),
          5);
    });
  });
}
