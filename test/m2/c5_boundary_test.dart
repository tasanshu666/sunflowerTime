/// C5 双闸阈值边界（A2 验收）：纯函数 [RedemptionService.decide] + [capFor] 的临界值。
///
/// 双闸口径（§3.2 / §4）：
///  ① 单笔价 ≤ 高 130 / 低 50
///  ② 当周累计自动放行 ≤ min(固定天花板 100/40, 周池 × 25%)，且整体池余量充足
///  ③ 自服务类一律不自动放行
///  满足双条件 → verified；不满足且池未满 → pending；超池 → queued。
library c5_boundary_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/age_tier_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/services/redemption_service.dart';

void main() {
  group('C5 双闸阈值边界', () {
    const RewardTemplate parentHandled = RewardTemplate(
      id: 't',
      name: 't',
      category: RewardCategory.parentHandled,
      baseCost: 1,
      frequencyLimitPerWeek: 1,
    );

    test('低档：cost == 周池上限 → pending（未超池）', () {
      const int budget = 160;
      final WeeklyPool pool = WeeklyPool(
        weekKey: '2026-09-07',
        budget: budget,
        used: 0,
        autoReleased: 0,
        resetAt: DateTime(2026, 9, 1),
      );
      expect(
        RedemptionService.decide(
          template: parentHandled,
          cost: budget,
          ageTier: AgeTier.low,
          pool: pool,
        ).status,
        RequestStatus.pending,
      );
    });

    test('低档：cost == 周池上限 + 1 → queued（超池下周释放）', () {
      const int budget = 160;
      final WeeklyPool pool = WeeklyPool(
        weekKey: '2026-09-07',
        budget: budget,
        used: 0,
        autoReleased: 0,
        resetAt: DateTime(2026, 9, 1),
      );
      expect(
        RedemptionService.decide(
          template: parentHandled,
          cost: budget + 1,
          ageTier: AgeTier.low,
          pool: pool,
        ).status,
        RequestStatus.queued,
      );
    });

    test('低档：cost == 40 同时过单笔上限(50)与周池自动放行上限(40) → verified(自动放行)', () {
      final WeeklyPool pool = WeeklyPool(
        weekKey: '2026-09-07',
        budget: 160,
        used: 0,
        autoReleased: 0,
        resetAt: DateTime(2026, 9, 1),
      );
      final RedemptionDecision r = RedemptionService.decide(
        template: parentHandled,
        cost: 40,
        ageTier: AgeTier.low,
        pool: pool,
      );
      expect(r.status, RequestStatus.verified);
      expect(r.autoApproved, isTrue);
    });

    test('低档：cost == 41 单笔未超(≤50)但周池自动放行上限(40)已满 → pending', () {
      final WeeklyPool pool = WeeklyPool(
        weekKey: '2026-09-07',
        budget: 160,
        used: 0,
        autoReleased: 0,
        resetAt: DateTime(2026, 9, 1),
      );
      final RedemptionDecision r = RedemptionService.decide(
        template: parentHandled,
        cost: 41,
        ageTier: AgeTier.low,
        pool: pool,
      );
      expect(r.status, RequestStatus.pending);
      expect(r.autoApproved, isFalse);
    });

    test('低档：cost == 51 超单笔上限 → 不自动放行（pending，未超池）', () {
      final WeeklyPool pool = WeeklyPool(
        weekKey: '2026-09-07',
        budget: 160,
        used: 0,
        autoReleased: 0,
        resetAt: DateTime(2026, 9, 1),
      );
      final RedemptionDecision r = RedemptionService.decide(
        template: parentHandled,
        cost: 51,
        ageTier: AgeTier.low,
        pool: pool,
      );
      expect(r.status, RequestStatus.pending);
      expect(r.autoApproved, isFalse);
    });

    test('capFor：低档周池 160 → 40（= min(40, 160×0.25)）', () {
      expect(capFor(AgeTier.low, 160), 40);
    });

    test('capFor：周池极大 → 取固定天花板 40（低档）', () {
      expect(capFor(AgeTier.low, 100000), 40);
    });

    test('自服务类无论价格多低都不自动放行（C5③）', () {
      const RewardTemplate selfService = RewardTemplate(
        id: 's',
        name: 's',
        category: RewardCategory.selfService,
        baseCost: 1,
        frequencyLimitPerWeek: 1,
      );
      final WeeklyPool pool = WeeklyPool(
        weekKey: '2026-09-07',
        budget: 160,
        used: 0,
        autoReleased: 0,
        resetAt: DateTime(2026, 9, 1),
      );
      final RedemptionDecision r = RedemptionService.decide(
        template: selfService,
        cost: 10,
        ageTier: AgeTier.low,
        pool: pool,
      );
      expect(r.status, isNot(RequestStatus.verified));
      expect(r.autoApproved, isFalse);
    });
  });
}
