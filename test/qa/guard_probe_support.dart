/// 花园守卫独立验收（QA 自造探针）共用的**真实链路**夹具。
///
/// 与 `test/guard/` 的工程师测试**刻意不共享**任何 helper：
///  · 守卫存档用**真实** [GuardStatePrefsStore]（SharedPreferences mock）；
///  · 阳光账本 / 植物 / 专注全部走**真实** drift 内存库 + 真实仓储；
///  · 成长扣减走**真实** [PlantGrowthService]（`raidGrowth`）。
///
/// 这样探针验证的是「生产装配后的行为」，而不是工程师自己写的假替身。
library;

import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/guard_state_prefs_store.dart';
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

import '../helpers/no_hit_random.dart';

/// 一套「生产同款」的守卫运行环境（内存 DB + 内存 prefs）。
class GuardProbeEnv {
  GuardProbeEnv._({
    required this.sp,
    required this.database,
    required this.account,
    required this.ledger,
    required this.store,
    required this.plants,
    required this.focus,
    required this.growth,
    required this.clock,
  });

  final SharedPreferences sp;
  final db.AppDatabase database;
  final AccountService account;
  final SunlightLocalRepository ledger;
  final GuardStatePrefsStore store;
  final PlantLocalRepository plants;
  final FocusLocalRepository focus;
  final PlantGrowthService growth;
  final DateTime Function() clock;

  String get childId => account.childId;
  String get today => dayKey(clock());

  /// 守卫编排服务（默认用夹具时钟；可换时钟模拟「次日重进 App」）。
  GuardService guardAt(DateTime Function() at) => GuardService(
        store: store,
        ledger: ledger,
        focus: focus,
        plants: plants,
        growth: growth,
        childId: () => childId,
        clock: at,
      );

  GuardService get guard => guardAt(clock);

  /// 今日券服务（时钟与夹具一致，`currentBuff` 才认得出「今天」）。
  GuardVoucherService get vouchers => GuardVoucherService(
        store: store,
        childId: () => childId,
        clock: clock,
      );

  Future<void> close() => database.close();

  /// 建一个干净环境。[clock] 默认指向 2026-11-09 10:30（固定日，便于断言）。
  static Future<GuardProbeEnv> create({
    DateTime Function()? clock,
    GuardStatePrefsStore Function(SharedPreferences sp)? storeFactory,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final DateTime Function() tick =
        clock ?? () => DateTime(2026, 11, 9, 10, 30);
    final SunlightLocalRepository ledger =
        SunlightLocalRepository(database, account: account);
    final PlantLocalRepository plants =
        PlantLocalRepository(database, account: account);
    final FocusLocalRepository focus =
        FocusLocalRepository(database, account: account);
    final GuardStatePrefsStore store =
        (storeFactory ?? (SharedPreferences p) => GuardStatePrefsStore(p, clock: tick))(sp);
    final PlantGrowthService growth = PlantGrowthService(
      plants: plants,
      focus: focus,
      ledger: ledger,
      settings: SettingsLocalRepository(database),
      bloomRewards: InMemoryBloomRewardRepository(),
      weedRandom: NoHitRandom(),
    );
    return GuardProbeEnv._(
      sp: sp,
      database: database,
      account: account,
      ledger: ledger,
      store: store,
      plants: plants,
      focus: focus,
      growth: growth,
      clock: tick,
    );
  }

  /// 账本里**当前孩子**的全部行（按写入顺序）。
  Future<List<SunlightEntry>> ledgerRows() => ledger.all();

  /// 账本中某 refType 的行（按写入顺序）。
  Future<List<SunlightEntry>> rowsOf(String refType) async =>
      (await ledger.all())
          .where((SunlightEntry e) => e.refType == refType)
          .toList()
        ..sort((SunlightEntry a, SunlightEntry b) => a.ts.compareTo(b.ts));

  /// 种一株植物（默认抽芽期、进度 0.5、昨天浇过水）。
  Future<Plant> seedPlant(
    String id, {
    int potIndex = 0,
    PlantStatus status = PlantStatus.growing,
    PlantStage stage = PlantStage.sprout,
    double progress = 0.5,
    bool weed = false,
    bool pest = false,
    DateTime? now,
  }) async {
    final DateTime at = now ?? clock();
    final DateTime day = DateTime(at.year, at.month, at.day);
    final Plant plant = Plant(
      id: id,
      speciesId: 'species_sunflower',
      potIndex: potIndex,
      stage: stage,
      stageStartedAt: at.subtract(const Duration(days: 1)),
      growthProgress: progress,
      growthFactor: 1.0,
      status: status,
      plantedAt: at.subtract(const Duration(days: 3)),
      lastWaterAt: at.subtract(const Duration(days: 1)),
      bloomedAt:
          status == PlantStatus.bloomed ? at.subtract(const Duration(days: 1)) : null,
      bloomCount: status == PlantStatus.bloomed ? 1 : 0,
      weedAt: weed ? day : null,
      pestAt: pest ? day : null,
      weedPestRollDay: (weed || pest) ? day : null,
    );
    await plants.savePlant(plant);
    return plant;
  }

  /// 把余额抬到 [amount]（种一行 earn，refType = `qa_seed`）。
  Future<void> seedBalance(double amount, {DateTime? at}) async {
    final DateTime ts = at ?? clock();
    await ledger.append(SunlightEntry(
      id: 'qa_seed_${amount.toStringAsFixed(2)}_${ts.microsecondsSinceEpoch}',
      ts: ts,
      type: SunlightType.earn,
      gross: amount,
      net: amount,
      balanceAfter: amount,
      refType: 'qa_seed',
      refId: 'qa',
      dayKey: dayKey(ts),
    ));
  }
}
