/// 迁移回归测试 v11 → v12（**奖励物图标化 + 掉落即定奖**，玄参 2026-09-27）。
///
/// v12 变更：`pending_bloom_rewards` 新增 3 列 `reward_sunlight` / `reward_fragments` /
/// `reward_species_id`（登记 pending 时就把奖励内容 roll 好落库，结算照单发放，UI 据此渲染
/// 头顶奖励图标）。均为带默认值的 `ALTER TABLE ADD COLUMN`；历史行取**零值哨兵** `0/0/null`
/// （= 未预先定奖），结算时退回「现场 roll」并回写本行，保证老 pending 奖励不丢。
///
/// 本测试钉死六件事（**必须把历史行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 15`；
///  ② v11 → v12 后 `pending_bloom_rewards` **新增 3 列**（PRAGMA table_info 可见）；
///  ③ 历史 pending 行**原样保留**，三列读回为**零值哨兵** `0/0/null`；
///  ④ 历史 pending 行**可正常结算**（现场 roll 发放 + 回写该行）；
///  ⑤ 其它表数据（settings / 碎片余额 / 已解锁物种 / 植物）原样保留；
///  ⑥ 幂等：已迁移到 v12 的库二次打开不报错、不丢数据、版本号稳定。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**，
///    故「老库」DDL 的日期列一律用 `INTEGER`（秒）。
library migration_v11_to_v12_test;

import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

final DateTime _legacyStageStarted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyPlanted = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyDue = DateTime(2026, 8, 22, 10, 0);

/// v11 线上 schema：与 v10 同构（v11 只删 daisy/cactus 行，不动 schema）。
/// `pending_bloom_rewards` **尚无** `reward_sunlight / reward_fragments / reward_species_id` 三列。
List<String> _v11Ddl({bool withLegacyPending = true}) {
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
    // ⚠️ 关键：v11 的 pending_bloom_rewards **没有** v12 的 3 个奖励内容列。
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
    // settings 单行（验证「其它表数据原样保留」）。
    'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
        'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget, '
        'garden_pot_capacity) VALUES (1, ${AgeTier.low.index}, 90, 30, 2, 10, 12, 160, 12);',
    'INSERT INTO premium_fragments (id, balance) VALUES (1, 7);',
    'INSERT INTO unlocked_species (species_id) VALUES (\'species_star_flower\');',
    // 历史 pending 行（v11 无奖励内容列；迁移后应读回零值哨兵 0/0/null）。
    if (withLegacyPending)
      'INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed) '
          'VALUES (\'pr_legacy\', \'p_sunflower\', ${_secs(_legacyDue)}, \'normal\', 0);',
    // 植物（验证不误伤）。
    'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
        'growth_progress, growth_factor, water_used, fertilizer_used, status, '
        'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
        'VALUES (\'p_sunflower\', \'species_sunflower\', 0, '
        '${PlantStage.adult.index}, ${_secs(_legacyStageStarted)}, 0.6, 1.0, '
        '1, 1, ${PlantStatus.growing.index}, ${_secs(_legacyPlanted)}, '
        '${_secs(_legacyPlanted)}, NULL, NULL, NULL, 0, 0);',
  ];
}

/// 某表当前行数。
Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row =
      await database.customSelect('SELECT COUNT(*) AS c FROM $table;').getSingle();
  return row.read<int>('c');
}

/// 某表当前是否含某列（PRAGMA table_info）。
Future<bool> _hasColumn(db.AppDatabase database, String table, String col) async {
  final List<QueryRow> info =
      await database.customSelect('PRAGMA table_info($table);').get();
  return info.any((QueryRow r) => r.read<String>('name') == col);
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

/// 无专注会话替身。
class _NoFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      const <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

/// 可编排随机源（确定性）。
class _SeqRandom implements Random {
  _SeqRandom({this.doubles = const <double>[], this.ints = const <int>[]});
  final List<double> doubles;
  final List<int> ints;
  int _di = 0;
  int _ii = 0;
  @override
  double nextDouble() => doubles[_di++ % doubles.length];
  @override
  int nextInt(int max) => ints[_ii++ % ints.length] % max;
  @override
  bool nextBool() => false;
}

void main() {
  group('迁移 v11->v12：pending_bloom_rewards 新增 3 列（掉落即定奖）', () {
    test('schemaVersion 必须为最新 14（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database =
          await _openMigrated(_v11Ddl(), 11);
      expect(database.schemaVersion, 16);
    });

    test('新增 3 列（reward_sunlight / reward_fragments / reward_species_id）可见', () async {
      final db.AppDatabase database = await _openMigrated(_v11Ddl(), 11);
      expect(
          await _hasColumn(database, 'pending_bloom_rewards', 'reward_sunlight'),
          isTrue);
      expect(
          await _hasColumn(
              database, 'pending_bloom_rewards', 'reward_fragments'),
          isTrue);
      expect(
          await _hasColumn(
              database, 'pending_bloom_rewards', 'reward_species_id'),
          isTrue);
    });

    test('历史 pending 行保留且读回为零值哨兵 0/0/null', () async {
      final db.AppDatabase database = await _openMigrated(_v11Ddl(), 11);
      expect(await _count(database, 'pending_bloom_rewards'), 1,
          reason: '历史行不得被迁移删除');
      final List<db.PendingBloomRewardRow> due =
          await database.bloomRewardDao.pendingDue(DateTime(2030));
      expect(due, hasLength(1));
      expect(due.first.id, 'pr_legacy');
      expect(due.first.rewardKind, 'normal');
      expect(due.first.rewardSunlight, 0, reason: '零值哨兵');
      expect(due.first.rewardFragments, 0, reason: '零值哨兵');
      expect(due.first.rewardSpeciesId, isNull, reason: '零值哨兵');
    });

    test('历史 pending 行可正常结算（现场 roll 发放 + 回写该行）', () async {
      final db.AppDatabase database = await _openMigrated(_v11Ddl(), 11);
      final PlantLocalRepository plants = PlantLocalRepository(database);
      final SunlightLocalRepository ledger = SunlightLocalRepository(database);
      final SettingsLocalRepository settings = SettingsLocalRepository(database);
      final PlantGrowthService svc = PlantGrowthService(
        plants: plants,
        focus: _NoFocusRepo(),
        ledger: ledger,
        settings: settings,
        bloomRewards: plants,
        // r=0.21 → 第二段大额阳光 10–20（nextInt=0 → 10）。
        random: _SeqRandom(doubles: <double>[0.21], ints: <int>[0]),
      );

      await svc.collectBloomReward('pr_legacy', DateTime(2026, 9, 30));
      final List<SunlightEntry> earns = (await ledger.all())
          .where((SunlightEntry e) => e.refType == kBloomSecondPhaseRefType)
          .toList();
      expect(earns, hasLength(1), reason: '历史行结算应正常发放一笔');
      expect(earns.first.net, kBloomBonusSunlightMin + 0);

      // 回写：该行已非哨兵（奖励内容落库）。
      final db.PendingBloomRewardRow row =
          await database.bloomRewardDao.byId('pr_legacy');
      expect(row.rewardSunlight, kBloomBonusSunlightMin + 0,
          reason: '哨兵行结算后应回写奖励内容');
      expect(row.claimed, isTrue, reason: '已结算 → claimed');
    });

    test('其它表数据原样保留（settings / 碎片 / 已解锁 / 植物）', () async {
      final db.AppDatabase database = await _openMigrated(_v11Ddl(), 11);
      expect(await _count(database, 'settings'), 1);
      expect(await database.bloomRewardDao.fragmentBalance(), 7);
      expect(await database.bloomRewardDao.unlockedSpeciesIds(),
          <String>['species_star_flower']);
      expect(await _count(database, 'plants'), 1);
      expect((await database.plantDao.byId('p_sunflower'))!.speciesId,
          'species_sunflower');
    });

    test('无历史 pending 行时迁移不报错、不新增行', () async {
      final db.AppDatabase database =
          await _openMigrated(_v11Ddl(withLegacyPending: false), 11);
      expect(await _count(database, 'pending_bloom_rewards'), 0);
    });
  });

  group('幂等 / 版本守卫：已迁移到 v12 的库重复打开', () {
    test('二次打开不报错、数据不丢、版本稳定 12；且 updatePendingContent 生效', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v12');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      // 首次打开：v11 → v12。
      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v11Ddl()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 11;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 16);
      // 回写一行内容（证明新列可写）。
      await first.bloomRewardDao.updatePendingContent(
        id: 'pr_legacy',
        rewardSunlight: 9,
        rewardFragments: 2,
        rewardSpeciesId: null,
      );
      await first.close();

      // 二次打开（from==12）：迁移不应再跑、不丢数据。
      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 16);
      expect(await _count(second, 'pending_bloom_rewards'), 1,
          reason: '二次打开不得丢数据');
      final db.PendingBloomRewardRow row =
          await second.bloomRewardDao.byId('pr_legacy');
      expect(row.rewardSunlight, 9, reason: '新列内容不得丢失');
      expect(row.rewardFragments, 2);
      expect(await second.bloomRewardDao.fragmentBalance(), 7,
          reason: '碎片余额不应丢失');
    });
  });
}
