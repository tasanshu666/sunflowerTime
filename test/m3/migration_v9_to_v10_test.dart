/// 迁移回归测试 v9 → v10（成株后循环玩法 Batch 1）：
/// `plants` 新增 `bloom_count` 列（累计盛开次数，INT NOT NULL DEFAULT 0）
/// ＋ 3 张新表：`premium_fragments`（精品碎片余额）、`pending_bloom_rewards`（第二段待收集奖励）、
/// `unlocked_species`（已解锁物种）。
///
/// 本测试钉死五件事（**必须把历史行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 15`；
///  ② v9 → v10 后 `plants` 含 `bloom_count` 列，且 3 张新表存在（PRAGMA / sqlite_master）；
///  ③ 历史植物（growing / bloomed / wilting / dead）的**其它字段原样保留**，
///     `bloom_count` 取默认值 0（NOT NULL DEFAULT 0，老库 ALTER 后历史行即 0）；
///  ④ 新列 / 新表可正常写入 / 读回（碎片余额 + 第二段待收集奖励往返不炸）；
///  ⑤ 幂等（重复打开列/表仍在、数据不丢）＋ 跨版本跳跃（v7 → v10）数据正确。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**，
///    故「老库」DDL 的日期列一律用 `INTEGER`（秒），否则读回会因类型不匹配而失败。
library migration_v9_to_v10_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

final DateTime _legacyStageStarted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyPlanted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyBloomedStarted = DateTime(2026, 8, 20, 10, 0);
final DateTime _legacyWiltingStarted = DateTime(2026, 8, 25, 12, 0);
final DateTime _legacyDeadStarted = DateTime(2026, 8, 10, 9, 0);

/// v9 线上 schema：plants 含 bloomed_at 但**无** bloom_count；
/// tasks 含 category、reward_templates 含 content_category（v9 已有）；无本批 3 张新表。
List<String> _v9Ddl({required bool withLegacyPlants}) {
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
        'mood INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));', // ← v10 才加 bloom_count
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
    if (withLegacyPlants) ...<String>[
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, mood) '
          'VALUES (\'p_growing\', \'species_sunflower\', 0, '
          '${PlantStage.adult.index}, ${_secs(_legacyStageStarted)}, 0.6, 1.0, '
          '1, 1, ${PlantStatus.growing.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, NULL, 0);',
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, mood) '
          'VALUES (\'p_bloomed\', \'species_tomato\', 1, '
          '${PlantStage.adult.index}, ${_secs(_legacyBloomedStarted)}, 1.0, 1.0, '
          '1, 1, ${PlantStatus.bloomed.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, ${_secs(_legacyBloomedStarted)}, 0);',
      // 复开花后花谢中（growing 但 bloomed_at 非空）：回填应认作「开过 ≥1 次花」。
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, mood) '
          'VALUES (\'p_rebloom_growing\', \'species_sunflower\', 4, '
          '${PlantStage.adult.index}, ${_secs(_legacyStageStarted)}, 0.7, 1.0, '
          '1, 1, ${PlantStatus.growing.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, ${_secs(_legacyBloomedStarted)}, 0);',
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, mood) '
          'VALUES (\'p_wilting\', \'species_star_flower\', 2, '
          '${PlantStage.sprout.index}, ${_secs(_legacyWiltingStarted)}, 0.35, '
          '1.0, 0, 0, ${PlantStatus.wilting.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, ${_secs(_legacyWiltingStarted)}, NULL, NULL, 2);',
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, mood) '
          'VALUES (\'p_dead\', \'species_sunflower\', 3, '
          '${PlantStage.seed.index}, ${_secs(_legacyDeadStarted)}, 0.1, 1.0, '
          '0, 0, ${PlantStatus.dead.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, ${_secs(_legacyDeadStarted)}, NULL, 0);',
    ],
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

void main() {
  group('迁移 v9->v10：plants.bloom_count + 3 张新表', () {
    test('schemaVersion 必须为最新 14（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(
        _v9Ddl(withLegacyPlants: true),
        9,
      );
      expect(database.schemaVersion, 16);
    });

    test('迁移后 plants 出现 bloom_count 列，且 3 张新表存在', () async {
      final db.AppDatabase database = await _openMigrated(
        _v9Ddl(withLegacyPlants: true),
        9,
      );
      expect(await _columns(database, 'plants'), contains('bloom_count'));
      expect(await _tableExists(database, 'premium_fragments'), isTrue);
      expect(await _tableExists(database, 'pending_bloom_rewards'), isTrue);
      expect(await _tableExists(database, 'unlocked_species'), isTrue);
    });

    test('历史植物其它字段原样保留；回填：bloomed_at 非空行 bloom_count=1、空行=0', () async {
      final db.AppDatabase database = await _openMigrated(
        _v9Ddl(withLegacyPlants: true),
        9,
      );

      final db.Plant growing = (await database.plantDao.byId('p_growing'))!;
      expect(growing.status, PlantStatus.growing.index);
      expect(growing.stage, PlantStage.adult.index);
      expect(growing.growthProgress, 0.6);
      expect(growing.speciesId, 'species_sunflower');
      expect(growing.bloomedAt, isNull);
      expect(growing.bloomCount, 0, reason: 'bloomed_at 为空 → 未开过花，回填不改');

      final db.Plant bloomed = (await database.plantDao.byId('p_bloomed'))!;
      expect(bloomed.status, PlantStatus.bloomed.index);
      expect(bloomed.growthProgress, 1.0);
      expect(bloomed.bloomedAt, _legacyBloomedStarted);
      expect(bloomed.bloomCount, 1,
          reason: 'bloomed_at 非空 → 回填 UPDATE 置 bloom_count=1（至少开过 1 次）');

      final db.Plant rebloom = (await database.plantDao.byId('p_rebloom_growing'))!;
      expect(rebloom.status, PlantStatus.growing.index);
      expect(rebloom.bloomedAt, _legacyBloomedStarted);
      expect(rebloom.bloomCount, 1,
          reason: '花谢后 growing 但 bloomed_at 非空 → 同样回填为 1（复开花速率）');

      final db.Plant wilting = (await database.plantDao.byId('p_wilting'))!;
      expect(wilting.status, PlantStatus.wilting.index);
      expect(wilting.growthProgress, 0.35);
      expect(wilting.bloomedAt, isNull);
      expect(wilting.bloomCount, 0);

      final db.Plant dead = (await database.plantDao.byId('p_dead'))!;
      expect(dead.status, PlantStatus.dead.index);
      expect(dead.growthProgress, 0.1);
      expect(dead.deadAt, _legacyDeadStarted);
      expect(dead.bloomedAt, isNull);
      expect(dead.bloomCount, 0);
    });

    test('迁移后 DAO 可写入 / 读回 bloomCount', () async {
      final db.AppDatabase database = await _openMigrated(
        _v9Ddl(withLegacyPlants: false),
        9,
      );
      final DateTime t = DateTime(2026, 9, 25, 12, 0);
      await database.plantDao.upsert(
        db.PlantsCompanion(
          id: const Value('p_new'),
          speciesId: const Value('species_star_flower'),
          potIndex: const Value(0),
          stage: Value(PlantStage.adult.index),
          stageStartedAt: Value(t),
          growthProgress: const Value(0.7),
          status: Value(PlantStatus.growing.index),
          plantedAt: Value(t),
          bloomCount: const Value(3),
        ),
      );
      final db.Plant p = (await database.plantDao.byId('p_new'))!;
      expect(p.bloomCount, 3);
    });

    test('新表可写入 / 读回（碎片余额 + 第二段待收集奖励往返不炸）', () async {
      final db.AppDatabase database = await _openMigrated(
        _v9Ddl(withLegacyPlants: false),
        9,
      );
      // 碎片余额往返。
      await database.bloomRewardDao.setFragmentBalance(5);
      expect(await database.bloomRewardDao.fragmentBalance(), 5);
      await database.bloomRewardDao.setFragmentBalance(9);
      expect(await database.bloomRewardDao.fragmentBalance(), 9);

      // 已解锁物种往返。
      expect(await database.bloomRewardDao.unlockedSpeciesIds(), isEmpty);
      await database.bloomRewardDao.unlockSpecies('species_star_flower');
      await database.bloomRewardDao.unlockSpecies('species_star_flower'); // 幂等
      expect(await database.bloomRewardDao.unlockedSpeciesIds(),
          <String>['species_star_flower']);

      // 第二段待发奖励：未到期不发、到期可取、标记后不再发。
      final DateTime bloom = DateTime(2026, 9, 25, 8, 0);
      await database.bloomRewardDao.insertPending(
        db.PendingBloomRewardsCompanion(
          id: const Value('pr_1'),
          plantId: const Value('p_1'),
          dueAt: Value(bloom.add(const Duration(hours: kBloomRewardDelayHours))),
          rewardKind: const Value(kBloomRewardKindNormal),
        ),
      );
      expect(await database.bloomRewardDao.pendingDue(bloom), isEmpty);
      final DateTime due =
          bloom.add(const Duration(hours: kBloomRewardDelayHours));
      final List<db.PendingBloomRewardRow> ready =
          await database.bloomRewardDao.pendingDue(due);
      expect(ready, hasLength(1));
      expect(ready.first.plantId, 'p_1');
      await database.bloomRewardDao.markClaimed('pr_1');
      expect(await database.bloomRewardDao.pendingDue(due), isEmpty);
    });

    test('回归 A：同 id 覆盖写 pending（改 due_at）走 upsert，不抛 UNIQUE 崩溃', () async {
      final db.AppDatabase database = await _openMigrated(
        _v9Ddl(withLegacyPlants: false),
        9,
      );
      final DateTime bloom = DateTime(2026, 9, 25, 8, 0);
      final DateTime due48h =
          bloom.add(const Duration(hours: kBloomRewardDelayHours));

      // 首次写入（开花 48h 掉落）。
      await database.bloomRewardDao.insertPending(
        db.PendingBloomRewardsCompanion(
          id: const Value('pr_dup'),
          plantId: const Value('p_dup'),
          dueAt: Value(due48h),
          rewardKind: const Value(kBloomRewardKindNormal),
        ),
      );
      expect(await database.bloomRewardDao.pendingDue(bloom), isEmpty,
          reason: '未到 48h 不可领取');

      // 同 id 重写：把 due_at 提前到「已到期」（模拟调试面板「让奖励现在可领取」）。
      // 旧实现为裸 insert() → 真实 SQLite 抛 SqliteException(1555) UNIQUE constraint failed；
      // 修为 upsert 后此处安全幂等，不得抛异常、不得产生第二行。
      await database.bloomRewardDao.insertPending(
        db.PendingBloomRewardsCompanion(
          id: const Value('pr_dup'),
          plantId: const Value('p_dup'),
          dueAt: Value(bloom.subtract(const Duration(seconds: 1))),
          rewardKind: const Value(kBloomRewardKindNormal),
        ),
      );

      final List<db.PendingBloomRewardRow> due =
          await database.bloomRewardDao.pendingDue(bloom);
      expect(due, hasLength(1), reason: '同 id 覆盖写，不得产生第二行');
      expect(due.first.id, 'pr_dup');
      expect(due.first.dueAt.isBefore(bloom), isTrue,
          reason: 'due_at 应被覆盖为「已到期」');
    });
  });

  group('幂等：已迁移到 v10 的库重复打开不报错、不丢数据', () {
    test('重新打开文件库：bloom_count 列与 3 张新表仍在、数据原样保留', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v10');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v9Ddl(withLegacyPlants: true)) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 9;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 16);
      // 首次迁移：bloomed_at 非空的行被回填为 1。
      expect((await first.plantDao.byId('p_bloomed'))!.bloomCount, 1);
      // 模拟该株之后又盛开若干次（写一个 ≠1 的值，验证二次打开不会被回填覆盖/叠加）。
      await first.customStatement(
        "UPDATE plants SET bloom_count = 5 WHERE id = 'p_bloomed';",
      );
      await first.bloomRewardDao.setFragmentBalance(4);
      await first.bloomRewardDao.unlockSpecies('species_star_flower');
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();

      expect(await _columns(second, 'plants'), contains('bloom_count'));
      expect(await _tableExists(second, 'unlocked_species'), isTrue);
      expect(await second.bloomRewardDao.fragmentBalance(), 4,
          reason: '碎片余额不应丢失');
      expect(await second.bloomRewardDao.unlockedSpeciesIds(),
          <String>['species_star_flower']);
      expect((await second.plantDao.byId('p_bloomed'))!.status,
          PlantStatus.bloomed.index);
      expect((await second.plantDao.byId('p_bloomed'))!.bloomCount, 5,
          reason: '二次打开不得重跑回填 UPDATE（否则 5 会被覆盖成 1）');
    });
  });

  group('跨版本跳跃升级', () {
    test('v7 → v10：v7 清零逻辑仍执行 + v8 补 bloomed_at + v10 补 bloom_count/新表', () async {
      // v7 的 plants 无 bloom_count、无 bloomed_at；这里用 v9 DDL（已有 bloomed_at）
      // 不足以模拟 v7，故用一个「v7 风格」DDL：plants 去掉 bloomed_at。
      final List<String> v7Ddl = _v9Ddl(withLegacyPlants: false);
      // 用 v7 的 plants 结构（无 bloomed_at / bloom_count）替换。
      v7Ddl[1] = 'CREATE TABLE plants ('
          'id TEXT NOT NULL, species_id TEXT NOT NULL, pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, stage_started_at INTEGER NOT NULL, '
          'growth_progress REAL NOT NULL DEFAULT 0.0, growth_factor REAL NOT NULL DEFAULT 1.0, '
          'water_used INTEGER NOT NULL DEFAULT 0, fertilizer_used INTEGER NOT NULL DEFAULT 0, '
          'status INTEGER NOT NULL, planted_at INTEGER NOT NULL, '
          'last_water_at INTEGER, wilted_at INTEGER, dead_at INTEGER, '
          'mood INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));';
      v7Ddl.add(
        'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
        'growth_progress, growth_factor, water_used, fertilizer_used, status, '
        'planted_at, last_water_at, wilted_at, dead_at, mood) '
        'VALUES (\'p_growing\', \'species_sunflower\', 0, '
        '${PlantStage.adult.index}, ${_secs(_legacyStageStarted)}, 0.6, 1.0, '
        '1, 1, ${PlantStatus.growing.index}, ${_secs(_legacyPlanted)}, '
        '${_secs(_legacyPlanted)}, NULL, NULL, 0);',
      );

      final db.AppDatabase database = await _openMigrated(v7Ddl, 7);
      expect(database.schemaVersion, 16);

      // ① v7 的清零分支（from<7 不成立，from==7），故 growing 不被清零——但这里模拟
      //    的是 from==7，v7 的清零分支只在 from<7 才执行。数据应保持。
      final db.Plant growing = (await database.plantDao.byId('p_growing'))!;
      expect(growing.growthProgress, 0.6);
      // v7 的 plants 无 bloomed_at 列（v8 才加），故跨版本升级后历史行 bloomed_at 仍为 NULL
      // → 不满足回填条件（bloomed_at IS NOT NULL），bloom_count 保持默认 0。
      // （bloomed_at 非空行的回填覆盖见上一个 group 的 v9→v10 用例。）
      expect(growing.bloomedAt, isNull);
      expect(growing.bloomCount, 0, reason: 'bloomed_at 为空 → 不回填，保持默认 0');

      // ② v8 补列：bloomed_at 存在。
      expect(await _columns(database, 'plants'), contains('bloomed_at'));
      // ③ v10 补列 / 新表。
      expect(await _columns(database, 'plants'), contains('bloom_count'));
      expect(await _tableExists(database, 'pending_bloom_rewards'), isTrue);
    });

    test('v3 → v10（无 plants 表）由 createAll 建出，迁移不报错', () async {
      // v3：无 plants 表、无 garden_pot_capacity、无 custom_subject、无 check_ins 5 列。
      final List<String> v3Ddl = <String>[
        'CREATE TABLE settings ('
            'id INTEGER NOT NULL, age_tier INTEGER NOT NULL, '
            'night_boundary_hour INTEGER NOT NULL DEFAULT 21, '
            'night_boundary_minute INTEGER NOT NULL DEFAULT 0, '
            'daily_focus_cap INTEGER NOT NULL, daily_app_cap_minutes INTEGER NOT NULL, '
            'rest_after_sessions INTEGER NOT NULL, rest_minutes INTEGER NOT NULL, '
            'task_sunlight INTEGER NOT NULL, monthly_pool_budget INTEGER NOT NULL, '
            'quiet_mode INTEGER NOT NULL DEFAULT 0, sound_on INTEGER NOT NULL DEFAULT 1, '
            'bgm_on INTEGER NOT NULL DEFAULT 0, detection_on INTEGER NOT NULL DEFAULT 1, '
            'auto_confirm_single_high INTEGER NOT NULL DEFAULT 130, '
            'auto_confirm_single_low INTEGER NOT NULL DEFAULT 50, '
            'auto_confirm_monthly_pct REAL NOT NULL DEFAULT 0.25, '
            'currency_rate REAL NOT NULL DEFAULT 0.25, theme_dark INTEGER NOT NULL DEFAULT 1, '
            'autonomous_mode INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
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
            'requires_focus INTEGER NOT NULL, min_focus_min INTEGER NOT NULL DEFAULT 15, '
            'sunlight_reward INTEGER NOT NULL DEFAULT 12, repeat_rule TEXT, '
            'is_custom INTEGER NOT NULL, PRIMARY KEY (id));',
        'CREATE TABLE check_ins ('
            'id TEXT NOT NULL, task_id TEXT NOT NULL, date INTEGER NOT NULL, '
            'completed_at INTEGER NOT NULL, session_id TEXT, is_perfect_day INTEGER NOT NULL, '
            'PRIMARY KEY (id));',
        'CREATE TABLE cooldown_counters ('
            'template_id TEXT NOT NULL, period INTEGER NOT NULL, used_count INTEGER NOT NULL DEFAULT 0, '
            'PRIMARY KEY (template_id, period));',
        'CREATE TABLE tracking_events ('
            'id TEXT NOT NULL, name TEXT NOT NULL DEFAULT \'\', type INTEGER NOT NULL, '
            'ts INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY (id));',
      ];

      final db.AppDatabase database = await _openMigrated(v3Ddl, 3);
      expect(database.schemaVersion, 16);
      expect(await _tableExists(database, 'plants'), isTrue);
      expect(await _columns(database, 'plants'), contains('bloom_count'));
      expect(await _tableExists(database, 'premium_fragments'), isTrue);
      expect(await database.plantDao.all(), isEmpty);
    });
  });
}
