/// 迁移回归测试 v10 → v11（**物种表改版**，玄参 2026-09-27 拍板）：
/// 移除 `species_daisy`（小雏菊）/ `species_cactus`（仙人掌）两个旧物种，
/// 其**存量植株直接删除**（不做迁移映射；这两物种已从物种表下线）。
///
/// 本测试钉死五件事（**必须把历史行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 15`；
///  ② v10 → v11 后 daisy / cactus 的存量植株 **被删除**（byId 返回 null、计数归零）；
///  ③ 其它物种（向日葵 / 番茄）植株 **原样保留**（含各字段逐项一致）；
///  ④ 其它表数据（settings / 碎片余额 / 已解锁物种 / 待收集奖励）原样保留；
///  ⑤ 幂等 + 版本守卫：已迁移到 v11 的库**二次打开不再执行删除分支**
///     （迁移后新写入的 species_daisy 行不会被二次打开误删）；幂等重复打开不丢数据。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**，
///    故「老库」DDL 的日期列一律用 `INTEGER`（秒），否则读回会因类型不匹配而失败。
library migration_v10_to_v11_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

final DateTime _legacyStageStarted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyPlanted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyBloomedStarted = DateTime(2026, 8, 20, 10, 0);
final DateTime _legacyDue48h = DateTime(2026, 8, 22, 10, 0);

/// v10 线上 schema：plants 已含 `bloom_count`；3 张 Batch 1 新表
/// （premium_fragments / pending_bloom_rewards / unlocked_species）已存在。
List<String> _v10Ddl({required bool withLegacyPlants}) {
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
        'bloom_count INTEGER NOT NULL DEFAULT 0, '
        'mood INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
    'CREATE TABLE premium_fragments ('
        'id INTEGER NOT NULL, balance INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
    'CREATE TABLE pending_bloom_rewards ('
        'id TEXT NOT NULL, plant_id TEXT NOT NULL, due_at INTEGER NOT NULL, '
        'reward_kind TEXT NOT NULL, claimed INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
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
    // 单行 settings（用于验证「其它表数据原样保留」）。
    'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
        'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget, '
        'garden_pot_capacity) VALUES (1, ${AgeTier.low.index}, 90, 30, 2, 10, 12, 160, 12);',
    // 碎片余额 + 已解锁物种 + 待收集奖励（Batch 1 三表，验证迁移不误伤）。
    'INSERT INTO premium_fragments (id, balance) VALUES (1, 7);',
    'INSERT INTO unlocked_species (species_id) VALUES (\'species_star_flower\');',
    'INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed) '
        'VALUES (\'pr_1\', \'p_sunflower\', ${_secs(_legacyDue48h)}, \'normal\', 0);',
    if (withLegacyPlants) ...<String>[
      // 保留物种：向日葵（精英后重命名与删除无关，必须原样保留）。
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
          'VALUES (\'p_sunflower\', \'species_sunflower\', 0, '
          '${PlantStage.adult.index}, ${_secs(_legacyStageStarted)}, 0.6, 1.0, '
          '1, 1, ${PlantStatus.growing.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, NULL, 0, 0);',
      // 保留物种：番茄（已开花，bloom_count=2）。
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
          'VALUES (\'p_tomato\', \'species_tomato\', 1, '
          '${PlantStage.adult.index}, ${_secs(_legacyBloomedStarted)}, 1.0, 1.0, '
          '1, 1, ${PlantStatus.bloomed.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, ${_secs(_legacyBloomedStarted)}, 2, 0);',
      // 待删除物种：小雏菊（存活）。
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
          'VALUES (\'p_daisy\', \'species_daisy\', 2, '
          '${PlantStage.sprout.index}, ${_secs(_legacyStageStarted)}, 0.35, 1.0, '
          '0, 0, ${PlantStatus.growing.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, NULL, NULL, 0, 0);',
      // 待删除物种：仙人掌（已死亡）。
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
          'VALUES (\'p_cactus\', \'species_cactus\', 3, '
          '${PlantStage.seed.index}, ${_secs(_legacyStageStarted)}, 0.1, 1.0, '
          '0, 0, ${PlantStatus.dead.index}, ${_secs(_legacyPlanted)}, '
          '${_secs(_legacyPlanted)}, NULL, ${_secs(_legacyStageStarted)}, NULL, 0, 0);',
    ],
  ];
}

/// 某表当前行数。
Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row =
      await database.customSelect('SELECT COUNT(*) AS c FROM $table;').getSingle();
  return row.read<int>('c');
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
  group('迁移 v10->v11：移除 daisy / cactus 存量植株', () {
    test('schemaVersion 必须为最新 14（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(
        _v10Ddl(withLegacyPlants: true),
        10,
      );
      expect(database.schemaVersion, 18);
    });

    test('daisy / cactus 存量植株被删除；保留物种原样保留', () async {
      final db.AppDatabase database = await _openMigrated(
        _v10Ddl(withLegacyPlants: true),
        10,
      );

      // ② 待删除物种：byId 返回 null。
      expect(await database.plantDao.byId('p_daisy'), isNull,
          reason: 'species_daisy 已下线 → 存量植株应被删除');
      expect(await database.plantDao.byId('p_cactus'), isNull,
          reason: 'species_cactus 已下线 → 存量植株应被删除（死株同样删）');

      // ③ 保留物种：其它字段逐项一致。
      final db.Plant sunflower = (await database.plantDao.byId('p_sunflower'))!;
      expect(sunflower.speciesId, 'species_sunflower');
      expect(sunflower.potIndex, 0);
      expect(sunflower.status, PlantStatus.growing.index);
      expect(sunflower.stage, PlantStage.adult.index);
      expect(sunflower.growthProgress, 0.6);
      expect(sunflower.bloomedAt, isNull);
      expect(sunflower.bloomCount, 0);

      final db.Plant tomato = (await database.plantDao.byId('p_tomato'))!;
      expect(tomato.speciesId, 'species_tomato');
      expect(tomato.status, PlantStatus.bloomed.index);
      expect(tomato.bloomedAt, _legacyBloomedStarted);
      expect(tomato.bloomCount, 2, reason: '保留物种的字段不得被迁移改动');

      // 仅剩两株（daisy / cactus 已删）。
      expect(await _count(database, 'plants'), 2);
      final List<db.Plant> all = await database.plantDao.all();
      expect(all.map((db.Plant p) => p.id).toSet(),
          <String>{'p_sunflower', 'p_tomato'});
    });

    test('其它表数据原样保留（settings / 碎片 / 已解锁 / 待收集奖励）', () async {
      final db.AppDatabase database = await _openMigrated(
        _v10Ddl(withLegacyPlants: true),
        10,
      );

      expect(await _count(database, 'settings'), 1);
      expect(await database.bloomRewardDao.fragmentBalance(), 7,
          reason: '碎片余额不应被迁移影响');
      expect(await database.bloomRewardDao.unlockedSpeciesIds(),
          <String>['species_star_flower'],
          reason: '已解锁物种（免费种植券）不应被迁移影响');
      expect(await _count(database, 'pending_bloom_rewards'), 1,
          reason: '待收集奖励不应被迁移影响');
    });

    test('物种表仅删指定物种：无 daisy / cactus 时迁移不误删其它行', () async {
      final db.AppDatabase database = await _openMigrated(
        _v10Ddl(withLegacyPlants: false),
        10,
      );
      // 老库无植物 → 删除分支无匹配行，不得报错。
      expect(await _count(database, 'plants'), 0);

      // 迁移后写入一株保留物种 → 不应被删。
      final DateTime t = DateTime(2026, 9, 27, 8, 0);
      await database.plantDao.upsert(
        db.PlantsCompanion(
          id: const Value('p_new'),
          speciesId: const Value('species_rainbow_fern'),
          potIndex: const Value(0),
          stage: Value(PlantStage.seed.index),
          stageStartedAt: Value(t),
          status: Value(PlantStatus.growing.index),
          plantedAt: Value(t),
        ),
      );
      expect(await database.plantDao.byId('p_new'), isNotNull);
    });
  });

  group('幂等 / 版本守卫：已迁移到 v11 的库重复打开', () {
    test('二次打开不再执行删除分支（迁移后写入的 daisy 行不被误删）+ 数据不丢', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v11');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      // 首次打开：v10 → v11，daisy / cactus 被删。
      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v10Ddl(withLegacyPlants: true)) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 10;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 18);
      expect(await first.plantDao.byId('p_daisy'), isNull);
      expect(await first.plantDao.byId('p_sunflower'), isNotNull);

      // 迁移后「人为」再写一株 species_daisy（模拟：from==11 后再出现的行）。
      await first.customStatement(
        'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
        'growth_progress, growth_factor, water_used, fertilizer_used, status, '
        'planted_at, bloom_count, mood) '
        'VALUES (\'p_daisy_after\', \'species_daisy\', 5, '
        '${PlantStage.seed.index}, ${_secs(_legacyStageStarted)}, 0.0, 1.0, '
        '0, 0, ${PlantStatus.growing.index}, ${_secs(_legacyPlanted)}, 0, 0);',
      );
      await first.bloomRewardDao.setFragmentBalance(3);
      await first.close();

      // 二次打开（from==11）：删除分支不应再执行。
      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 18);
      expect(await second.plantDao.byId('p_sunflower'), isNotNull,
          reason: '二次打开不得丢数据');
      expect(await second.plantDao.byId('p_daisy_after'), isNotNull,
          reason: '删除分支带 from<11 守卫 → from==11 时不得再执行（幂等/守卫验证）');
      expect(await second.bloomRewardDao.fragmentBalance(), 3,
          reason: '碎片余额不应丢失');
    });
  });
}
