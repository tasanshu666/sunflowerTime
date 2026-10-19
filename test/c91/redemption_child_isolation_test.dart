/// C91 / F123：兑换申请按孩子隔离回归（玄参平板真机反馈，最高优先级）。
///
/// 复现路径（真机）：孩子 A 申请 3 笔兑换 → 家长把当前孩子切到 B →
/// 家长端「今日」tab 待核销列表出现 A 的申请；核销后 A、B 视图同时变已核销
/// （同一行被两个视图重复展示）。
///
/// 拍板修法（🔴 仓储级统一按当前孩子过滤，接口签名零改动）：
///  · `RewardLocalRepository` 的全部 `redemption_requests` 读路径
///    （pendingAndQueued / verifiedRequests / rejectedRequests / queuedOfWeek）
///    一律按当前 childId 过滤（沿批 1/2 `_childId` 单点可选注入模式）；
///  · `RedemptionOrchestrationService.verify / reject / forceRelease` 加跨孩子
///    防护：目标申请 childId ≠ 当前孩子 → 抛 [StateError]（双保险）。
///
/// 钉死口径：
///  ① A 申请 → 切 B：B 的待核销列表为空（孩子端「我的申请」同源同滤）；
///  ② B 视图核销 / 拒绝 A 的申请 id → 被拒（StateError，状态/账本零改动）；
///  ③ 核销后记录各归各：A 的已核销记录只在 A 的视图，B 看不到；
///  ④ 未注入 AccountService 的仓储（既有单测路径）= 恒按默认孩子，行为不变。
///
/// 脚手架参照 `test/c90/child_data_isolation_batch2_test.dart`：
/// 内存 Drift 库 + mock SP + 真 Dao / 真仓储全链路（走真实编排服务）。
library redemption_child_isolation_test;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/tracking_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/weekly_pool_local_repository.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/redemption_orchestration_service.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime now = DateTime(2026, 10, 19, 10);

  /// 真依赖组装：内存 Drift 库 + mock SP + 真仓储全链路 + 真实编排服务。
  Future<(
    AccountService,
    db.AppDatabase,
    RewardLocalRepository,
    RedemptionOrchestrationService,
  )> build() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    final ChildProfileLocalRepository children =
        ChildProfileLocalRepository(database);
    final AccountService account = AccountService(
      children: children,
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final RewardLocalRepository reward =
        RewardLocalRepository(database, account: account);
    final WeeklyPoolService pools = WeeklyPoolService(
      WeeklyPoolLocalRepository(database, account: account),
      SettingsLocalRepository(database),
      TrackingLocalRepository(database),
      account: account,
    );
    final RedemptionOrchestrationService orchestration =
        RedemptionOrchestrationService(
      reward: reward,
      pools: pools,
      ledger: SunlightLocalRepository(database, account: account),
      tracking: TrackingLocalRepository(database),
      account: account,
      settings: SettingsLocalRepository(database),
    );
    return (account, database, reward, orchestration);
  }

  /// 给当前孩子发 1000 阳光（真账本 append，落当前 childId）。
  Future<void> grantSunlight(
      db.AppDatabase database, AccountService account) async {
    final DateTime ts = DateTime(2026, 10, 19, 9);
    final double balance = await SunlightLocalRepository(database,
            account: account)
        .balance();
    await SunlightLocalRepository(database, account: account).append(
      SunlightEntry(
        id: const Uuid().v4(),
        ts: ts,
        type: SunlightType.earn,
        gross: 1000,
        net: 1000,
        balanceAfter: balance + 1000,
        refType: 'debug_grant',
        refId: null,
        dayKey: dayKey(ts),
      ),
    );
  }

  /// 种一个可兑换的奖励模板（全局表，跨孩子共享；frequencyLimitPerWeek = 0
  /// 视为不限次数，让本测试可以连续提交多笔）。
  Future<void> seedTemplate(RewardRepository reward) async {
    await reward.saveTemplate(const RewardTemplate(
      id: 'tpl_snack',
      name: '小零食',
      category: RewardCategory.parentHandled,
      baseCost: 20,
      frequencyLimitPerWeek: 0,
    ));
  }

  group('F123 · 兑换申请按孩子隔离（仓储级过滤）', () {
    test('① A 申请 2 笔 → 切 B：待核销列表为空（家长今日 tab / 孩子端我的申请同源）',
        () async {
      final (
        AccountService account,
        db.AppDatabase database,
        RewardLocalRepository reward,
        RedemptionOrchestrationService orchestration,
      ) = await build();
      addTearDown(database.close);

      await seedTemplate(reward);
      await grantSunlight(database, account);

      // A（默认孩子）连续申请 2 笔。
      final SubmitResult r1 = await orchestration.submit(
          'tpl_snack', AgeTier.low, DateTime(2026, 10, 19, 9, 30));
      final SubmitResult r2 = await orchestration.submit(
          'tpl_snack', AgeTier.low, DateTime(2026, 10, 19, 9, 40));
      expect(r1.outcome, SubmitOutcome.pending);
      expect(r2.outcome, SubmitOutcome.pending);
      expect(await reward.pendingAndQueued(), hasLength(2));

      // 家长切到 B → 待核销列表必须为空（修复前：出现 A 的申请）。
      final ChildProfile b = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(b.id);
      expect(await reward.pendingAndQueued(), isEmpty,
          reason: 'F123：B 的待核销列表绝不能出现 A 的申请');
      expect(await orchestration.pendingList(), isEmpty,
          reason: '家长今日 tab 待核销卡同样只看当前孩子');
    });

    test('② B 视图核销 / 拒绝 A 的申请 id → 被拒（StateError），状态与账本零改动',
        () async {
      final (
        AccountService account,
        db.AppDatabase database,
        RewardLocalRepository reward,
        RedemptionOrchestrationService orchestration,
      ) = await build();
      addTearDown(database.close);

      await seedTemplate(reward);
      await grantSunlight(database, account);

      final SubmitResult r =
          await orchestration.submit('tpl_snack', AgeTier.low, now);
      final String idA = r.requestId!;

      final ChildProfile b = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(b.id);

      // B 核销 A 的申请 → 拒绝并报错。
      await expectLater(
        orchestration.verify(idA, now),
        throwsStateError,
        reason: 'F123：跨孩子核销必须被拒（仓储过滤 + 编排层双保险）',
      );
      // B 拒绝 A 的申请 → 同样被拒。
      await expectLater(
        orchestration.reject(idA, now),
        throwsStateError,
      );

      // 状态零改动：切回 A，申请仍是 pending、账本未被扣。
      await account.switchTo(kChildIdDefault);
      final List<RedemptionRequest> pending = await reward.pendingAndQueued();
      expect(pending, hasLength(1));
      expect(pending.single.id, idA);
      expect(pending.single.status, RequestStatus.pending);
      final double balance =
          await SunlightLocalRepository(database, account: account).balance();
      expect(balance, 1000, reason: '跨孩子核销被拒 → 绝不扣账本');
    });

    test('③ 核销后记录各归各：A 的已核销记录只在 A 的视图出现', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        RewardLocalRepository reward,
        RedemptionOrchestrationService orchestration,
      ) = await build();
      addTearDown(database.close);

      await seedTemplate(reward);
      await grantSunlight(database, account);

      final SubmitResult r =
          await orchestration.submit('tpl_snack', AgeTier.low, now);
      final ChildProfile b = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(b.id);
      await expectLater(orchestration.verify(r.requestId!, now),
          throwsStateError);

      // 切回 A 正常核销。
      await account.switchTo(kChildIdDefault);
      await orchestration.verify(r.requestId!, now);

      // A 的已核销记录恰 1 条；B 的为空（修复前：同一行被两个视图重复展示）。
      final List<RedemptionRequest> verifiedA =
          await reward.verifiedRequests();
      expect(verifiedA, hasLength(1));
      expect(verifiedA.single.id, r.requestId);

      await account.switchTo(b.id);
      expect(await reward.verifiedRequests(), isEmpty,
          reason: 'F123：核销记录各归各，B 视图不得出现 A 的已核销行');

      // 拒绝对称通知同源同滤：A 的 rejected 列表不含任何 B 视角可见行。
      await account.switchTo(kChildIdDefault);
      expect(await reward.rejectedRequests(), isEmpty);
    });

    test('④ 未注入 AccountService 的仓储（既有单测路径）：恒按默认孩子过滤，行为不变',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final AccountService account = AccountService(
        children: ChildProfileLocalRepository(database),
        settings: SettingsLocalRepository(database),
        prefs: sp,
      );
      await account.initialize();
      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);

      // ⚠️ 不传 account：恒按 kChildIdDefault（Plan B 兼容语义）。
      final RewardLocalRepository reward = RewardLocalRepository(database);
      await reward.saveTemplate(const RewardTemplate(
        id: 'tpl_x',
        name: '模板X',
        category: RewardCategory.parentHandled,
        baseCost: 10,
        frequencyLimitPerWeek: 0,
      ));
      await reward.createRequest(RedemptionRequest(
        id: 'r_stub',
        childId: kChildIdDefault,
        templateId: 'tpl_x',
        requestedAt: now,
        cost: 10,
        status: RequestStatus.pending,
      ));

      // 即使 AccountService 当前活跃的是二娃，无 account 的仓储仍按默认孩子读。
      expect(await reward.pendingAndQueued(), hasLength(1));
      // 默认孩子实例读不到（隔离成立）。
      final RewardLocalRepository scoped =
          RewardLocalRepository(database, account: account);
      expect(await scoped.pendingAndQueued(), isEmpty);
    });
  });
}
