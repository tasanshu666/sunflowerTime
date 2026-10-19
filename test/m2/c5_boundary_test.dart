/// 兑换判定边界（**C90-C 修订**）：纯函数 [RedemptionService.decide] 的临界值。
///
/// C90-C（玄参 2026-10-18 拍板）：自动放行（C5 免确认双条件）**全删** ——
/// `decide()` 只会给出 pending / rejected 两态；verified（自动核销）不再是判定产物。
/// 原「单笔阈值 130/50、天花板 100/40、池×25%、自服务类例外」分组全部移除。
///
/// 钉死口径：
///  · 限额池（budget > kWeeklyPoolBudgetUnlimited，低/中年级默认 300/600）：
///    cost == 预算余量 → pending；cost 超余量 → rejected
///   （C62：超池直接拒绝，不再排队，调用方不得落库）；
///  · 不限额（budget == kWeeklyPoolBudgetUnlimited = 0，高年级默认）：一律 pending，
///    兑换只受阳光余额约束（余额闸门在编排层，不属本判定）。
library c5_boundary_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/services/redemption_service.dart';

void main() {
  group('兑换判定边界（C90-C：仅超池拒绝 / 其余待核销）', () {
    const RewardTemplate parentHandled = RewardTemplate(
      id: 't',
      name: 't',
      category: RewardCategory.parentHandled,
      baseCost: 1,
      frequencyLimitPerWeek: 1,
    );

    WeeklyPool pool({
      required int budget,
      int used = 0,
      int autoReleased = 0,
    }) =>
        WeeklyPool(
          weekKey: '2026-09-07',
          budget: budget,
          used: used,
          autoReleased: autoReleased,
          resetAt: DateTime(2026, 9, 1),
        );

    test('限额池：cost == 周池余量 → pending（未超池）', () {
      // 边界随 C90-C 同日二次修订重算：低年级默认额度 200 → 300。
      final WeeklyPool p = pool(budget: kPoolBudgetDefaultLow);
      expect(
        RedemptionService.decide(
          template: parentHandled,
          cost: kPoolBudgetDefaultLow,
          ageTier: AgeTier.low,
          pool: p,
        ).status,
        RequestStatus.pending,
      );
    });

    test('限额池：cost == 周池余量 + 1 → rejected（C62：超池直接拒绝，不再排队）',
        () {
      final WeeklyPool p = pool(budget: kPoolBudgetDefaultLow);
      final RedemptionDecision r = RedemptionService.decide(
        template: parentHandled,
        cost: kPoolBudgetDefaultLow + 1,
        ageTier: AgeTier.low,
        pool: p,
      );
      expect(r.status, RequestStatus.rejected);
    });

    test('限额池：used 已占满 → 任何新兑换均 rejected（防超额）', () {
      final WeeklyPool p = pool(budget: 100, used: 100);
      final RedemptionDecision r = RedemptionService.decide(
        template: parentHandled,
        cost: 1,
        ageTier: AgeTier.high,
        pool: p,
      );
      expect(r.status, RequestStatus.rejected);
    });

    test('限额池：池未满但接近满 → pending（不再有「自动放行 verified」产物）', () {
      // C90-C 回归：原「小额 + 池余量充足 → verified 自动放行」分支已删；
      // 即便 cost 极小、池余充足，判定也只能是 pending（家长显式核销）。
      final WeeklyPool p = pool(budget: 100, used: 10);
      final RedemptionDecision r = RedemptionService.decide(
        template: parentHandled,
        cost: 1,
        ageTier: AgeTier.high,
        pool: p,
      );
      expect(r.status, RequestStatus.pending);
      expect(r.status, isNot(RequestStatus.verified));
    });

    test('不限额（budget == 0 哨兵，高年级默认）→ 一律 pending，永不判超池', () {
      // used/autoReleased 任意大都不影响：不限额下兑换只受阳光余额约束。
      final WeeklyPool p = pool(
        budget: kWeeklyPoolBudgetUnlimited,
        used: 100000,
        autoReleased: 100000,
      );
      final RedemptionDecision r = RedemptionService.decide(
        template: parentHandled,
        cost: 500,
        ageTier: AgeTier.high,
        pool: p,
      );
      expect(r.status, RequestStatus.pending);
    });

    test('自服务类与家长经手类在新口径下判定一致（类别不再影响走向）', () {
      const RewardTemplate selfService = RewardTemplate(
        id: 's',
        name: 's',
        category: RewardCategory.selfService,
        baseCost: 1,
        frequencyLimitPerWeek: 1,
      );
      final WeeklyPool p = pool(budget: kPoolBudgetDefaultLow);
      final RedemptionDecision a = RedemptionService.decide(
        template: selfService,
        cost: 10,
        ageTier: AgeTier.low,
        pool: p,
      );
      final RedemptionDecision b = RedemptionService.decide(
        template: parentHandled,
        cost: 10,
        ageTier: AgeTier.low,
        pool: p,
      );
      expect(a.status, b.status);
      expect(a.status, RequestStatus.pending);
    });
  });
}
