/// 迁移回归测试 v16 → v17（**晨露奖励历史重复行清理**，B35，真机实证 2026-10-08）。
///
/// 背景：`PlantGrowthService._enqueueBloomRewards` 旧版对「同株 + 同一 8 点槽位」
/// 不去重——调试催熟 N 次开花 → 同一槽位重复登记 N 条未领取行；8 点一到期，
/// 头顶一次性堆 N 个产物图标（玄参真机实证：33 次催熟 → 99 条未领取）。
/// 领域层已加槽位指纹去重护栏（B35）；本迁移一次性清理**存量**重复行：
/// 每个 `(plant_id, due_at, reward_kind)` 槽位的未领取行只保留一条（MIN(id)）。
///
/// 本测试钉死六件事（**必须把行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 17`；
///  ② 同槽位未领取重复行塌缩为 1 条（金额取保留行，不许合并求和）；
///  ③ claimed 行是已发放历史账，**一条不动**（同槽位的 claimed 行保留）；
///  ④ 不同槽位 / 不同 kind 的正常行一条不丢；
///  ⑤ plants / sunlight_ledgers 等其它表原样保留；
///  ⑥ 幂等：v17 库二次打开不报错、行数稳定不变。
library migration_v16_to_v17_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// v16 线上 schema（与 v15 相同 + plants.shovel_refund 列）。
List<String> _v16Ddl() => <String>[
      'CREATE TABLE settings ('
          'id INTEGER NOT NULL, age_tier INTEGER NOT NULL, '
          'night_boundary_hour INTEGER NOT NULL DEFAULT 21, '
          'night_boundary_minute INTEGER NOT NULL DEFAULT 0, '
          'daily_focus_cap INTEGER NOT NULL, daily_app_cap_minutes INTEGER NOT NULL, '
          'rest_after_sessions INTEGER NOT NULL, rest_minutes INTEGER NOT NULL, '
          'task_sunlight INTEGER NOT NULL, monthly_pool_budget INTEGER NOT NULL, '
          'quiet_mode INTEGER NOT NULL DEFAULT 0, sound_on INTEGER NOT NULL DEFAULT 1, '
          'bgm_on INTEGER NOT NULL DEFAULT 1, detection_on INTEGER NOT NULL DEFAULT 1, '
          'auto_confirm_single_high INTEGER NOT NULL DEFAULT 130, '
          'auto_confirm_single_low INTEGER NOT NULL DEFAULT 50, '
          'auto_confirm_monthly_pct REAL NOT NULL DEFAULT 0.25, '
          'currency_rate REAL NOT NULL DEFAULT 0.25, theme_dark INTEGER NOT NULL DEFAULT 0, '
          'autonomous_mode INTEGER NOT NULL DEFAULT 0, '
          'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, '
          'eye_care_enabled INTEGER NOT NULL DEFAULT 1, '
          'eye_care_interval_min INTEGER NOT NULL DEFAULT 20, '
          'eye_care_skip_allowed INTEGER NOT NULL DEFAULT 1, '
          'shovel_refund INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
      'CREATE TABLE plants ('
          'id TEXT NOT NULL, species_id TEXT NOT NULL, pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, stage_started_at INTEGER NOT NULL, '
          'growth_progress REAL NOT NULL DEFAULT 0.0, growth_factor REAL NOT NULL DEFAULT 1.0, '
          'water_used INTEGER NOT NULL DEFAULT 0, fertilizer_used INTEGER NOT NULL DEFAULT 0, '
          'status INTEGER NOT NULL, planted_at INTEGER NOT NULL, '
          'last_water_at INTEGER, wilted_at INTEGER, dead_at INTEGER, bloomed_at INTEGER, '
          'bloom_count INTEGER NOT NULL DEFAULT 0, mood INTEGER NOT NULL DEFAULT 0, '
          'weed_at INTEGER, pest_at INTEGER, weed_pest_roll_day INTEGER, '
          'shovel_refund INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
      'CREATE TABLE premium_fragments ('
          'id INTEGER NOT NULL, balance INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));',
      'CREATE TABLE pending_bloom_rewards ('
          'id TEXT NOT NULL, plant_id TEXT NOT NULL, due_at INTEGER NOT NULL, '
          'reward_kind TEXT NOT NULL, claimed INTEGER NOT NULL DEFAULT 0, '
          'reward_sunlight INTEGER NOT NULL DEFAULT 0, '
          'reward_fragments INTEGER NOT NULL DEFAULT 0, '
          'reward_species_id TEXT, PRIMARY KEY (id));',
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
    ];

/// 2026-10-08 08:00（晨露槽位；unix 秒，与真机实证一致）。
final int _slot08 = _secs(DateTime(2026, 10, 8, 8));
final int _slot09 = _secs(DateTime(2026, 10, 9, 8));
final int _slotBloom = _secs(DateTime(2026, 10, 7, 20));

/// 历史脏数据：模拟「催熟 3 次开花 → 同一槽位登记 3 条未领取 + 1 条已领取历史账」。
/// ⚠️ 逐条 execute（sqlite3 单次 execute 不允许多语句）。
List<String> _pendingInsertSqls() => <String>[
      // p1：同一槽位 3 条未领取（调试催熟 3 次留下的重复）——迁移后只留 1 条。
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight) "
          "VALUES ('dup-1', 'p1', $_slot08, 'normal', 0, 4);",
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight) "
          "VALUES ('dup-2', 'p1', $_slot08, 'normal', 0, 12);",
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight) "
          "VALUES ('dup-3', 'p1', $_slot08, 'normal', 0, 18);",
      // p1：同槽位的 claimed 行（已发放历史账）——必须保留。
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight) "
          "VALUES ('done-1', 'p1', $_slot08, 'instant', 1, 6);",
      // p2：不同槽位各 1 条（正常晨露节奏）——一条不丢。
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight) "
          "VALUES ('ok-1', 'p2', $_slot08, 'normal', 0, 5);",
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_fragments) "
          "VALUES ('ok-2', 'p2', $_slot09, 'normal', 0, 1);",
      // p2：instant 行（不同 kind）——一条不丢。
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight) "
          "VALUES ('ok-3', 'p2', $_slotBloom, 'instant', 0, 6);",
      // 账本一行（迁移不许碰账本）。
      "INSERT INTO sunlight_ledgers (id, ts, type, gross, net, balance_after, ref_type, day_key) "
          "VALUES ('led-1', $_slot08, 1, 4.0, 4.0, 4.0, 'bloom_reward_24h', '2026-10-08');",
    ];

/// 手工构造「老库（v16）」并让 AppDatabase 触发迁移（内存库）。
Future<db.AppDatabase> _openMigrated(int userVersion) async {
  final NativeDatabase executor = NativeDatabase.memory(
    setup: (rawDb) {
      for (final String sql in _v16Ddl()) {
        rawDb.execute(sql);
      }
      for (final String sql in _pendingInsertSqls()) {
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

/// 未领取行 id 集合（按 id 升序）。
Future<List<String>> _unclaimedIds(db.AppDatabase database) async {
  final List<QueryRow> rows = await database.customSelect(
    'SELECT id FROM pending_bloom_rewards WHERE claimed = 0 ORDER BY id;',
  ).get();
  return rows.map((QueryRow r) => r.read<String>('id')).toList();
}

Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row =
      await database.customSelect('SELECT COUNT(*) AS c FROM $table;').getSingle();
  return row.read<int>('c');
}

void main() {
  group('迁移 v16->v17：晨露奖励历史重复行清理（B35）', () {
    test('schemaVersion 必须为最新 17（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(16);
      expect(database.schemaVersion, 18);
    });

    test('同槽位未领取重复行塌缩为 1 条（保留行金额原样，不合并求和）', () async {
      final db.AppDatabase database = await _openMigrated(16);
      final List<String> ids = await _unclaimedIds(database);
      final List<String> p1Ids =
          ids.where((String id) => ids.contains(id)).toList();
      expect(p1Ids, isNotEmpty);
      // p1 的 3 条重复塌缩为 1 条。
      final QueryRow row = await database.customSelect(
        "SELECT COUNT(*) AS c FROM pending_bloom_rewards "
        "WHERE plant_id = 'p1' AND claimed = 0;",
      ).getSingle();
      expect(row.read<int>('c'), 1, reason: '同槽位 3 条未领取 → 只留 1 条');
      // 保留的是 MIN(id) = 'dup-1'，金额 4 原样（不许把 4+12+18 合并成 34）。
      final QueryRow kept = await database.customSelect(
        "SELECT reward_sunlight FROM pending_bloom_rewards "
        "WHERE plant_id = 'p1' AND claimed = 0;",
      ).getSingle();
      expect(kept.read<int>('reward_sunlight'), 4,
          reason: '照单发放口径：保留行金额原样，绝不合并求和（否则凭空多给阳光）');
    });

    test('claimed 行一条不动（已发放历史账保留）', () async {
      final db.AppDatabase database = await _openMigrated(16);
      final QueryRow row = await database.customSelect(
        "SELECT COUNT(*) AS c FROM pending_bloom_rewards "
        "WHERE plant_id = 'p1' AND claimed = 1;",
      ).getSingle();
      expect(row.read<int>('c'), 1, reason: 'done-1 是已发放历史账，清理绝不碰');
    });

    test('不同槽位 / 不同 kind 的正常行一条不丢', () async {
      final db.AppDatabase database = await _openMigrated(16);
      final List<String> ids = await _unclaimedIds(database);
      // p2 的 3 条（两个 8 点槽位 + 1 条 instant）全部保留。
      final QueryRow p2 = await database.customSelect(
        "SELECT COUNT(*) AS c FROM pending_bloom_rewards "
        "WHERE plant_id = 'p2' AND claimed = 0;",
      ).getSingle();
      expect(p2.read<int>('c'), 3);
      expect(ids.length, 4, reason: 'p1 塌缩后 1 条 + p2 共 3 条 = 4 条未领取');
    });

    test('账本等其它表原样保留', () async {
      final db.AppDatabase database = await _openMigrated(16);
      expect(await _count(database, 'sunlight_ledgers'), 1);
      expect(await _count(database, 'pending_bloom_rewards'), 5,
          reason: '4 条未领取 + 1 条 claimed');
    });

    test('幂等：已迁移到 v17 的库二次打开不报错、行数稳定不变', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v17');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v16Ddl()) {
              rawDb.execute(sql);
            }
            for (final String sql in _pendingInsertSqls()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 16;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 18);
      final List<String> idsAfterFirst = await _unclaimedIds(first);
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 18);
      final List<String> idsAfterSecond = await _unclaimedIds(second);
      expect(idsAfterSecond, idsAfterFirst, reason: '二次打开行集合稳定不变');
    });
  });
}
