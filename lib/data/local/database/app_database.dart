/// Drift + SQLCipher 数据库入口（§3 / §10.4 C13 加密存储义务）。
///
/// opener 用 SQLCipher 打开本地库并设密钥（PRAGMA key）。MVP 口令来自
/// `app_constants.kDatabasePassphrase`（骨架阶段固定；生产应改为设备级密钥派生
/// + flutter_secure_storage 保管，见 T03 风险项）。
library app_database;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

import 'daos.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Settings,
    Plants,
    PremiumFragments,
    PendingBloomRewards,
    UnlockedSpecies,
    FocusSessions,
    SunlightLedgers,
    RewardTemplates,
    RedemptionRequests,
    MonthlyPools,
    Tasks,
    CheckIns,
    CooldownCounters,
    TrackingEvents,
    EyeCareLogs,
  ],
  daos: [
    SettingsDao,
    PlantDao,
    BloomRewardDao,
    TaskDao,
    SunlightLedgerDao,
    RewardTemplateDao,
    RedemptionRequestDao,
    MonthlyPoolDao,
    CooldownCounterDao,
    TrackingEventDao,
    EyeCareLogDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openEncryptedDb());

  @override
  int get schemaVersion => 24;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (Migrator m, int from, int to) async {
          // ① 幂等补齐所有表（CREATE TABLE IF NOT EXISTS，防御性对齐）。
          //    玄参大人真机库由 v1 升级而来，可能停留在 v2（缺列），此处先把
          //    所有表对齐到当前 schema，避免后续 addColumn/alterTable 因缺表报错。
          await m.createAll();

          // ② 幂等补齐 M2 期间新增的列（老库可能因历史迁移遗漏而缺列）。
          //    玄参大人现网库已是 v2，只有 from < 3 的新分支才会真正执行修复，
          //    光改 from < 2 分支救不了现网库。
          await _ensureColumn(m, rewardTemplates, rewardTemplates.baseCost);
          await _ensureColumn(m, rewardTemplates, rewardTemplates.cooldownRule);
          await _ensureColumn(
              m, redemptionRequests, redemptionRequests.childId);
          await _ensureColumn(m, trackingEvents, trackingEvents.name);
          // ④ M3 新增：garden_pot_capacity 列（老库从 v3 升级时可能缺此列）。
          await _ensureColumn(
              m, settings, settings.gardenPotCapacity);
          // ⑤ M3 修订（v5）：tasks.custom_subject 列（自定义科目名）。
          //    可空 TEXT，老库经 ALTER TABLE ADD COLUMN 补列，历史行取 NULL。
          await _ensureColumn(m, tasks, tasks.customSubject);

          // ⑨ M5（v9）：tasks.category 列（成长项内容分类）+ reward_templates.content_category 列
          //    （奖励内容分类）。均为 IntColumn 带默认值 0（=other）的 ALTER TABLE ADD COLUMN，
          //    历史行取默认值 0 → 读作「其他」，避免历史数据被误判成具体分类。
          //    幂等：_ensureColumn 先查 PRAGMA table_info 再决定是否补列。
          await _ensureColumn(m, tasks, tasks.category);
          await _ensureColumn(m, rewardTemplates, rewardTemplates.contentCategory);

          // ⑥ M4（v6）：check_ins 新增 5 列（家长核销流水）。
          //    status 默认 0 = verified（见 CheckInStatus 注释）：v5 及以前的打卡
          //    本就是「打卡即入账」，升级后必须保持「已核销」，不得变成待核销。
          await _ensureColumn(m, checkIns, checkIns.status);
          await _ensureColumn(m, checkIns, checkIns.sunlightGross);
          await _ensureColumn(m, checkIns, checkIns.sunlightGranted);
          await _ensureColumn(m, checkIns, checkIns.resolvedAt);
          await _ensureColumn(m, checkIns, checkIns.parentNote);

          // ③ 清除 v1 遗留的 base_cost_high / base_cost_low 两列：
          //    它们在 Dart 侧已删除、drift 不再写入，但老库物理列仍是
          //    INTEGER NOT NULL 无默认值，会导致 INSERT 触发
          //    "NOT NULL constraint failed"。用 drift 的表重建（12 步法）对齐当前
          //    schema，移除多余物理列。
          if (await _hasColumn(rewardTemplates.actualTableName, 'base_cost_high') ||
              await _hasColumn(
                  rewardTemplates.actualTableName, 'base_cost_low')) {
            await m.alterTable(TableMigration(rewardTemplates));
          }

          // ④ v1 的 age_tier=1 表示旧语义 high，重编号为新语义 high(2)。
          //    必须保持 from < 2 守卫：v2 库中 age_tier=1 已是新语义 mid，绝不能再改。
          if (from < 2) {
            await customStatement(
              'UPDATE settings SET age_tier = 2 WHERE age_tier = 1;',
            );
          }

          // ⑦ 植物成长 V2（v7）：成长进度算法改为幂等 + 成长数值重规划
          //    （每阶段 240h/480h、浇水 +1%、施肥 +5%）。旧进度是按 24h/阶段、
          //    ⚠️ 上面是 **v7 当时的口径**；施肥增量已于 2026-09-25 调为 **+3%**
          //    （`kPlantFertilizeProgressGain`），只改常量、不涉及本迁移。
          //    且非幂等累加出来的，**无法与新口径对齐**（真机上已表现为进度虚高）。
          //    玄参大人 2026-09-22 在「平滑衔接 / 老植物沿用旧参数 / 全部重置清零」
          //    三选项中明确选 **全部重置清零**。
          //
          //    仅重置 status = growing 的植物：已开花 bloomed / 枯萎中 wilting /
          //    已死亡 dead 的植物保持原样，不被清零。
          //
          //    ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为
          //       **unix 秒 INTEGER**；SQL 里必须写**秒**，写毫秒会算出 1970 年
          //       或让增量少算 1000 倍。
          if (from < 7) {
            final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            await customStatement(
              'UPDATE plants SET stage = ${PlantStage.seed.index}, '
              'growth_progress = 0.0, stage_started_at = $nowSec '
              'WHERE status = ${PlantStatus.growing.index};',
            );
          }

          // ⑧ v8（M3 修订，玄参大人 2026-09-23 拍板「花谢循环」玩法）：plants 新增
          //    bloomed_at 列（进入盛开的计时起点，可空）。老库 ALTER TABLE ADD COLUMN
          //    补列，历史行取 NULL（表示「尚未记录花期起点」，首次 tick 自动补计时）。
          await _ensureColumn(m, plants, plants.bloomedAt);

          // ⑩ v10（成株后循环玩法 Batch 1）：plants 新增 bloom_count 列（累计盛开次数，
          //    INT NOT NULL DEFAULT 0）+ 3 张新表（premium_fragments 精品碎片余额、
          //    pending_bloom_rewards 第二段待收集奖励、unlocked_species 已解锁物种）。
          //    · 新表由顶部 createAll()（CREATE TABLE IF NOT EXISTS）自动建出；
          //    · bloom_count 用 _ensureColumn 幂等补列，历史行取默认 0
          //      （= 从未开过花 → 复开花节奏判据安全默认为「首花」）。
          await _ensureColumn(m, plants, plants.bloomCount);

          //    回填：已盛开过的存量植物（有花期起点 bloomed_at）至少算「开过 1 次花」，
          //    否则升级后被当成首花、复开花速率退回首花速率（普通重满约 5 天而非 ~14 天）。
          //    幂等：① 该 UPDATE 只在 from<10 的 onUpgrade 中执行（版本号到 10 后不再跑）；
          //    ② 条件带 `bloom_count = 0`，且为**赋值**而非自增，重复执行也不会叠加。
          //    ⚠️ 本仓未开 `storeDateTimesAsText`，DateTime 落库为 unix 秒 INTEGER；
          //       此处按 `bloomed_at IS NOT NULL` 判「曾盛开」，与列的实际存储无关。
          await customStatement(
            'UPDATE plants SET bloom_count = 1 '
            'WHERE bloomed_at IS NOT NULL AND bloom_count = 0;',
          );

          // ⑪ v11（物种表改版，玄参 2026-09-27 拍板）：移除 `species_daisy`（小雏菊）/
          //    `species_cactus`（仙人掌）两个旧物种，其**存量植株直接删除**（不做迁移映射）。
          //    幂等：① 只在 from<11 时执行（版本号到 11 后不再跑）；② 条件为按 species_id 删除，
          //    重复执行时第二次已无匹配行 → 无副作用、不误删其它物种。
          //    ⚠️ 这是**版本变更**（schemaVersion 10 → 11），必须配迁移测试（见
          //       `test/m3/migration_v10_to_v11_test.dart`）。
          if (from < 11) {
            await customStatement(
              "DELETE FROM plants WHERE species_id IN "
              "('species_daisy','species_cactus')",
            );
          }

          // ⑫ v12（奖励物图标化 + 掉落即定奖，玄参 2026-09-27 拍板）：pending_bloom_rewards 新增
          //    3 列——`reward_sunlight` / `reward_fragments` / `reward_species_id`，用于在「登记
          //    pending」时就把奖励内容 roll 好落库（结算照单发放），UI 据此渲染头顶奖励图标。
          //    · 用 _ensureColumn 幂等补列，历史行取默认零值哨兵 `0/0/null`（= 未预先定奖）；
          //      结算时命中哨兵者退回「现场 roll」路径并回写本行，保证老 pending 奖励不丢。
          //    · 均为带默认值的 ALTER TABLE ADD COLUMN（nullable 的 reward_species_id 默认 NULL）。
          //    ⚠️ 版本变更（11 → 12），必须配迁移测试（见 `test/m3/migration_v11_to_v12_test.dart`）。
          await _ensureColumn(m, pendingBloomRewards, pendingBloomRewards.rewardSunlight);
          await _ensureColumn(m, pendingBloomRewards, pendingBloomRewards.rewardFragments);
          await _ensureColumn(m, pendingBloomRewards, pendingBloomRewards.rewardSpeciesId);

          // ⑬ v13（花园氛围音默认开启，玄参 2026-09-29 拍板）：把存量 settings 行的
          //    `bgm_on` 翻为 1。
          //    背景：此前 `bgm_on` 默认 0，且**代码从未把设置接到音频服务**（`applySettings`
          //    无调用点）→ 花园 BGM 从来不会响。玄参拍板「默认开启」后，仅改列默认值
          //    救不了**已存在的行**（老设备仍是 0），故用一次迁移显式翻值。
          //    幂等：① 只在 from<13 时执行；② 为**赋值**而非自增，重复执行无副作用。
          //    ⚠️ 版本变更（12 → 13），必须配迁移测试（见
          //       `test/m3/migration_v12_to_v13_test.dart`）。
          if (from < 13) {
            await customStatement('UPDATE settings SET bgm_on = 1;');
          }

          // ⑭ v14（花园干扰物「杂草 / 害虫」，玄参 2026-09-30 拍板，口径 C26）：plants 新增
          //    3 列——`weed_at` / `pest_at` / `weed_pest_roll_day`。
          //    · 三者都是 nullable 且无语义默认值（null = 无杂草 / 无害虫 / 尚未 roll），
          //      存量行取 NULL 即可，不需要回填脚本；
          //    · `_ensureColumn` 幂等补列，保证重复升级不报错。
          //    ⚠️ 版本变更（13 → 14），必须配迁移测试（见
          //       `test/m3/migration_v13_to_v14_test.dart`）。
          await _ensureColumn(m, plants, plants.weedAt);
          await _ensureColumn(m, plants, plants.pestAt);
          await _ensureColumn(m, plants, plants.weedPestRollDay);

          // ⑮ v15（少儿护眼休息，玄参 2026-10-03 初稿 / 2026-10-04 收口，口径 C28）：
          //     settings 新增 3 列 —— `eye_care_enabled` / `eye_care_interval_min` /
          //     `eye_care_skip_allowed`，承载家长端 C28 §4 的三项配置（总开关 / 触发
          //     间隔（分钟）/ 是否允许孩子跳过）。
          //     · 三者都是**带语义默认值**的列（开 / 20 / 允许），存量 settings 行经
          //       `ALTER TABLE ADD COLUMN` 补列后直接落到默认口径，不需要回填脚本；
          //     · 用 `_ensureColumn` 幂等补列，重复升级不报错、也不覆盖家长既有配置；
          //     · ⚠️ 护眼**时长**（固定 60 秒，两段各 30 秒）**刻意不落列** —— 玄参
          //       2026-10-04 拍板「家长端不设、不可调」，时长常量收口
          //       `kEyeCareDurationSeconds`，别在这里另开一列。
          //     ⚠️ 版本变更（14 → 15），必须配迁移测试（见
          //        `test/m3/migration_v14_to_v15_test.dart`）。
          await _ensureColumn(m, settings, settings.eyeCareEnabled);
          await _ensureColumn(m, settings, settings.eyeCareIntervalMin);
          await _ensureColumn(m, settings, settings.eyeCareSkipAllowed);

          // ⑯ v16（铲除返还，玄参 2026-10-05 拍板，口径 C29）：plants 新增
          //    `shovel_refund` 列 —— 种下时即定好的「铲除返还阳光数」。
          //    · INT NOT NULL DEFAULT 0：历史行（v16 前种下）与向日葵免费首株均为 0
          //      = 铲除不返还（防「免费种 → 铲 → 循环刷阳光」的经济漏洞）；
          //    · 普通档付费/种子券种下 = 150（300×50%）、精英档 = 250（500×50%），
          //      由领域层 `PlantGrowthService._chargeForPlanting` 在种下时计算落列；
          //    · 用 `_ensureColumn` 幂等补列，重复升级不报错。
          //    ⚠️ 版本变更（15 → 16），必须配迁移测试（见
          //       `test/m3/migration_v15_to_v16_test.dart`）。
          await _ensureColumn(m, plants, plants.shovelRefund);

          // ⑰ v17（晨露奖励历史重复行清理，B35，真机实证 2026-10-08）：
          //    `_enqueueBloomRewards` 旧版对「同株 + 同一 8 点槽位」不去重——调试催熟
          //    N 次开花 → 同一槽位重复登记 N 条未领取行，8 点一到期头顶一次性堆 N 个
          //    产物图标。领域层已加槽位指纹去重护栏（B35），本迁移一次性清理**存量**
          //    重复行：每个 (plant_id, due_at, reward_kind) 槽位的未领取行只保留一条
          //    （MIN(id)），其余删除。claimed 行是已发放的历史账（含调试期已收集的），
          //    **一律不动**；阳光账本同样是只读事实，不动。
          //    · 幂等：DELETE 按「非本组 MIN(id) 的未领取行」判定，重复执行第二次
          //      已无匹配行 → 无副作用（v17+ 库根本不再进入本分支）。
          //    ⚠️ 版本变更（16 → 17），必须配迁移测试（见
          //       `test/m3/migration_v16_to_v17_test.dart`）。
          if (from < 17) {
            await customStatement(
              'DELETE FROM pending_bloom_rewards '
              'WHERE claimed = 0 AND id NOT IN ('
              '  SELECT MIN(id) FROM pending_bloom_rewards'
              '  WHERE claimed = 0'
              '  GROUP BY plant_id, due_at, reward_kind'
              ');',
            );
          }

          // ⑱ v18（护眼记录表，玄参 2026-10-09 拍板）：新增 `eye_care_logs` 表 ——
          //    每次护眼卡退出落一行（完成 / 跳过都记），承载家长报告的护眼统计：
          //    跳过次数（账本从无跳过记录）与实际观看时长；完成次数的权威口径仍在
          //    阳光账本 `refType='eye_care_break'`（孩子端「我的」也走账本，历史全量）。
          //    · 全新表、无历史数据迁移：`m.createTable` 幂等（v18+ 库不再进入本分支，
          //      首次建库走 onCreate 同样建表）；
          //    ⚠️ 版本变更（17 → 18），必须配迁移测试（见
          //       `test/m3/migration_v17_to_v18_test.dart`）。
          if (from < 18) {
            await m.createTable(eyeCareLogs);
          }

          // ⑲ v19（旧「48h 第二段」遗留行清理，F104，玄参 2026-10-09 实证）：
          //    模拟器库实锤——向日葵头顶聚合出 **+165 阳光 / ×2 碎片**。根因两层：
          //    ① 调试催熟 23 次开花（10/5~10/7，旧口径代码期）各登记一条
          //      「48h 第二段」行（due = 开花时刻 + 48h，时间点为 21:36/22:32 等
          //      非整点），全部未领取；② F78「同轮」判定只看 `dueAt >= bloomedAt`，
          //      这些行的到期时间恰好都晚于最后一次开花 → 被误判为本轮可收集，
          //      头顶图标聚合出一笔 165 的横财。
          //    新口径（2026-10-07 每日 8 点修订）晨露行恒为**本地 08:00:00 整**，
          //    与遗留行（非整点）可精确区分：本迁移删除「**盛开中植物的**未领取
          //    normal/premium 行且 due_at 时间非 08:00:00」——即恰好是被 F78 误判
          //    为本轮可收集、正堆在头顶图标里的那批（**直接删除、不发放**——调试
          //    产生的横财不应入账）。非盛开植物的遗留行不删（无误判问题，且保留
          //    其 F78 自动结算语义）；claimed 历史账与阳光账本一律不动；instant 行
          //    （due=开花时刻、正常口径）不受影响。旧库迁移测试的历史 pending 行
          //    均挂在 growing 植物上 → 不受影响。
          //    · 幂等：清理后库中不再有「盛开植物的非整点未领取行」，重复执行无副作用。
          //    · 防复发：新口径 + B35 槽位指纹去重下，单株同屏可收集 ≤ 瞬间 1 条
          //      + 花期内 3 个 8 点槽位 ≈ 24 阳光，不会再堆出大额聚合。
          //    ⚠️ 版本变更（18 → 19），必须配迁移测试（见
          //       `test/m3/migration_v18_to_v19_test.dart`）。
          if (from < 19) {
            final List<QueryRow> legacyRows = await customSelect(
              'SELECT r.id, r.due_at FROM pending_bloom_rewards r '
              'JOIN plants p ON p.id = r.plant_id '
              "WHERE r.claimed = 0 AND r.reward_kind != 'instant' "
              'AND p.status = 1 AND p.bloomed_at IS NOT NULL '
              'AND r.due_at >= p.bloomed_at;',
            ).get();
            for (final QueryRow row in legacyRows) {
              final DateTime due = DateTime.fromMillisecondsSinceEpoch(
                (row.data['due_at'] as int) * 1000,
              );
              final bool isMorningSlot =
                  due.hour == 8 && due.minute == 0 && due.second == 0;
              if (!isMorningSlot) {
                await customStatement(
                  'DELETE FROM pending_bloom_rewards WHERE id = ?;',
                  <Object>[row.data['id']],
                );
              }
            }
          }

          // ⑳ C48（玄参 2026-10-10 拍板）：「允许孩子跳过护眼」默认口径
          //    true → false。历史库在 v15 补列时按旧默认落了 true（家长未显式
          //    动过也是 true），此处无条件翻为 false，让新默认对既有设备立即生效。
          //    ⚠️ 口径变更语义：家长此前**显式开启**过的设置同样被重置（当前
          //    验收阶段仅玄参一台设备，接受重置；正式发布后不得再做同类重置）。
          //    幂等：已为 false 的行 UPDATE 无变化。
          if (from < 20) {
            await customStatement(
              'UPDATE settings SET eye_care_skip_allowed = 0;',
            );
          }

          // ㉑ C52（玄参 2026-10-10 截图拍板）：默认种子数据替换——成长任务
          //    3 条 → 9 条、奖励模板 5 条 → 6 条（价格/科目/分类/联动专注/周限
          //    全按玄参默认版）。纯数据迁移（枚举追加分类值无需改表结构）。
          //    规则：
          //     · 旧种子行若被打卡（check_ins.task_id）/ 兑换（redemption_requests
          //       .template_id）历史引用 → **保留不删**（两表存 id 引用、无外键，
          //       删了会让历史行变孤儿）；无引用 → 删除；
          //     · 新 9+6 默认行 INSERT OR REPLACE（REPLACE 只会覆盖同 id 的
          //       旧种子行——它们是内置模板、非用户自建）；
          //     · 用户自建项（is_custom=1 / 其他 id）一律不动。
          if (from < 21) {
            const List<String> kOldSeedTaskIds = <String>[
              'seed_task_homework',
              'seed_task_read',
              'seed_task_math',
            ];
            const List<String> kOldSeedRewardIds = <String>[
              'seed_snack',
              'seed_cartoon_tonight',
              'seed_extra_10min',
              'seed_weekend_outing',
              'seed_extra_episode',
            ];
            final Set<String> referencedTaskIds =
                (await customSelect('SELECT DISTINCT task_id FROM check_ins;')
                        .get())
                    .map((QueryRow r) => r.data['task_id'] as String)
                    .toSet();
            final Set<String> referencedTemplateIds =
                (await customSelect(
              'SELECT DISTINCT template_id FROM redemption_requests;',
            ).get())
                    .map((QueryRow r) => r.data['template_id'] as String)
                    .toSet();
            for (final String id in kOldSeedTaskIds) {
              if (!referencedTaskIds.contains(id)) {
                await customStatement(
                  'DELETE FROM tasks WHERE id = ?;',
                  <Object>[id],
                );
              }
            }
            for (final String id in kOldSeedRewardIds) {
              if (!referencedTemplateIds.contains(id)) {
                await customStatement(
                  'DELETE FROM reward_templates WHERE id = ?;',
                  <Object>[id],
                );
              }
            }
            // 新默认 9 条成长任务。列序：[id, name, subject, requiresFocus,
            // minFocusMin, sunlightReward, category]；subject 取 enum index
            // （chinese=0 math=1 english=2 general=3），category 同
            // （learning=1 sports=2 life=3）。custom_subject=NULL、
            // repeat_rule='daily'、is_custom=0。
            const List<List<Object>> kV21SeedTasks = <List<Object>>[
              <Object>['seed_task_homework', '完成学校作业', 3, 1, 20, 8, 1],
              <Object>['seed_task_read', '阅读 20 分钟', 0, 0, 15, 8, 1],
              <Object>['seed_task_math', '练习数学口算', 1, 1, 15, 6, 1],
              <Object>['seed_task_english_read', '指读英语20分钟', 2, 0, 15, 8, 1],
              <Object>[
                'seed_task_english_listen',
                '早上听英语听力15分钟',
                2,
                0,
                15,
                6,
                1,
              ],
              <Object>['seed_task_rope_skip', '1分钟跳绳170个以上', 3, 0, 15, 10, 2],
              <Object>[
                'seed_task_homework_first',
                '放学后优先完成作业',
                3,
                0,
                15,
                5,
                1,
              ],
              <Object>[
                'seed_task_pushup',
                '10个俯卧撑+10个仰卧起坐',
                3,
                0,
                15,
                5,
                2,
              ],
              <Object>['seed_task_chores', '帮助家长打扫卫生', 3, 0, 15, 5, 3],
            ];
            for (final List<Object> t in kV21SeedTasks) {
              await customStatement(
                'INSERT OR REPLACE INTO tasks '
                '(id, name, subject, custom_subject, requires_focus, '
                'min_focus_min, sunlight_reward, repeat_rule, is_custom, '
                'category) VALUES (?, ?, ?, NULL, ?, ?, ?, \'daily\', 0, ?);',
                t,
              );
            }
            // 新默认 6 条奖励模板。列序：[id, name, baseCost, freqLimit,
            // contentCategory]；category=1（parentHandled 家长经手）、
            // cooldown_rule=1（weekly 每周限领）、enabled=1。
            // content_category：snacks=1 play=2 entertainment=3。
            const List<List<Object>> kV21SeedRewards = <List<Object>>[
              <Object>['seed_snack', '小零食', 30, 3, 1],
              <Object>['seed_cartoon', '看一集动画片', 100, 1, 3],
              <Object>['seed_extra_play', '睡前多玩10分钟', 20, 3, 3],
              <Object>['seed_weekend_outing', '周末出去玩', 200, 1, 2],
              <Object>['seed_toy', '买一个小玩具', 100, 1, 3],
              <Object>['seed_story', '睡前多听1个故事', 30, 3, 3],
            ];
            for (final List<Object> r in kV21SeedRewards) {
              await customStatement(
                'INSERT OR REPLACE INTO reward_templates '
                '(id, name, category, base_cost, freq_limit, cooldown_rule, '
                'enabled, content_category) '
                'VALUES (?, ?, 1, ?, ?, 1, 1, ?);',
                r,
              );
            }
          }

          // ㉒ v22（C53，玄参 2026-10-10 真机实证「家长天地默认条目重复」）：
          //    v21 换默认种子时，对「被 check_ins / redemption_requests 引用过的
          //    旧种子」采取**保留不断链**策略 —— 于是 3 条旧奖励残留（选今晚动画片 /
          //    多看一集动画片 / 多玩10分钟），与新种子（看一集动画片 / 睡前多玩10
          //    分钟）语义重复。本迁移把「内置种子」集合**强制对齐**到新 9 任务 +
          //    6 奖励：
          //     ① 先把引用旧奖励 id 的兑换历史**重定向**到对应新奖励 id（历史不断
          //        链）：选今晚动画片 / 多看一集动画片 → 看一集动画片；
          //        多玩10分钟 → 睡前多玩10分钟；
          //     ② 删除 3 条旧奖励残留行（**显式 id 白名单**，绝不误伤 UUID 自建项）；
          //     ③ 任务侧防御性清理：删 `is_custom = 0` 且不在新 9 id 集合内的行
          //        （正常库无残留 —— 任务种子 id 从未变过、同 id 已被 v21 覆盖；
          //        仅防历史脏数据。用户自建任务 `is_custom = 1` → 一律不动）。
          //    幂等：重定向后旧 id 已无引用、删除后行已不存在，重复执行无副作用。
          //    ⚠️ 版本变更（21 → 22），必须配迁移测试（见
          //       `test/m3/migration_v21_to_v22_test.dart`）。
          if (from < 22) {
            // ① 兑换历史重定向（旧奖励 id → 新奖励 id，语义等价映射）。
            await customStatement(
              "UPDATE redemption_requests SET template_id = 'seed_cartoon' "
              "WHERE template_id IN ('seed_cartoon_tonight', "
              "'seed_extra_episode');",
            );
            await customStatement(
              "UPDATE redemption_requests SET template_id = 'seed_extra_play' "
              "WHERE template_id = 'seed_extra_10min';",
            );
            // ② 删除 3 条旧奖励残留（显式白名单，不动自建项）。
            await customStatement(
              'DELETE FROM reward_templates WHERE id IN '
              "('seed_cartoon_tonight', 'seed_extra_10min', "
              "'seed_extra_episode');",
            );
            // ③ 任务侧防御性清理（is_custom = 0 且非新 9 条 id）。
            await customStatement(
              'DELETE FROM tasks WHERE is_custom = 0 AND id NOT IN ('
              "'seed_task_homework','seed_task_read','seed_task_math',"
              "'seed_task_english_read','seed_task_english_listen',"
              "'seed_task_rope_skip','seed_task_homework_first',"
              "'seed_task_pushup','seed_task_chores');",
            );
          }

          // ㉓ v23（C54，玄参 2026-10-10 真机实证「家长天地成长任务默认条目重复」）：
          //    把内置种子集合**强制定死**为 9 成长任务 + 6 奖励模板，并清掉任何
          //    「与内置种子**同名**、但 id 不是内置 id」的重复行（历史引用先重定向，
          //    不断链）。
          //    背景：v21 / v22 只按**固定 id** 识别内置行。若库里存在一条「名字与
          //    内置种子完全一致、id 却是别的」的行（用户按同名自建、或历史脏数据），
          //    v22 的 `is_custom = 0` 白名单清理**碰不到它**（它是 is_custom = 1）
          //    → 家长天地里同一个名字出现两条（玄参截图实证：帮助家长打扫卫生 ×2）。
          //    口径（幂等）：
          //     ① 成长任务：同名重复行 → 把它的打卡历史改挂到内置 id，再删该行；
          //     ② 奖励模板：同名重复行 → 把兑换历史改挂到内置 id，再删该行；
          //     ③ 兜底再删一次「is_custom = 0 且不在 9 条 id 白名单内」的脏行
          //        （与 v22③ 同口径，重复执行无副作用）；
          //     ④ **只删不补**：家长主动删掉的内置项不会被本迁移复活
          //        （验收口径：以「删除多余内容」为准）。
          //    幂等：重复行删除后不再匹配；UPDATE 命中 0 行无副作用。
          //    ⚠️ 版本变更（22 → 23），必须配迁移测试（见
          //       `test/m3/migration_v23_test.dart`）。
          if (from < 23) {
            // SQL 字面量（只用编译期常量，无用户输入）。
            String q(String s) => "'${s.replaceAll("'", "''")}'";
            const List<String> seedTaskIds = <String>[
              'seed_task_homework',
              'seed_task_read',
              'seed_task_math',
              'seed_task_english_read',
              'seed_task_english_listen',
              'seed_task_rope_skip',
              'seed_task_homework_first',
              'seed_task_pushup',
              'seed_task_chores',
            ];
            const Map<String, String> seedTaskIdByName = <String, String>{
              '完成学校作业': 'seed_task_homework',
              '阅读 20 分钟': 'seed_task_read',
              '练习数学口算': 'seed_task_math',
              '指读英语20分钟': 'seed_task_english_read',
              '早上听英语听力15分钟': 'seed_task_english_listen',
              '1分钟跳绳170个以上': 'seed_task_rope_skip',
              '放学后优先完成作业': 'seed_task_homework_first',
              '10个俯卧撑+10个仰卧起坐': 'seed_task_pushup',
              '帮助家长打扫卫生': 'seed_task_chores',
            };
            const List<String> seedRewardIds = <String>[
              'seed_snack',
              'seed_cartoon',
              'seed_extra_play',
              'seed_weekend_outing',
              'seed_toy',
              'seed_story',
            ];
            const Map<String, String> seedRewardIdByName = <String, String>{
              '小零食': 'seed_snack',
              '看一集动画片': 'seed_cartoon',
              '睡前多玩10分钟': 'seed_extra_play',
              '周末出去玩': 'seed_weekend_outing',
              '买一个小玩具': 'seed_toy',
              '睡前多听1个故事': 'seed_story',
            };
            final String taskIdList = seedTaskIds.map(q).join(',');
            final String taskNameList = seedTaskIdByName.keys.map(q).join(',');
            final String rewardIdList = seedRewardIds.map(q).join(',');
            final String rewardNameList = seedRewardIdByName.keys.map(q).join(',');

            // ① 成长任务同名重复行：打卡历史重定向 → 删行。
            final List<QueryRow> dupTasks = await customSelect(
              'SELECT id, name FROM tasks '
              'WHERE name IN ($taskNameList) AND id NOT IN ($taskIdList);',
            ).get();
            for (final QueryRow row in dupTasks) {
              final String dupId = row.read<String>('id');
              final String? seedId = seedTaskIdByName[row.read<String>('name')];
              if (seedId == null) continue;
              await customStatement(
                'UPDATE check_ins SET task_id = ? WHERE task_id = ?;',
                <Object>[seedId, dupId],
              );
              await customStatement(
                'DELETE FROM tasks WHERE id = ?;',
                <Object>[dupId],
              );
            }
            // ③ 兜底：非自建脏行（is_custom = 0 且不在 9 条白名单）。
            await customStatement(
              'DELETE FROM tasks WHERE is_custom = 0 AND id NOT IN ($taskIdList);',
            );

            // ② 奖励模板同名重复行：兑换历史重定向 → 删行。
            final List<QueryRow> dupRewards = await customSelect(
              'SELECT id, name FROM reward_templates '
              'WHERE name IN ($rewardNameList) AND id NOT IN ($rewardIdList);',
            ).get();
            for (final QueryRow row in dupRewards) {
              final String dupId = row.read<String>('id');
              final String? seedId =
                  seedRewardIdByName[row.read<String>('name')];
              if (seedId == null) continue;
              await customStatement(
                'UPDATE redemption_requests SET template_id = ? '
                'WHERE template_id = ?;',
                <Object>[seedId, dupId],
              );
              await customStatement(
                'DELETE FROM reward_templates WHERE id = ?;',
                <Object>[dupId],
              );
            }
            // 旧 v21 三条奖励残留 id（幂等兜底，v22 已删过）。
            await customStatement(
              'DELETE FROM reward_templates WHERE id IN '
              "('seed_cartoon_tonight','seed_extra_10min','seed_extra_episode');",
            );
          }

          // ㉔ v24（C55，玄参 2026-10-10 真机实证「成长任务只剩 3 条 / 奖励只剩 4 条」）：
          //    **补齐内置种子**（修复 v23 同名去重引发的数据丢失）。
          //    背景（真机库离线解密实证，非推测）：C52 的 9 任务 + 6 奖励新增项在
          //    该设备上**从未落库**（其内置集合仍是早期 3 任务 + 4 奖励，字段值与新默认
          //    一字不差、仅缺行）；玄参为凑齐手动补了同名条目，而 v23 的「同名去重」
          //    假设「同名内置行一定存在」→ 删掉手动条目后只剩内置那 3 + 4。
          //    口径：**只补不删、不覆盖、不复活**。对 9 条成长任务 / 6 条奖励逐条
          //    `INSERT OR IGNORE`：id 已存在则整行跳过（家长对内置项的改价 / 改名 /
          //    删除一律尊重），id 缺失才补一条默认行。
          //    幂等：第二次执行全部命中 IGNORE，0 行写入。
          //    ⚠️ 版本变更（23 → 24），必须配迁移测试（见
          //       `test/m3/migration_v24_test.dart`）。
          if (from < 24) {
            // 9 条成长任务。列序：[id, name, subject, requiresFocus, minFocusMin,
            // sunlightReward, category]；subject enum（chinese=0 math=1 english=2
            // general=3）、category enum（learning=1 sports=2 life=3）。
            const List<List<Object>> kSeedTasksV24 = <List<Object>>[
              <Object>['seed_task_homework', '完成学校作业', 3, 1, 20, 8, 1],
              <Object>['seed_task_read', '阅读 20 分钟', 0, 0, 15, 8, 1],
              <Object>['seed_task_math', '练习数学口算', 1, 1, 15, 6, 1],
              <Object>['seed_task_english_read', '指读英语20分钟', 2, 0, 15, 8, 1],
              <Object>[
                'seed_task_english_listen',
                '早上听英语听力15分钟',
                2,
                0,
                15,
                6,
                1,
              ],
              <Object>['seed_task_rope_skip', '1分钟跳绳170个以上', 3, 0, 15, 10, 2],
              <Object>[
                'seed_task_homework_first',
                '放学后优先完成作业',
                3,
                0,
                15,
                5,
                1,
              ],
              <Object>[
                'seed_task_pushup',
                '10个俯卧撑+10个仰卧起坐',
                3,
                0,
                15,
                5,
                2,
              ],
              <Object>['seed_task_chores', '帮助家长打扫卫生', 3, 0, 15, 5, 3],
            ];
            for (final List<Object> t in kSeedTasksV24) {
              await customStatement(
                'INSERT OR IGNORE INTO tasks '
                '(id, name, subject, custom_subject, requires_focus, '
                'min_focus_min, sunlight_reward, repeat_rule, is_custom, '
                'category) VALUES (?, ?, ?, NULL, ?, ?, ?, \'daily\', 0, ?);',
                t,
              );
            }
            // 6 条奖励模板。列序：[id, name, baseCost, freqLimit, contentCategory]。
            const List<List<Object>> kSeedRewardsV24 = <List<Object>>[
              <Object>['seed_snack', '小零食', 30, 3, 1],
              <Object>['seed_cartoon', '看一集动画片', 100, 1, 3],
              <Object>['seed_extra_play', '睡前多玩10分钟', 20, 3, 3],
              <Object>['seed_weekend_outing', '周末出去玩', 200, 1, 2],
              <Object>['seed_toy', '买一个小玩具', 100, 1, 3],
              <Object>['seed_story', '睡前多听1个故事', 30, 3, 3],
            ];
            for (final List<Object> r in kSeedRewardsV24) {
              await customStatement(
                'INSERT OR IGNORE INTO reward_templates '
                '(id, name, category, base_cost, freq_limit, cooldown_rule, '
                'enabled, content_category) '
                'VALUES (?, ?, 1, ?, ?, 1, 1, ?);',
                r,
              );
            }
          }
        },
      );

  /// 清空全部业务表（合规删除权 §10.4 C5；供 DataManagementService.clearAll 调用）。
  ///
  /// 仅 DELETE 行、不 DROP 表：删除后 settings 单行由 SettingsLocalRepository
  /// 在下次读取时按需重建默认设置。
  Future<void> deleteEverything() => transaction(() async {
        await delete(settings).go();
        await delete(plants).go();
        await delete(premiumFragments).go();
        await delete(pendingBloomRewards).go();
        await delete(unlockedSpecies).go();
        await delete(focusSessions).go();
        await delete(sunlightLedgers).go();
        await delete(rewardTemplates).go();
        await delete(redemptionRequests).go();
        await delete(monthlyPools).go();
        await delete(tasks).go();
        await delete(checkIns).go();
        await delete(cooldownCounters).go();
        await delete(trackingEvents).go();
        await delete(eyeCareLogs).go();
      });

  /// 该表当前是否含某列（PRAGMA table_info）。
  Future<bool> _hasColumn(String tableName, String columnName) async {
    final List<QueryRow> info =
        await customSelect('PRAGMA table_info($tableName);').get();
    return info.any((QueryRow r) => r.read<String>('name') == columnName);
  }

  /// 缺列才补（幂等），避免 "duplicate column name"。
  ///
  /// 语义与 [Migrator.addColumn] 一致：先查 [PRAGMA table_info] 再决定是否补列。
  Future<void> _ensureColumn<T extends Table, D>(
    Migrator m,
    TableInfo<T, D> table,
    GeneratedColumn column,
  ) async {
    if (!await _hasColumn(table.actualTableName, column.name)) {
      await m.addColumn(table, column);
    }
  }
}

/// SQLCipher 加密库打开器（Lazy：首次访问才建连）。
LazyDatabase openEncryptedDb() {
  return LazyDatabase(() async {
    // 注：sqlite3 3.x 已移除 open.overrideFor（改由原生资产 hook 决定加载哪个库）。
    // 本工程在 pubspec.yaml 的 hooks.user_defines 里配置：
    //   sqlite3: { source: system, name_android: sqlcipher }
    // —— Android 加载 sqlcipher_flutter_libs 经 Maven 提供的 libsqlcipher.so（ABI 兼容 sqlite3），
    //    `PRAGMA key` 因此生效；同时避免了从 GitHub 下载预编译库（本机被代理拦截）。
    // 旧 Android 上 SQLCipher 打开兼容处理（sqlcipher_flutter_libs 提供）。
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/$kDatabaseFileName');
    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$kDatabasePassphrase'");
      },
    );
  });
}
