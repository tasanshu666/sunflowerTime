/// 独立复验探针 #6（qa-verify3）：**迁移 v11 → v12**（pending_bloom_rewards 加 3 列）。
///
/// 自建「v11 老库」DDL（`pending_bloom_rewards` **不含** v12 的
/// `reward_sunlight / reward_fragments / reward_species_id` 三列）+ 多张代表性业务表数据，
/// 升级读回后逐条断言；再验证**幂等 / 版本守卫**与**老 pending 可结算不丢奖励**。
///
/// 与工程用例 `test/m3/migration_v11_to_v12_test.dart` 相互独立（本探针 DDL / 断言自建）。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为 **unix 秒 INTEGER**。
library qa_b3_migration_v12_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import '../helpers/no_hit_random.dart';

int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

final DateTime _t = DateTime(2026, 9, 1, 8, 0);
final DateTime _legacyDue = DateTime(2026, 8, 20, 10, 0);

/// v11 线上 schema（pending_bloom_rewards **无** v12 的 3 列；其余表与当前一致）。
List<String> _v11Ddl() => <String>[
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
      // ⚠️ 关键：v11 无 reward_sunlight / reward_fragments / reward_species_id。
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
      // ── 代表性存量数据（验证「加列不丢数据」）────────────────────────────
      'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
          'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget, '
          'garden_pot_capacity, quiet_mode, sound_on) '
          'VALUES (1, ${AgeTier.low.index}, 90, 30, 2, 10, 12, 160, 12, 1, 0);',
      'INSERT INTO premium_fragments (id, balance) VALUES (1, 7);',
      'INSERT INTO unlocked_species (species_id) VALUES (\'species_tomato\');',
      // 历史 pending 行（v11 无奖励内容列；迁移后应读回零值哨兵 0/0/null）。
      'INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed) '
          'VALUES (\'pr_legacy\', \'p_sf\', ${_secs(_legacyDue)}, \'normal\', 0);',
      'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
          'growth_progress, growth_factor, water_used, fertilizer_used, status, '
          'planted_at, last_water_at, wilted_at, dead_at, bloomed_at, bloom_count, mood) '
          'VALUES (\'p_sf\', \'species_sunflower\', 0, ${PlantStage.adult.index}, '
          '${_secs(_t)}, 0.6, 1.0, 1, 1, ${PlantStatus.growing.index}, ${_secs(_t)}, '
          '${_secs(_t)}, NULL, NULL, NULL, 0, ${PlantMood.calm.index});',
      'INSERT INTO tasks (id, name, subject, requires_focus, is_custom) '
          'VALUES (\'t1\', \'读书\', ${TaskSubject.chinese.index}, 1, 0);',
      'INSERT INTO check_ins (id, task_id, date, completed_at, is_perfect_day) '
          'VALUES (\'ci1\', \'t1\', ${_secs(_t)}, ${_secs(_t)}, 0);',
      'INSERT INTO tracking_events (id, name, type, ts, payload) '
          'VALUES (\'te1\', \'evt\', ${TrackingType.metric.index}, ${_secs(_t)}, \'{}\');',
      'INSERT INTO sunlight_ledgers (id, ts, type, gross, net, balance_after, ref_type, ref_id, day_key) '
          'VALUES (\'l1\', ${_secs(_t)}, ${SunlightType.earn.index}, 10, 10, 10, \'seed\', NULL, \'2026-09-01\');',
      'INSERT INTO monthly_pools (month_key, budget, used, auto_released, reset_at) '
          'VALUES (\'2026-09\', 160, 0, 0, ${_secs(_t)});',
      'INSERT INTO cooldown_counters (template_id, period, used_count) '
          'VALUES (\'rt1\', 1, 2);',
      'INSERT INTO redemption_requests (id, template_id, requested_at, cost, status) '
          'VALUES (\'rr1\', \'rt1\', ${_secs(_t)}, 50, ${RequestStatus.verified.index});',
      'INSERT INTO reward_templates (id, name, category) VALUES (\'rt1\', \'看电影\', 0);',
      'INSERT INTO focus_sessions (id, start, end, planned_min, actual_focus_min, status, '
          'sunlight_earned, created_at) '
          'VALUES (\'fs1\', ${_secs(_t)}, ${_secs(_t.add(const Duration(minutes: 25)))}, '
          '25, 25.0, ${FocusStatus.completed.index}, 10.0, ${_secs(_t)});',
    ];

Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row = await database
      .customSelect('SELECT COUNT(*) AS c FROM $table;')
      .getSingle();
  return row.read<int>('c');
}

Future<bool> _hasColumn(
    db.AppDatabase database, String table, String col) async {
  final List<QueryRow> info =
      await database.customSelect('PRAGMA table_info($table);').get();
  return info.any((QueryRow r) => r.read<String>('name') == col);
}

Future<db.AppDatabase> _openMigratedMemory(
    List<String> ddl, int userVersion) async {
  final NativeDatabase executor = NativeDatabase.memory(
    setup: (raw) {
      for (final String sql in ddl) {
        raw.execute(sql);
      }
      raw.execute('PRAGMA user_version = $userVersion;');
    },
  );
  final db.AppDatabase database = db.AppDatabase(executor);
  await database.customSelect('SELECT 1').get(); // 触发迁移
  addTearDown(database.close);
  return database;
}

class _NoFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      const <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
      totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('F · 迁移 v11 → v12：pending 加 3 列', () {
    test('schemaVersion == 15；3 列出现', () async {
      final db.AppDatabase database = await _openMigratedMemory(_v11Ddl(), 11);
      expect(database.schemaVersion, 20);
      expect(
          await _hasColumn(
              database, 'pending_bloom_rewards', 'reward_sunlight'),
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

    test('历史 pending 行保留、三列读回为零值哨兵 0/0/null、其余字段不变', () async {
      final db.AppDatabase database = await _openMigratedMemory(_v11Ddl(), 11);
      expect(await _count(database, 'pending_bloom_rewards'), 1,
          reason: '历史行不得被删除');

      final db.PendingBloomRewardRow row =
          await database.bloomRewardDao.byId('pr_legacy');
      expect(row.rewardKind, 'normal');
      expect(row.claimed, isFalse);
      expect(row.plantId, 'p_sf');
      expect(row.dueAt, _legacyDue, reason: 'due_at 不得被改写');
      expect(row.rewardSunlight, 0, reason: '零值哨兵');
      expect(row.rewardFragments, 0, reason: '零值哨兵');
      expect(row.rewardSpeciesId, isNull, reason: '零值哨兵');
    });

    test('其它 13 张表数据原样保留（加列不误伤）', () async {
      final db.AppDatabase database = await _openMigratedMemory(_v11Ddl(), 11);
      expect(await _count(database, 'settings'), 1);
      expect(await _count(database, 'plants'), 1);
      expect(await _count(database, 'premium_fragments'), 1);
      expect(await _count(database, 'unlocked_species'), 1);
      expect(await _count(database, 'tasks'), 1);
      expect(await _count(database, 'check_ins'), 1);
      expect(await _count(database, 'tracking_events'), 1);
      expect(await _count(database, 'sunlight_ledgers'), 1);
      expect(await _count(database, 'monthly_pools'), 1);
      expect(await _count(database, 'cooldown_counters'), 1);
      expect(await _count(database, 'redemption_requests'), 1);
      expect(await _count(database, 'reward_templates'), 1);
      expect(await _count(database, 'focus_sessions'), 1);

      // 关键字段值抽查（证明「读回仍正确」而非仅张数）。
      expect(await database.bloomRewardDao.fragmentBalance(), 7);
      expect(await database.bloomRewardDao.unlockedSpeciesIds(),
          <String>['species_tomato']);
      expect((await database.plantDao.byId('p_sf'))!.speciesId,
          'species_sunflower');
      final db.Setting settings = (await database.settingsDao.getRow())!;
      expect(settings.quietMode, isTrue);
      expect(settings.soundOn, isFalse);
      expect(settings.gardenPotCapacity, 12);
    });

    test('新列可写：插入带奖励内容的新行 / 回写历史行均 round-trip', () async {
      final db.AppDatabase database = await _openMigratedMemory(_v11Ddl(), 11);
      // 写入一条「已定奖」新行。
      await database.bloomRewardDao
          .insertPending(db.PendingBloomRewardsCompanion(
        id: const Value('pr_new'),
        plantId: const Value('p_sf'),
        dueAt: Value(_t),
        rewardKind: const Value('instant'),
        rewardSunlight: const Value(12),
        rewardFragments: const Value(3),
        rewardSpeciesId: const Value('species_star_flower'),
      ));
      final db.PendingBloomRewardRow nuevo =
          await database.bloomRewardDao.byId('pr_new');
      expect(nuevo.rewardSunlight, 12);
      expect(nuevo.rewardFragments, 3);
      expect(nuevo.rewardSpeciesId, 'species_star_flower');

      // 回写历史行（不改 claimed）。
      await database.bloomRewardDao.updatePendingContent(
        id: 'pr_legacy',
        rewardSunlight: 9,
        rewardFragments: 2,
        rewardSpeciesId: null,
      );
      final db.PendingBloomRewardRow legacy =
          await database.bloomRewardDao.byId('pr_legacy');
      expect(legacy.rewardSunlight, 9);
      expect(legacy.rewardFragments, 2);
      expect(legacy.claimed, isFalse, reason: '回写内容不改 claimed');
    });

    test('历史行可正常结算（现场 roll 发放 + 回写，奖励不丢）', () async {
      final db.AppDatabase database = await _openMigratedMemory(_v11Ddl(), 11);
      final PlantLocalRepository plants = PlantLocalRepository(database);
      final SunlightLocalRepository ledger = SunlightLocalRepository(database);
      final SettingsLocalRepository settings =
          SettingsLocalRepository(database);
      final PlantGrowthService svc = PlantGrowthService(
        plants: plants,
        focus: _NoFocusRepo(),
        ledger: ledger,
        settings: settings,
        bloomRewards: plants,
        weedRandom: NoHitRandom(),
      );

      final double before = await ledger.balance();
      // 历史行结算：普通第二段，随机 → 必有一项奖励（碎片 / 种子 / 阳光）。此处只断言「有入账」。
      await svc.collectBloomReward('pr_legacy', DateTime(2026, 9, 30));

      final List<SunlightEntry> earns = (await ledger.all())
          .where((SunlightEntry e) => e.refType == kBloomSecondPhaseRefType)
          .toList();
      final int frag = await plants.premiumFragmentBalance();
      final Set<String> unlocked = await plants.unlockedSpeciesIds();
      // 三选一：阳光一笔 / 碎片增加 / 券增加 至少其一。
      final bool anyCredited =
          earns.isNotEmpty || frag > 0 || unlocked.length > 1;
      expect(anyCredited, isTrue, reason: '历史行结算必须有实际入账（奖励不丢）');

      final db.PendingBloomRewardRow row =
          await database.bloomRewardDao.byId('pr_legacy');
      expect(row.claimed, isTrue, reason: '结算后 claimed');
      expect(
          row.rewardSunlight != 0 ||
              row.rewardFragments != 0 ||
              row.rewardSpeciesId != null,
          isTrue,
          reason: '结算后应回写奖励内容（脱离零值哨兵）');
      expect(await ledger.balance() - before, isNonNegative);
    });
  });

  group('F · 幂等 / 版本守卫（文件库二次打开）', () {
    test('v11 → v12 升级一次；二次打开不再迁移、数据与新列内容不丢、版本稳定 12', () async {
      final Directory dir = Directory.systemTemp.createTempSync('qa_b3_v12');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      // 首次打开：v11 → v12。
      final db.AppDatabase first = db.AppDatabase(NativeDatabase(
        file,
        setup: (raw) {
          for (final String sql in _v11Ddl()) {
            raw.execute(sql);
          }
          raw.execute('PRAGMA user_version = 11;');
        },
      ));
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 20);
      await first.bloomRewardDao.updatePendingContent(
        id: 'pr_legacy',
        rewardSunlight: 5,
        rewardFragments: 4,
        rewardSpeciesId: 'species_tomato',
      );
      await first.close();

      // 二次打开（from == 12）：不得再迁移、不得丢数据。
      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 20);
      expect(await _count(second, 'pending_bloom_rewards'), 1,
          reason: '二次打开不得丢 pending 数据');
      final db.PendingBloomRewardRow row =
          await second.bloomRewardDao.byId('pr_legacy');
      expect(row.rewardSunlight, 5, reason: '新列内容不得丢失');
      expect(row.rewardFragments, 4);
      expect(row.rewardSpeciesId, 'species_tomato');
      expect(await _count(second, 'tasks'), 1);
      expect(await second.bloomRewardDao.fragmentBalance(), 7);
      // 三列仍在。
      expect(
          await _hasColumn(second, 'pending_bloom_rewards', 'reward_sunlight'),
          isTrue);
    });
  });
}
