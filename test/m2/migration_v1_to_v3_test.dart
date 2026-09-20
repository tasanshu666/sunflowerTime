/// 迁移回归测试（§5 验收证据）：手工构造「老库」再让 AppDatabase 迁移。
///
/// 背景：玄参大人真机库由 M1（schemaVersion=1）升级而来，v1→v2 迁移补列不完整，
/// 导致 reward_templates 表缺 cooldown_rule、redemption_requests 缺 child_id，
/// 且残留 v1 遗留的 base_cost_high / base_cost_low 两列（NOT NULL 无默认值，
/// 会让 INSERT 触发 "NOT NULL constraint failed"）。reward_seed 被 unawaited 静默
/// 吞掉异常，于是 reward_templates 始终为空 → 阳光商店纯黑页。
///
/// 场景 A：v1 老库（含遗留 base_cost_high/base_cost_low，缺 base_cost/cooldown_rule/
///   child_id/name）→ 最新 schema(3)。
/// 场景 B：已被 v2 破坏的库（跑了半截 v2 迁移：有 base_cost、有 tracking_events.name，
///   但仍缺 cooldown_rule 且残留 base_cost_high/base_cost_low）→ 修复到 schema(3)。
///
/// 用 `flutter test` 跑（沙箱内纯 dart test 因 sqlcipher_flutter_libs 引入
/// package:flutter，standalone dart VM 无 dart:ui 无法编译；故走 flutter test）。
library migration_v1_to_v3_test;

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_seed.dart';
import 'package:test/test.dart';

/// v1「老库」完整建表 DDL。
///
/// 只改与 M2 相关的 4 张表（reward_templates / redemption_requests /
/// tracking_events / settings 语义），其余表与当前 schema 一致。
/// - reward_templates(v1)：含 base_cost_high INTEGER NOT NULL、base_cost_low
///   INTEGER NOT NULL，**无** base_cost、**无** cooldown_rule；
/// - redemption_requests(v1)：**无** child_id；
/// - tracking_events(v1)：**无** name。
List<String> _v1SchemaDdl() {
  return <String>[
    // settings（v1 与当前一致）
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
        'PRIMARY KEY (id));',
    // focus_sessions（与当前一致）
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
    // sunlight_ledgers（与当前一致）
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
    // reward_templates（v1：含遗留 base_cost_high/base_cost_low，缺 base_cost/cooldown_rule）
    'CREATE TABLE reward_templates ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'category INTEGER NOT NULL, '
        'base_cost_high INTEGER NOT NULL, '
        'base_cost_low INTEGER NOT NULL, '
        'freq_limit INTEGER, '
        'enabled INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id));',
    // redemption_requests（v1：缺 child_id）
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
        'PRIMARY KEY (id));',
    // monthly_pools（与当前一致）
    'CREATE TABLE monthly_pools ('
        'month_key TEXT NOT NULL, '
        'budget INTEGER NOT NULL, '
        'used INTEGER NOT NULL DEFAULT 0, '
        'auto_released INTEGER NOT NULL DEFAULT 0, '
        'reset_at TEXT NOT NULL, '
        'PRIMARY KEY (month_key));',
    // tasks（与当前一致）
    'CREATE TABLE tasks ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'subject INTEGER NOT NULL, '
        'requires_focus INTEGER NOT NULL, '
        'min_focus_min INTEGER NOT NULL DEFAULT 15, '
        'sunlight_reward INTEGER NOT NULL DEFAULT 12, '
        'repeat_rule TEXT, '
        'is_custom INTEGER NOT NULL, '
        'PRIMARY KEY (id));',
    // check_ins（与当前一致）
    'CREATE TABLE check_ins ('
        'id TEXT NOT NULL, '
        'task_id TEXT NOT NULL, '
        'date TEXT NOT NULL, '
        'completed_at TEXT NOT NULL, '
        'session_id TEXT, '
        'is_perfect_day INTEGER NOT NULL, '
        'PRIMARY KEY (id));',
    // cooldown_counters（与当前一致）
    'CREATE TABLE cooldown_counters ('
        'template_id TEXT NOT NULL, '
        'period INTEGER NOT NULL, '
        'used_count INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (template_id, period));',
    // tracking_events（v1：缺 name）
    'CREATE TABLE tracking_events ('
        'id TEXT NOT NULL, '
        'type INTEGER NOT NULL, '
        'ts TEXT NOT NULL, '
        'payload TEXT NOT NULL, '
        'PRIMARY KEY (id));',
  ];
}

/// 读取某表当前所有列名（PRAGMA table_info）。
Future<Set<String>> _columns(db.AppDatabase database, String table) async {
  final List<QueryRow> rows =
      await database.customSelect('PRAGMA table_info($table);').get();
  return rows.map((QueryRow r) => r.read<String>('name')).toSet();
}

/// 手工构造「老库」并触发迁移。
///
/// 在 [NativeDatabase.memory] 的 setup 回调里把 [legacyDdl] 跑完（在连接打开后、
/// drift 读取 user_version 之前），再写 PRAGMA user_version=[userVersion]，从而
/// 让 AppDatabase 打开时按 from=userVersion 跑 onUpgrade 修复到 schema(3)。
Future<db.AppDatabase> _openMigrated(List<String> legacyDdl, int userVersion) async {
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
  group('迁移 v1->v3：reward_templates 列修复（场景 A）', () {
    test('v1 老库迁移后列正确、INSERT 成功、播种 5 条', () async {
      final db.AppDatabase database = await _openMigrated(_v1SchemaDdl(), 1);

      // ① 列补齐断言：reward_templates 含 base_cost / cooldown_rule，
      //    且不再含 base_cost_high / base_cost_low。
      final Set<String> rtCols =
          await _columns(database, 'reward_templates');
      expect(rtCols, contains('base_cost'));
      expect(rtCols, contains('cooldown_rule'));
      expect(rtCols, isNot(contains('base_cost_high')));
      expect(rtCols, isNot(contains('base_cost_low')));

      // ② redemption_requests 补齐 child_id。
      final Set<String> rrCols =
          await _columns(database, 'redemption_requests');
      expect(rrCols, contains('child_id'));

      // ③ tracking_events 补齐 name。
      final Set<String> teCols =
          await _columns(database, 'tracking_events');
      expect(teCols, contains('name'));

      // ④ ensureRewardSeed 先跑（此时表为空才会播种），跑完 all() 返回 5 条。
      //    这一步是端到端验收：修复前因迁移失败，reward_templates 始终为空、
      //    ensureRewardSeed 被 unawaited 静默吞掉异常，旭日商店纯黑页。
      final RewardLocalRepository repo = RewardLocalRepository(database);
      await ensureRewardSeed(repo);
      final List<db.RewardTemplate> all =
          await database.rewardTemplateDao.all();
      expect(all, hasLength(5));
      expect(
        all.map((db.RewardTemplate t) => t.id).toSet(),
        <String>{
          'seed_snack',
          'seed_cartoon_tonight',
          'seed_extra_10min',
          'seed_weekend_outing',
          'seed_extra_episode',
        },
      );

      // ⑤ 真正的验收点（旧代码在这步必炸）：RewardTemplateDao.upsert 能成功插入。
      await database.rewardTemplateDao.upsert(
        db.RewardTemplatesCompanion(
          id: const Value('tpl_probe'),
          name: const Value('探针模板'),
          category: const Value(1), // RewardCategory.parentHandled
          baseCost: const Value(35),
          freqLimit: const Value(1),
          cooldownRule: const Value(1), // CooldownRule.weekly
        ),
      );
      final List<db.RewardTemplate> allWithProbe =
          await database.rewardTemplateDao.all();
      expect(allWithProbe, hasLength(6));
      final db.RewardTemplate probe = allWithProbe.firstWhere(
        (db.RewardTemplate t) => t.id == 'tpl_probe',
      );
      expect(probe.baseCost, 35);
      expect(probe.cooldownRule, 1);
    });
  });

  group('迁移 v2->v3：修复被 v2 破坏的库（场景 B，复现玄参大人真机状态）', () {
    test('v2 半截迁移库迁移后列正确、INSERT 成功、播种 5 条', () async {
      // 模拟跑过「半截」v2 迁移：补上 base_cost 与 tracking_events.name，
      // 但仍缺 cooldown_rule、且残留 base_cost_high/base_cost_low。
      final List<String> legacy = <String>[
        ..._v1SchemaDdl(),
        'ALTER TABLE reward_templates '
            'ADD COLUMN base_cost INTEGER NOT NULL DEFAULT 50;',
        'ALTER TABLE tracking_events '
            'ADD COLUMN name TEXT NOT NULL DEFAULT \'\';',
      ];

      final db.AppDatabase database = await _openMigrated(legacy, 2);

      // ① 列修复断言（与场景 A 一致）。
      final Set<String> rtCols =
          await _columns(database, 'reward_templates');
      expect(rtCols, contains('base_cost'));
      expect(rtCols, contains('cooldown_rule'));
      expect(rtCols, isNot(contains('base_cost_high')));
      expect(rtCols, isNot(contains('base_cost_low')));

      final Set<String> rrCols =
          await _columns(database, 'redemption_requests');
      expect(rrCols, contains('child_id'));

      final Set<String> teCols =
          await _columns(database, 'tracking_events');
      expect(teCols, contains('name'));

      // ② ensureRewardSeed 先跑（表为空才会播种），跑完 all() 返回 5 条。
      final RewardLocalRepository repo = RewardLocalRepository(database);
      await ensureRewardSeed(repo);
      expect(await database.rewardTemplateDao.all(), hasLength(5));

      // ③ INSERT 成功（旧代码必炸）。
      await database.rewardTemplateDao.upsert(
        db.RewardTemplatesCompanion(
          id: const Value('tpl_probe'),
          name: const Value('探针模板'),
          category: const Value(1),
          baseCost: const Value(35),
          freqLimit: const Value(1),
          cooldownRule: const Value(1),
        ),
      );
      expect(await database.rewardTemplateDao.all(), hasLength(6));
    });
  });
}
