/// 独立复验探针 #6（qa-verify3）：**概率不变**——把 roll 时机从「结算」前移到「登记」后，
/// 有效奖励分布必须仍与文档常量 (`prd_params`) 完全一致。
///
/// 方法：真实 Drift 库 + 真实服务，注入 `Random(seed)`，连续 N 次「成株即盛开」→ 每次读回
/// **登记时已定奖**的两条 pending，按分支归类（碎片 / 本档种子 / 大额阳光 / 兜底），统计频率；
/// 与常量声明的概率逐个 `closeTo` 比对。
///
/// 关键防污染手段：每轮把 pending 表清空 → `unlocked_species` 始终为空 → 「种子分支」每轮都
/// 真正掉种子（不会因本档物种全持券而退化成兜底阳光），分布不被污染。
///
/// 覆盖任务 #31「概率数值一个字都没改，只把 roll 时机前移」。
library qa_b3_probability_real_db_test;

import 'dart:math';

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
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:test/test.dart';

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

const String _pid = 'p1';

Plant _readyToBloom(DateTime now) => Plant(
      id: _pid,
      speciesId: kStarterSpeciesId, // 向日葵（common）
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: now,
      growthProgress: 1.0,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
      lastWaterAt: now,
      mood: PlantMood.calm,
    );

/// 分支归类。
String _classifyInstant(PendingBloomReward r) {
  if (r.rewardFragments > 0) return 'frag';
  if (r.rewardSpeciesId != null) return 'seed';
  if (r.rewardSunlight > kBloomInstantSunlight) return 'bonus';
  return 'none';
}

String _classifySecond(PendingBloomReward r) {
  if (r.rewardFragments > 0) return 'frag';
  if (r.rewardSpeciesId != null) return 'seed';
  if (r.rewardSunlight >= kBloomBonusSunlightMin) return 'bonus';
  return 'base';
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('⑧ 概率不变：登记分支频率 == 文档常量（真实库，N=3000 次盛开）', () async {
    const int n = 3000;
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
    addTearDown(database.close);

    final PlantLocalRepository plants = PlantLocalRepository(database);
    final SunlightLocalRepository ledger = SunlightLocalRepository(database);
    final SettingsLocalRepository settings = SettingsLocalRepository(database);
    await settings.saveSettings(const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: kDailyFocusCapLow,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: kPoolBudgetDefaultLow,
      gardenPotCapacity: 4,
    ));
    await ledger.append(SunlightEntry(
      id: 'seed',
      ts: DateTime(2026, 1, 1),
      type: SunlightType.earn,
      gross: 1000000,
      net: 1000000,
      balanceAfter: 1000000,
      refType: 'seed',
      dayKey: '2026-01-01',
    ));
    final PlantGrowthService svc = PlantGrowthService(
      plants: plants,
      focus: _NoFocusRepo(),
      ledger: ledger,
      settings: settings,
      bloomRewards: plants,
      random: Random(20260101),
    );

    final Map<String, int> inst = <String, int>{
      'frag': 0, 'seed': 0, 'bonus': 0, 'none': 0,
    };
    final Map<String, int> sec = <String, int>{
      'frag': 0, 'seed': 0, 'bonus': 0, 'base': 0,
    };
    final DateTime base = DateTime(2026, 9, 25, 8, 0);

    for (int i = 0; i < n; i++) {
      final DateTime now = base.add(Duration(minutes: i));
      await plants.savePlant(_readyToBloom(now));
      await svc.tickAll(now);
      // 读回**登记时**的定奖内容：区间取到 now+48h，令 instant 与第二段两条都到期可见。
      final List<PendingBloomReward> due = await plants
          .pendingBloomRewardsDue(now.add(const Duration(hours: kBloomRewardDelayHours)));
      final PendingBloomReward instant = due.firstWhere(
          (PendingBloomReward r) => r.rewardKind == kBloomRewardPhaseInstant);
      final PendingBloomReward second = due.firstWhere(
          (PendingBloomReward r) => r.rewardKind != kBloomRewardPhaseInstant);
      inst[_classifyInstant(instant)] = inst[_classifyInstant(instant)]! + 1;
      sec[_classifySecond(second)] = sec[_classifySecond(second)]! + 1;
      // 清空 pending：避免 unlocked_species 增长污染种子分支，并避免 O(N^2) 累积。
      await database.customStatement('DELETE FROM pending_bloom_rewards;');
    }

    double f(Map<String, int> m, String k) => m[k]! / n;
    print('[⑧] instant 频率 frag=${f(inst, 'frag')} seed=${f(inst, 'seed')} '
        'bonus=${f(inst, 'bonus')} none=${f(inst, 'none')}');
    print('[⑧] second  频率 frag=${f(sec, 'frag')} seed=${f(sec, 'seed')} '
        'bonus=${f(sec, 'bonus')} base=${f(sec, 'base')}');

    // 普通档「开花瞬间」：碎片 15% / 种子 5% / 大额阳光 20% / 无额外 60%。
    expect(f(inst, 'frag'), closeTo(kBloomInstantFragmentRate, 0.03));
    expect(f(inst, 'seed'), closeTo(kBloomInstantSeedRate, 0.03));
    expect(f(inst, 'bonus'), closeTo(kBloomInstantBonusRate, 0.03));
    expect(f(inst, 'none'), closeTo(1 - kBloomInstantFragmentRate - kBloomInstantSeedRate - kBloomInstantBonusRate, 0.03));

    // 普通档「第二段」：碎片 15% / 种子 5% / 大额阳光 20% / 基础阳光 60%。
    expect(f(sec, 'frag'), closeTo(kBloomSecondPhaseFragmentRate, 0.03));
    expect(f(sec, 'seed'), closeTo(kBloomSecondPhaseSeedRate, 0.03));
    expect(f(sec, 'bonus'), closeTo(kBloomSecondPhaseBonusRate, 0.03));
    expect(f(sec, 'base'), closeTo(1 - kBloomSecondPhaseFragmentRate - kBloomSecondPhaseSeedRate - kBloomSecondPhaseBonusRate, 0.03));
  });
}
