/// 迁移回归测试 v18 → v19（**旧「48h 第二段」遗留行清理**，F104，玄参 2026-10-09 实证）。
///
/// 背景（模拟器库实锤）：调试催熟 23 次开花（旧口径代码期）各登记一条
/// 「48h 第二段」行（due = 开花时刻 + 48h，时间点非整点），全部未领取；
/// F78「同轮」判定（`dueAt >= bloomedAt`）把到期时间晚于最后一次开花的
/// 遗留行误判为本轮可收集 → 头顶聚合出 **+165 阳光 / ×2 碎片** 的横财。
///
/// 新口径（2026-10-07 每日 8 点修订）晨露行恒为**本地 08:00:00 整**，与遗留行
/// （非整点）可精确区分。v19 迁移：删除未领取且 due_at 非 08:00:00 整的
/// normal/premium 行（**直接删除、不发放**——调试横财不应入账）。
///
/// 本测试钉死六件事：
///  ① `AppDatabase.schemaVersion == 19`；
///  ② 遗留 48h 行（非 08:00 整）升级后被删除；
///  ③ 新口径晨露行（08:00:00 整）原样保留；
///  ④ instant 行（due=开花时刻，正常口径）不受影响；
///  ⑤ claimed 行（历史账）一律不动；
///  ⑥ 幂等：v19 库二次打开不报错、行集合稳定不变。
library migration_v18_to_v19_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// v18 schema（v18 仅新增 eye_care_logs 表，其余 DDL 与 v17 一致）。
List<String> _v18Ddl() => <String>[
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
      'CREATE TABLE eye_care_logs ('
          'id TEXT NOT NULL, ts INTEGER NOT NULL, day_key TEXT NOT NULL, '
          'result TEXT NOT NULL, watched_seconds INTEGER NOT NULL, '
          'source TEXT NOT NULL, PRIMARY KEY (id));',
    ];

/// 基准时刻：2026-10-07 12:14:22（最后一次调试催熟，玄参库实锤值）。
final DateTime _lastBloom = DateTime(2026, 10, 7, 12, 14, 22);

/// 种子数据：模拟玄参模拟器库的四种行形态。
List<String> _seedSqls() => <String>[
      "INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, "
          "rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget) "
          "VALUES (1, 2, 60, 30, 2, 10, 12, 400);",
      "INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, status, planted_at, bloomed_at, bloom_count) "
          "VALUES ('p1', 'species_sunflower', 0, 2, ${_secs(_lastBloom)}, 1, ${_secs(_lastBloom)}, ${_secs(_lastBloom)}, 23);",
      // ① 遗留 48h 行 ×2（未领取、时间点非整点）→ 必须删除。
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight, reward_fragments) "
          "VALUES ('legacy-1', 'p1', ${_secs(_lastBloom.add(const Duration(days: 2)))}, 'normal', 0, 13, 0);",
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight, reward_fragments) "
          "VALUES ('legacy-2', 'p1', ${_secs(_lastBloom.add(const Duration(days: 3, hours: 1)))}, 'normal', 0, 5, 0);",
      // ② 新口径晨露行（08:00:00 整、未领取）→ 必须保留。
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight, reward_fragments) "
          "VALUES ('morning-1', 'p1', ${_secs(DateTime(2026, 10, 8, 8))}, 'normal', 0, 6, 0);",
      // ③ instant 行（due=开花时刻，正常口径）→ 不受影响。
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight, reward_fragments) "
          "VALUES ('instant-1', 'p1', ${_secs(_lastBloom)}, 'instant', 0, 6, 0);",
      // ④ 遗留 48h 行但**已领取**（历史账）→ 一律不动。
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight, reward_fragments) "
          "VALUES ('legacy-claimed', 'p1', ${_secs(_lastBloom.add(const Duration(days: 4)))}, 'normal', 1, 6, 0);",
      // ⑤ 遗留 48h 行挂在 **growing** 植物上（非盛开、无误判问题）→ 不删。
      "INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, status, planted_at) "
          "VALUES ('p2', 'species_tomato', 1, 2, ${_secs(_lastBloom)}, 0, ${_secs(_lastBloom)});",
      "INSERT INTO pending_bloom_rewards (id, plant_id, due_at, reward_kind, claimed, reward_sunlight, reward_fragments) "
          "VALUES ('legacy-growing', 'p2', ${_secs(_lastBloom.add(const Duration(days: 2)))}, 'normal', 0, 6, 0);",
    ];

Future<db.AppDatabase> _openV18() async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        for (final String sql in _v18Ddl()) {
          rawDb.execute(sql);
        }
        for (final String sql in _seedSqls()) {
          rawDb.execute(sql);
        }
        rawDb.execute('PRAGMA user_version = 18;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get(); // 触发迁移
  return database;
}

void main() {
  group('迁移 v18->v19：旧 48h 第二段遗留行清理（F104）', () {
    test('schemaVersion 必须为最新 21（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV18();
      addTearDown(database.close);
      expect(database.schemaVersion, 24);
    });

    test('遗留 48h 行（非 08:00 整、未领取）升级后被删除', () async {
      final db.AppDatabase database = await _openV18();
      addTearDown(database.close);
      final List<QueryRow> rows = await database.customSelect(
        "SELECT id FROM pending_bloom_rewards WHERE id IN ('legacy-1', 'legacy-2');",
      ).get();
      expect(rows, isEmpty, reason: '调试横财不发放、直接清理');
    });

    test('新口径晨露行（08:00 整）与 instant 行原样保留', () async {
      final db.AppDatabase database = await _openV18();
      addTearDown(database.close);
      final List<QueryRow> rows = await database.customSelect(
        "SELECT id FROM pending_bloom_rewards WHERE claimed = 0 ORDER BY id;",
      ).get();
      expect(rows.map((QueryRow r) => r.read<String>('id')).toList(),
          <String>['instant-1', 'legacy-growing', 'morning-1'],
          reason: '新口径行与 growing 植物遗留行均不受迁移影响');
    });

    test('claimed 行（历史账）一律不动', () async {
      final db.AppDatabase database = await _openV18();
      addTearDown(database.close);
      final QueryRow row = await database.customSelect(
        "SELECT COUNT(*) AS c FROM pending_bloom_rewards WHERE id = 'legacy-claimed';",
      ).getSingle();
      expect(row.read<int>('c'), 1, reason: '已发放历史账只读，不清理');
    });

    test('非盛开（growing）植物的遗留行不删（无误判问题，保留 F78 自动结算语义）', () async {
      final db.AppDatabase database = await _openV18();
      addTearDown(database.close);
      final QueryRow row = await database.customSelect(
        "SELECT COUNT(*) AS c FROM pending_bloom_rewards WHERE id = 'legacy-growing';",
      ).getSingle();
      expect(row.read<int>('c'), 1, reason: '只清盛开植物上被误判为本轮的遗留行');
    });

    test('幂等：v19 库二次打开行集合稳定不变', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v19');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v18Ddl()) {
              rawDb.execute(sql);
            }
            for (final String sql in _seedSqls()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 18;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      final List<String> idsAfterFirst = (await first.customSelect(
        'SELECT id FROM pending_bloom_rewards ORDER BY id;',
      ).get())
          .map((QueryRow r) => r.read<String>('id'))
          .toList();
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 24);
      final List<String> idsAfterSecond = (await second.customSelect(
        'SELECT id FROM pending_bloom_rewards ORDER BY id;',
      ).get())
          .map((QueryRow r) => r.read<String>('id'))
          .toList();
      expect(idsAfterSecond, idsAfterFirst, reason: '二次打开行集合稳定不变');
    });
  });
}
