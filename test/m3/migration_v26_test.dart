/// 迁移回归测试 v25 → v26（**C90 期 1：新增 child_profiles 表**，玄参 2026-10-17）。
///
/// 背景（C90 期 1 拍板口径）：多孩子档案数据底座 —— 新表 `child_profiles`
///（id / name / age_tier / created_at），仅建表、无列变更、无历史行改写。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion == 26`；
///  ② v25 旧库（4 张历史表 DDL + 历史行）→ 迁移后 **children 表存在且为空**
///     （🔴 默认孩子**不在迁移里插**：由 App 层 `AccountService.initialize()`
///     冷启动补，全新安装与老库升级同一条路）；
///  ③ 老行全部可读：settings / plants / sunlight_ledgers / redemption_requests
///     （含默认 childId）逐位保留；
///  ④ ageTier 读回正确（经 `SettingsLocalRepository` 端到端）；
///  ⑤ 幂等：二次访问不报错、children 不被填充。
library migration_v26_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// v25 时期 settings 表 DDL（v26 未改 settings；⚠️ 与现库列集一致）。
const String _settingsV25Ddl = 'CREATE TABLE "settings" ('
    '"id" INTEGER NOT NULL, "age_tier" INTEGER NOT NULL, '
    '"night_boundary_hour" INTEGER NOT NULL DEFAULT 21, '
    '"night_boundary_minute" INTEGER NOT NULL DEFAULT 0, '
    '"daily_focus_cap" INTEGER NOT NULL, "daily_app_cap_minutes" INTEGER NOT NULL, '
    '"rest_after_sessions" INTEGER NOT NULL, "rest_minutes" INTEGER NOT NULL, '
    '"task_sunlight" INTEGER NOT NULL, "monthly_pool_budget" INTEGER NOT NULL, '
    '"quiet_mode" INTEGER NOT NULL DEFAULT 0, "sound_on" INTEGER NOT NULL DEFAULT 1, '
    '"bgm_on" INTEGER NOT NULL DEFAULT 1, '
    '"auto_confirm_single_high" INTEGER NOT NULL DEFAULT 130, '
    '"auto_confirm_single_low" INTEGER NOT NULL DEFAULT 50, '
    '"auto_confirm_monthly_pct" REAL NOT NULL DEFAULT 0.25, '
    '"currency_rate" REAL NOT NULL DEFAULT 0.25, '
    '"theme_dark" INTEGER NOT NULL DEFAULT 0, '
    '"garden_pot_capacity" INTEGER NOT NULL DEFAULT 4, '
    '"eye_care_enabled" INTEGER NOT NULL DEFAULT 1, '
    '"eye_care_interval_min" INTEGER NOT NULL DEFAULT 20, '
    '"eye_care_skip_allowed" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));';

/// settings 历史行（家长动过：night_boundary 22:30、garden_pot_capacity 6）。
const String _settingsRowSeed = 'INSERT INTO settings ('
    'id, age_tier, night_boundary_hour, night_boundary_minute, '
    'daily_focus_cap, daily_app_cap_minutes, rest_after_sessions, rest_minutes, '
    'task_sunlight, monthly_pool_budget, quiet_mode, sound_on, bgm_on, '
    'auto_confirm_single_high, auto_confirm_single_low, '
    'auto_confirm_monthly_pct, currency_rate, theme_dark, '
    'garden_pot_capacity, eye_care_enabled, eye_care_interval_min, '
    'eye_care_skip_allowed) VALUES '
    "(1, 2, 22, 30, 90, 45, 3, 15, 12, 200, 1, 0, 1, 130, 50, 0.25, 0.25, 1, 6, 1, 20, 0);";

/// v25 时期 plants 表 DDL（v26 未改 plants）。
const String _plantsV25Ddl = 'CREATE TABLE "plants" ('
    '"id" TEXT NOT NULL, "species_id" TEXT NOT NULL, '
    '"pot_index" INTEGER NOT NULL, "stage" INTEGER NOT NULL, '
    '"stage_started_at" INTEGER NOT NULL, '
    '"growth_progress" REAL NOT NULL DEFAULT 0.0, '
    '"growth_factor" REAL NOT NULL DEFAULT 1.0, '
    '"water_used" INTEGER NOT NULL DEFAULT 0, '
    '"fertilizer_used" INTEGER NOT NULL DEFAULT 0, '
    '"status" INTEGER NOT NULL, "planted_at" INTEGER NOT NULL, '
    '"last_water_at" INTEGER NULL, "wilted_at" INTEGER NULL, '
    '"dead_at" INTEGER NULL, "bloomed_at" INTEGER NULL, '
    '"bloom_count" INTEGER NOT NULL DEFAULT 0, "mood" INTEGER NOT NULL DEFAULT 0, '
    '"weed_at" INTEGER NULL, "pest_at" INTEGER NULL, '
    '"weed_pest_roll_day" INTEGER NULL, '
    '"shovel_refund" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));';

const String _plantRowSeed = "INSERT INTO plants (id, species_id, pot_index, "
    "stage, stage_started_at, status, planted_at) VALUES "
    "('p1', 'sunflower', 0, 0, 1729000000, 0, 1729000000);";

/// v25 时期 sunlight_ledgers 表 DDL（v26 未改账本）。
const String _ledgersV25Ddl = 'CREATE TABLE "sunlight_ledgers" ('
    '"id" TEXT NOT NULL, "ts" INTEGER NOT NULL, "type" INTEGER NOT NULL, '
    '"gross" REAL NOT NULL, "net" REAL NOT NULL, '
    '"balance_after" REAL NOT NULL, "ref_type" TEXT NULL, "ref_id" TEXT NULL, '
    '"day_key" TEXT NOT NULL, PRIMARY KEY ("id"));';

const String _ledgerRowSeed = "INSERT INTO sunlight_ledgers (id, ts, type, "
    "gross, net, balance_after, ref_type, ref_id, day_key) VALUES "
    "('l1', 1729000000, 0, 12.0, 12.0, 12.0, 'task_checkin', 't1', '2026-10-10');";

/// v25 时期 redemption_requests 表 DDL（v26 未改；child_id 有默认值）。
const String _requestsV25Ddl = 'CREATE TABLE "redemption_requests" ('
    '"id" TEXT NOT NULL, "template_id" TEXT NOT NULL, '
    '"requested_at" INTEGER NOT NULL, "cost" INTEGER NOT NULL, '
    '"status" INTEGER NOT NULL, "auto_approved" INTEGER NOT NULL DEFAULT 0, '
    '"queue_position" INTEGER NULL, "verified_at" INTEGER NULL, '
    '"parent_note" TEXT NULL, '
    '"child_id" TEXT NOT NULL DEFAULT \'single-child\', PRIMARY KEY ("id"));';

const String _requestRowSeed = "INSERT INTO redemption_requests (id, "
    "template_id, requested_at, cost, status) VALUES "
    "('r1', 'seed_snack', 1729000000, 30, 0);";

/// 打开一个「v25 旧库」：4 张历史表（v25 列集）+ 历史行 + `user_version = 25`，
/// 打开即触发 v26 迁移（child_profiles 等缺失表由 onUpgrade 首步
/// `m.createAll()` 幂等补齐）。
Future<db.AppDatabase> _openV25() async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute(_settingsV25Ddl);
        rawDb.execute(_plantsV25Ddl);
        rawDb.execute(_ledgersV25Ddl);
        rawDb.execute(_requestsV25Ddl);
        rawDb.execute(_settingsRowSeed);
        rawDb.execute(_plantRowSeed);
        rawDb.execute(_ledgerRowSeed);
        rawDb.execute(_requestRowSeed);
        rawDb.execute('PRAGMA user_version = 25;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get(); // 首次访问触发迁移
  return database;
}

Future<int> _tableCount(db.AppDatabase d, String table) async {
  final QueryRow row = await d
      .customSelect('SELECT COUNT(*) AS c FROM $table;')
      .getSingle();
  return row.read<int>('c');
}

Future<bool> _tableExists(db.AppDatabase d, String table) async {
  final List<QueryRow> rows = await d
      .customSelect("SELECT name FROM sqlite_master WHERE type='table' "
          "AND name = '$table';")
      .get();
  return rows.isNotEmpty;
}

void main() {
  group('迁移 v25->v26：新增 child_profiles（C90 期 1）', () {
    test('① schemaVersion 必须为最新 26（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV25();
      addTearDown(database.close);
      expect(database.schemaVersion, 27);
    });

    test('② children 表存在且为空（默认孩子由 App 层补，不在迁移里插）', () async {
      final db.AppDatabase database = await _openV25();
      addTearDown(database.close);

      expect(await _tableExists(database, 'child_profiles'), isTrue,
          reason: 'v26 必须建出 child_profiles 表');
      expect(await _tableCount(database, 'child_profiles'), 0,
          reason: '🔴 默认孩子不在迁移里插（AccountService.initialize 冷启动补，'
              '空表才建 —— 全新安装与老库升级同一条路）');
    });

    test('③ 老行全部可读：settings / plants / ledgers / requests（含默认 childId）',
        () async {
      final db.AppDatabase database = await _openV25();
      addTearDown(database.close);

      expect(await _tableCount(database, 'settings'), 1);
      expect(await _tableCount(database, 'plants'), 1);
      expect(await _tableCount(database, 'sunlight_ledgers'), 1);
      expect(await _tableCount(database, 'redemption_requests'), 1);

      final Map<String, Object?> s =
          (await database.customSelect('SELECT * FROM settings WHERE id = 1;')
              .getSingle())
          .data;
      expect(s['age_tier'], 2);
      expect(s['night_boundary_hour'], 22);
      expect(s['night_boundary_minute'], 30);
      expect(s['garden_pot_capacity'], 6);
      expect(s['eye_care_skip_allowed'], 0);

      final Map<String, Object?> r = (await database
              .customSelect("SELECT * FROM redemption_requests WHERE id = 'r1';")
              .getSingle())
          .data;
      expect(r['child_id'], 'single-child',
          reason: 'C90 期 1 唯一真实数据效应：兑换记录按活跃孩子落 childId（'
              '历史行默认 single-child 必须原样可读）');
      expect(r['template_id'], 'seed_snack');
      expect(r['cost'], 30);

      final Map<String, Object?> p =
          (await database.customSelect("SELECT * FROM plants WHERE id = 'p1';")
              .getSingle())
          .data;
      expect(p['species_id'], 'sunflower');
      expect(p['stage'], 0);

      final Map<String, Object?> l = (await database
              .customSelect("SELECT * FROM sunlight_ledgers WHERE id = 'l1';")
              .getSingle())
          .data;
      expect(l['ref_type'], 'task_checkin');
      expect(l['balance_after'], 12.0);
    });

    test('④ ageTier 经 SettingsLocalRepository 端到端读回正确', () async {
      final db.AppDatabase database = await _openV25();
      addTearDown(database.close);
      final SettingsLocalRepository repo = SettingsLocalRepository(database);

      final s = await repo.getSettings();
      expect(s.ageTier, AgeTier.high, reason: '历史行 age_tier=2 → high');
      expect(s.gardenPotCapacity, 6);
      expect(s.eyeCareSkipAllowed, isFalse);
    });

    test('⑤ 幂等：二次访问不报错、children 仍为空、无重复建表', () async {
      final db.AppDatabase database = await _openV25();
      addTearDown(database.close);

      await database.customSelect('SELECT COUNT(*) FROM settings;').getSingle();
      expect(await _tableCount(database, 'child_profiles'), 0);
      // 二次访问（模拟重启后重开）。
      await database
          .customSelect('SELECT COUNT(*) FROM child_profiles;')
          .getSingle();
      expect(await _tableCount(database, 'child_profiles'), 0);
      expect(await _tableCount(database, 'settings'), 1);
    });

    test('⑥ 新装库（v26 直建）children 表存在且为空，可正常写入档案', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      expect(database.schemaVersion, 27);
      expect(await _tableExists(database, 'child_profiles'), isTrue);
      expect(await _tableCount(database, 'child_profiles'), 0);

      // 写一条档案再读回（列形态 / 默认值验证）。
      await database.childProfileDao.upsert(
        db.ChildProfilesCompanion.insert(
          id: 'c1',
          name: '小向日葵',
          ageTier: const Value(1),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            1729000000 * 1000,
          ),
        ),
      );
      final db.ChildProfileRow? row = await database.childProfileDao.byId('c1');
      expect(row, isNotNull);
      expect(row!.name, '小向日葵');
      expect(row.ageTier, 1);
    });
  });
}
