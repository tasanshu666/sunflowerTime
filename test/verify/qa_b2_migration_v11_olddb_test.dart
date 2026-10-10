/// 独立复验探针 E（qa-verify2）：v11 迁移（物种表改版）。
///
/// 自建「v10 老库」（含 daisy / cactus / sunflower 植株 + 多张代表性业务表数据）→
/// 升级读回，逐条断言；再验证**迁移幂等 / 版本守卫**。
///
/// 注：当前 `AppDatabase.schemaVersion` 已推进到 **12**（v12 奖励物图标化 + 掉落即定奖），
/// 故版本护栏断言为 12；v10 → v11 的删除分支行为不因此变化。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**，
///    故老库 DDL 的日期列一律 INTEGER（秒）。
library qa_b2_migration_v11_olddb_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

final DateTime _stageAt = DateTime(2026, 9, 1, 8, 0);
final DateTime _plantedAt = DateTime(2026, 9, 1, 8, 0);
final DateTime _bloomAt = DateTime(2026, 8, 20, 10, 0);

/// v10 线上 schema（plants 已含 bloom_count；3 张 Batch 1 表已存在）。
List<String> _v10Ddl({required bool withLegacyPlants}) => <String>[
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
          'autonomous_mode INTEGER NOT NULL DEFAULT 0, '
          'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, PRIMARY KEY (id));',
      'CREATE TABLE plants ('
          'id TEXT NOT NULL, species_id TEXT NOT NULL, pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, stage_started_at INTEGER NOT NULL, '
          'growth_progress REAL NOT NULL DEFAULT 0.0, growth_factor REAL NOT NULL DEFAULT 1.0, '
          'water_used INTEGER NOT NULL DEFAULT 0, fertilizer_used INTEGER NOT NULL DEFAULT 0, '
          'status INTEGER NOT NULL, planted_at INTEGER NOT NULL, '
          'last_water_at INTEGER, wilted_at INTEGER, dead_at INTEGER, bloomed_at INTEGER, '
          'bloom_count INTEGER NOT NULL DEFAULT 0, mood INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id));',
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
      'CREATE TABLE tasks ('
          'id TEXT NOT NULL, name TEXT NOT NULL, subject INTEGER NOT NULL, '
          'custom_subject TEXT, requires_focus INTEGER NOT NULL, '
          'min_focus_min INTEGER NOT NULL DEFAULT 15, '
          'sunlight_reward INTEGER NOT NULL DEFAULT 12, repeat_rule TEXT, '
          'is_custom INTEGER NOT NULL, category INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
      'CREATE TABLE check_ins ('
          'id TEXT NOT NULL, task_id TEXT NOT NULL, date INTEGER NOT NULL, '
          'completed_at INTEGER NOT NULL, session_id TEXT, is_perfect_day INTEGER NOT NULL, '
          'status INTEGER NOT NULL DEFAULT 0, sunlight_gross REAL NOT NULL DEFAULT 0.0, '
          'sunlight_granted REAL NOT NULL DEFAULT 0.0, resolved_at INTEGER, '
          'parent_note TEXT, PRIMARY KEY (id));',
      'CREATE TABLE tracking_events ('
          'id TEXT NOT NULL, name TEXT NOT NULL DEFAULT \'\', type INTEGER NOT NULL, '
          'ts INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY (id));',
      // 代表性数据（验证迁移不误伤）。
      'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
          'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget, '
          'garden_pot_capacity) VALUES (1, ${AgeTier.low.index}, 90, 30, 2, 10, 12, 160, 12);',
      'INSERT INTO premium_fragments (id, balance) VALUES (1, 9);',
      'INSERT INTO unlocked_species (species_id) VALUES (\'species_rainbow_fern\');',
      'INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed) '
          'VALUES (\'pr_x\', \'p_sunflower\', ${_secs(_bloomAt)}, \'normal\', 0);',
      'INSERT INTO sunlight_ledgers (id, ts, type, gross, net, balance_after, ref_type, ref_id, day_key) '
          'VALUES (\'led_x\', ${_secs(_stageAt)}, ${SunlightType.earn.index}, 10, 10, 10, \'seed\', NULL, \'2026-09-01\');',
      'INSERT INTO tasks (id, name, subject, requires_focus, is_custom) '
          'VALUES (\'t_x\', \'读书\', ${TaskSubject.chinese.index}, 1, 0);',
      'INSERT INTO check_ins (id, task_id, date, completed_at, is_perfect_day) '
          'VALUES (\'ci_x\', \'t_x\', ${_secs(_stageAt)}, ${_secs(_stageAt)}, 0);',
      'INSERT INTO tracking_events (id, name, type, ts, payload) '
          'VALUES (\'te_x\', \'evt\', ${TrackingType.metric.index}, ${_secs(_stageAt)}, \'{}\');',
      if (withLegacyPlants) ...<String>[
        // 保留物种：向日葵（应原样保留）。
        'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
            'growth_progress, growth_factor, water_used, fertilizer_used, status, '
            'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
            'VALUES (\'p_sunflower\', \'species_sunflower\', 0, '
            '${PlantStage.adult.index}, ${_secs(_stageAt)}, 0.6, 1.3, 1, 1, '
            '${PlantStatus.growing.index}, ${_secs(_plantedAt)}, ${_secs(_plantedAt)}, '
            'NULL, NULL, NULL, 0, ${PlantMood.thirsty.index});',
        // 待删物种：小雏菊（存活）。
        'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
            'growth_progress, growth_factor, water_used, fertilizer_used, status, '
            'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
            'VALUES (\'p_daisy\', \'species_daisy\', 2, '
            '${PlantStage.sprout.index}, ${_secs(_stageAt)}, 0.35, 1.0, 0, 0, '
            '${PlantStatus.growing.index}, ${_secs(_plantedAt)}, ${_secs(_plantedAt)}, '
            'NULL, NULL, NULL, 0, 0);',
        // 待删物种：仙人掌（已死亡）。
        'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
            'growth_progress, growth_factor, water_used, fertilizer_used, status, '
            'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
            'VALUES (\'p_cactus\', \'species_cactus\', 3, '
            '${PlantStage.seed.index}, ${_secs(_stageAt)}, 0.1, 1.0, 0, 0, '
            '${PlantStatus.dead.index}, ${_secs(_plantedAt)}, ${_secs(_plantedAt)}, '
            'NULL, ${_secs(_stageAt)}, NULL, 0, 0);',
      ],
    ];

Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row =
      await database.customSelect('SELECT COUNT(*) AS c FROM $table;').getSingle();
  return row.read<int>('c');
}

Future<db.AppDatabase> _openMigrated(List<String> ddl, int userVersion) async {
  final NativeDatabase executor = NativeDatabase.memory(
    setup: (rawDb) {
      for (final String sql in ddl) {
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
  group('E · v11 迁移：移除 daisy / cactus 存量植株', () {
    test('schemaVersion == 13（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database =
          await _openMigrated(_v10Ddl(withLegacyPlants: true), 10);
      expect(database.schemaVersion, 20);
    });

    test('daisy / cactus 行被删除；向日葵行完好保留（含各字段）', () async {
      final db.AppDatabase database =
          await _openMigrated(_v10Ddl(withLegacyPlants: true), 10);

      expect(await database.plantDao.byId('p_daisy'), isNull,
          reason: 'species_daisy 已下线 → 存活植株应删');
      expect(await database.plantDao.byId('p_cactus'), isNull,
          reason: 'species_cactus 已下线 → 死株同样删');

      final db.Plant sf = (await database.plantDao.byId('p_sunflower'))!;
      expect(sf.speciesId, 'species_sunflower');
      expect(sf.potIndex, 0);
      expect(sf.stage, PlantStage.adult.index);
      expect(sf.status, PlantStatus.growing.index);
      expect(sf.growthProgress, 0.6);
      expect(sf.growthFactor, 1.3);
      expect(sf.waterUsed, isTrue);
      expect(sf.fertilizerUsed, isTrue);
      expect(sf.mood, PlantMood.thirsty.index);
      expect(sf.bloomCount, 0);

      expect(await _count(database, 'plants'), 1);
    });

    test('其它表数据未丢（settings / 碎片 / 券 / pending / 账本 / 任务 / 打卡 / 埋点）', () async {
      final db.AppDatabase database =
          await _openMigrated(_v10Ddl(withLegacyPlants: true), 10);

      expect(await _count(database, 'settings'), 1);
      expect(await database.bloomRewardDao.fragmentBalance(), 9);
      expect(await database.bloomRewardDao.unlockedSpeciesIds(),
          <String>['species_rainbow_fern']);
      expect(await _count(database, 'pending_bloom_rewards'), 1);
      expect(await _count(database, 'sunlight_ledgers'), 1);
      expect(await _count(database, 'tasks'), 1);
      expect(await _count(database, 'check_ins'), 1);
      expect(await _count(database, 'tracking_events'), 1);
    });

    test('老库无 daisy / cactus 时迁移不误删其它物种行', () async {
      final db.AppDatabase database =
          await _openMigrated(_v10Ddl(withLegacyPlants: false), 10);
      expect(await _count(database, 'plants'), 0);

      final DateTime t = DateTime(2026, 9, 27, 8);
      await database.plantDao.upsert(db.PlantsCompanion(
        id: const Value('p_new'),
        speciesId: const Value('species_jade_hydrangea'),
        potIndex: const Value(0),
        stage: Value(PlantStage.seed.index),
        stageStartedAt: Value(t),
        status: Value(PlantStatus.growing.index),
        plantedAt: Value(t),
      ));
      expect(await database.plantDao.byId('p_new'), isNotNull);
    });
  });

  group('E · 幂等 / 版本守卫：已迁移到 v12 的库重复打开', () {
    test('二次打开不再执行删除分支（迁移后写入的 daisy 行不被误删）+ 数据不丢', () async {
      final Directory dir = Directory.systemTemp.createTempSync('qa_v11');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(NativeDatabase(
        file,
        setup: (rawDb) {
          for (final String sql in _v10Ddl(withLegacyPlants: true)) {
            rawDb.execute(sql);
          }
          rawDb.execute('PRAGMA user_version = 10;');
        },
      ));
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 20);
      expect(await first.plantDao.byId('p_daisy'), isNull);
      expect(await first.plantDao.byId('p_sunflower'), isNotNull);

      // 迁移后人为再写一株 species_daisy（模拟 v11 后新出现的行）。
      await first.customStatement(
        'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
        'growth_progress, growth_factor, water_used, fertilizer_used, status, '
        'planted_at, bloom_count, mood) '
        'VALUES (\'p_daisy_after\', \'species_daisy\', 5, ${PlantStage.seed.index}, '
        '${_secs(_stageAt)}, 0.0, 1.0, 0, 0, ${PlantStatus.growing.index}, '
        '${_secs(_plantedAt)}, 0, 0);',
      );
      await first.bloomRewardDao.setFragmentBalance(3);
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 20);
      expect(await second.plantDao.byId('p_sunflower'), isNotNull);
      expect(await second.plantDao.byId('p_daisy_after'), isNotNull,
          reason: 'from<11 守卫 → from==11 不再执行删除（幂等/守卫验证）');
      expect(await second.bloomRewardDao.fragmentBalance(), 3);
    });
  });
}
