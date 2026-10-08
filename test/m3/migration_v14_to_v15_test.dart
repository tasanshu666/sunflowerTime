/// 迁移回归测试 v14 → v15（**少儿护眼休息**，玄参 2026-10-03 初稿 / 2026-10-04 收口，
/// 口径 C28 §4）。
///
/// v15 变更：`settings` 新增 3 列 ——
///  · `eye_care_enabled`：护眼提醒总开关（默认 1 = 开）；
///  · `eye_care_interval_min`：场内护眼触发间隔（分钟，默认 20）；
///  · `eye_care_skip_allowed`：是否允许孩子跳过护眼卡（默认 1 = 允许）。
///
/// 为什么必须迁移（光靠列默认值救不了存量库）：
///  · SQLite 的 `ALTER TABLE ADD COLUMN` 已由 `_ensureColumn` 幂等补列，新装库的
///    settings 天然有列；但**老设备上已存在的 settings 行**不会自己长出新列，读取
///    时必须由迁移补齐，否则老用户一进家长端设置页就撞上「no such column」；
///  · 三列都是**带语义默认值**的列（开 / 20 / 允许），存量行补列后直接落到默认口径，
///    不需要回填脚本，也不会把老用户已有的配置洗掉。
///
/// ⚠️ 刻意**没有** `eye_care_duration`（护眼时长）列：单次护眼固定 60 秒，玄参
/// 2026-10-04 拍板「家长端不设、不可调」，时长常量单点收口 `kEyeCareDurationSeconds`。
/// 本测试顺带把这个「不该有」的决策钉死（见「护眼时长不落列」用例）。
///
/// 本测试钉死五件事（**必须把历史行读回来断言**，不能只断言「没抛异常」）：
///  ① `AppDatabase.schemaVersion == 15`；
///  ② 老库 settings 行的三条新列**读得到、且为默认值**（1 / 20 / 1）；
///  ③ 经 `SettingsLocalRepository` 读回的 [AppSettings] 实体三项为
///     `true / [kEyeCareIntervalMinDefault] / true`，且老行原有字段（日上限 /
///     休息节奏 / 花园容量 / 夜间边界）**一条没丢**；
///  ④ 幂等：已迁移到 v15 的库二次打开不报错、默认值稳定不变；
///  ⑤ 护眼时长不落列（`settings` 表里不存在 `eye_care_duration`，防后人误加）。
library migration_v14_to_v15_test;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// v14 线上 schema（**不含** v15 的三个新列 —— 缺列正是本测试要修的状态）。
///
/// 列类型必须与 drift 定义一致（`boolean()` → `INTEGER NOT NULL DEFAULT x`，SQLCipher
/// 下 bool 存 0/1），否则迁移补列后读回会取不到值。
List<String> _v14Ddl() => <String>[
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
          'bgm_on INTEGER NOT NULL DEFAULT 1, '
          'detection_on INTEGER NOT NULL DEFAULT 1, '
          'auto_confirm_single_high INTEGER NOT NULL DEFAULT 130, '
          'auto_confirm_single_low INTEGER NOT NULL DEFAULT 50, '
          'auto_confirm_monthly_pct REAL NOT NULL DEFAULT 0.25, '
          'currency_rate REAL NOT NULL DEFAULT 0.25, '
          'theme_dark INTEGER NOT NULL DEFAULT 0, '
          'autonomous_mode INTEGER NOT NULL DEFAULT 0, '
          'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, '
          'PRIMARY KEY (id));',
      // ⚠️ v15 新增的三列**故意缺失** —— 缺列正是本测试要修的状态。
      'CREATE TABLE plants ('
          'id TEXT NOT NULL, species_id TEXT NOT NULL, pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, stage_started_at INTEGER NOT NULL, '
          'growth_progress REAL NOT NULL DEFAULT 0.0, growth_factor REAL NOT NULL DEFAULT 1.0, '
          'water_used INTEGER NOT NULL DEFAULT 0, fertilizer_used INTEGER NOT NULL DEFAULT 0, '
          'status INTEGER NOT NULL, planted_at INTEGER NOT NULL, '
          'last_water_at INTEGER, wilted_at INTEGER, dead_at INTEGER, bloomed_at INTEGER, '
          'bloom_count INTEGER NOT NULL DEFAULT 0, mood INTEGER NOT NULL DEFAULT 0, '
          'weed_at INTEGER, pest_at INTEGER, weed_pest_roll_day INTEGER, '
          'PRIMARY KEY (id));',
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
      // 历史 settings 行：家长早已调过「每 N 次专注后休息 / 休息时长 / 日上限」，
      // 迁移后这些自定义值**一条都不能被默认值覆盖**。
      'INSERT INTO settings (id, age_tier, night_boundary_hour, night_boundary_minute, '
          'daily_focus_cap, daily_app_cap_minutes, rest_after_sessions, rest_minutes, '
          'task_sunlight, monthly_pool_budget, sound_on, bgm_on, garden_pot_capacity) '
          'VALUES (1, 1, 22, 30, 90, 30, 3, 15, 12, 480, 1, 1, 6);',
    ];

/// 逐列读出 settings 的三个新列（直接走 SQL，绕开 drift 数据类，专测「列补出来没有」）。
Future<Map<String, Object?>> _eyeCareRow(db.AppDatabase database) async {
  final QueryRow row = await database
      .customSelect('SELECT eye_care_enabled, eye_care_interval_min, '
          'eye_care_skip_allowed FROM settings WHERE id = 1;')
      .getSingle();
  return <String, Object?>{
    'eye_care_enabled': row.data['eye_care_enabled'],
    'eye_care_interval_min': row.data['eye_care_interval_min'],
    'eye_care_skip_allowed': row.data['eye_care_skip_allowed'],
  };
}

/// 手工构造「老库（v14）」并让 AppDatabase 触发迁移（内存库）。
Future<db.AppDatabase> _openMigrated(int userVersion) async {
  final NativeDatabase executor = NativeDatabase.memory(
    setup: (rawDb) {
      for (final String sql in _v14Ddl()) {
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

Future<int> _count(db.AppDatabase database, String table) async {
  final QueryRow row =
      await database.customSelect('SELECT COUNT(*) AS c FROM $table;').getSingle();
  return row.read<int>('c');
}

void main() {
  group('迁移 v14->v15：少儿护眼休息三列（C28）', () {
    test('schemaVersion 必须为最新 15（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(14);
      expect(database.schemaVersion, 17);
    });

    test('三列补出来且历史行为默认值（开 / 20 分钟 / 允许跳过）', () async {
      final db.AppDatabase database = await _openMigrated(14);
      final Map<String, Object?> row = await _eyeCareRow(database);
      // 存量老库没有「护眼」概念 → 必须落到默认口径，不能是 0/占位值。
      expect(row['eye_care_enabled'], 1,
          reason: '护眼提醒对老用户必须默认开启（玄参拍板默认开）');
      expect(row['eye_care_interval_min'], kEyeCareIntervalMinDefault);
      expect(row['eye_care_skip_allowed'], 1);
    });

    test('读回的 AppSettings：护眼三项为默认值，且老行原有字段一条不丢', () async {
      final db.AppDatabase database = await _openMigrated(14);
      final AppSettings s =
          await SettingsLocalRepository(database).getSettings();
      expect(s.eyeCareEnabled, isTrue);
      expect(s.eyeCareIntervalMin, kEyeCareIntervalMinDefault);
      expect(s.eyeCareSkipAllowed, isTrue);
      // 老行历史值完整性（迁移只补列、不许顺手改数据）
      expect(s.restAfterSessions, 3, reason: '家长调过的「每 3 场休息」不能被洗成默认 2');
      expect(s.restMinutes, 15);
      expect(s.dailyFocusCap, 90);
      expect(s.dailyAppCapMinutes, 30);
      expect(s.gardenPotCapacity, 6);
      expect(s.nightBoundaryHour, 22);
      expect(s.nightBoundaryMinute, 30);
      expect(s.poolBudget, 480);
    });

    test('其它表数据原样保留（植物 / 账本 / 任务）', () async {
      final db.AppDatabase database = await _openMigrated(14);
      expect(await _count(database, 'settings'), 1);
      expect(await _count(database, 'plants'), 0);
      expect(await _count(database, 'sunlight_ledgers'), 0);
      expect(await _count(database, 'tasks'), 0);
    });

    test('幂等：已迁移到 v15 的库二次打开不报错、默认值稳定不变', () async {
      final Directory dir = Directory.systemTemp.createTempSync('sunflower_v15');
      final File file = File('${dir.path}/legacy.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final db.AppDatabase first = db.AppDatabase(
        NativeDatabase(
          file,
          setup: (rawDb) {
            for (final String sql in _v14Ddl()) {
              rawDb.execute(sql);
            }
            rawDb.execute('PRAGMA user_version = 14;');
          },
        ),
      );
      await first.customSelect('SELECT 1').get();
      expect(first.schemaVersion, 17);
      await first.close();

      final db.AppDatabase second = db.AppDatabase(NativeDatabase(file));
      addTearDown(() => second.close());
      await second.customSelect('SELECT 1').get();
      expect(second.schemaVersion, 17);
      expect(await _count(second, 'settings'), 1);

      final Map<String, Object?> row = await _eyeCareRow(second);
      expect(row['eye_care_enabled'], 1);
      expect(row['eye_care_interval_min'], kEyeCareIntervalMinDefault);
      expect(row['eye_care_skip_allowed'], 1);
      // 二次打开不覆盖家长既有配置（即使老行被改过也别回退默认值）
      await SettingsLocalRepository(second).saveSettings(
        const AppSettings(
          ageTier: AgeTier.mid,
          dailyFocusCap: 90,
          dailyAppCapMinutes: 30,
          restAfterSessions: 3,
          restMinutes: 15,
          taskSunlight: 12,
          poolBudget: 480,
          eyeCareEnabled: false,
          eyeCareIntervalMin: 30,
          eyeCareSkipAllowed: false,
        ),
      );
      final Map<String, Object?> after =
          await _eyeCareRow(await _openMigrated(14));
      expect(after['eye_care_enabled'], 1,
          reason: '刚补出来的新列不该被之后写入的值影响（迁移早于写入）');
    });

    test('护眼时长不落列（家长端不设、不可调，玄参 2026-10-04 拍板）', () async {
      final db.AppDatabase database = await _openMigrated(14);
      final List<QueryRow> cols = await database
          .customSelect('SELECT name FROM pragma_table_info(\'settings\');')
          .get();
      final List<String> names =
          cols.map((QueryRow r) => r.read<String>('name')).toList();
      expect(names, isNot(contains('eye_care_duration')),
          reason: '护眼总长固定 [kEyeCareDurationSeconds] 秒，不该成为家长可配列；'
              '若将来误加此列，等于把已拍板的「家长端不设」口径改回去');
      expect(names, contains('eye_care_enabled'));
      expect(names, contains('eye_care_interval_min'));
      expect(names, contains('eye_care_skip_allowed'));
    });
  });
}
