import 'package:test/test.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/services/redemption_service.dart';

RewardTemplate tpl(RewardCategory c, {int baseCost = 50}) => RewardTemplate(
      id: 'r1',
      name: '测试奖励',
      category: c,
      baseCost: baseCost,
      frequencyLimitPerWeek: 3,
    );

void main() {
  group('C5 免确认双条件 · 高年级（单笔候选阈值 130，但天花板 100 才是实际放行边界）', () {
    const age = AgeTier.high;
    final pool = WeeklyPool(weekKey: '2026-09-07', budget: kPoolBudgetDefaultHigh);

    test('单笔价 = 131：不满足① → 进待核销', () {
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 131,
        ageTier: age,
        pool: pool,
      );
      expect(d.status, RequestStatus.pending);
      expect(d.autoApproved, isFalse);
    });

    test('单笔价 = 130：①满足但天花板 100 绑定 → 进待核销（130 不自动放行）', () {
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 130,
        ageTier: age,
        pool: pool,
      );
      expect(d.status, RequestStatus.pending);
    });

    test('单笔价 = 100：恰好顶到天花板 → 自动放行（默认池 400 上限 100）', () {
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 100,
        ageTier: age,
        pool: pool,
      );
      expect(d.status, RequestStatus.verified);
      expect(d.autoApproved, isTrue);
    });

    test('单笔价 = 101：超过天花板 100 → 进待核销', () {
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 101,
        ageTier: age,
        pool: pool,
      );
      expect(d.status, RequestStatus.pending);
    });

    test('自服务类即使极低价也一律不自动放行', () {
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.selfService, baseCost: 10),
        cost: 4,
        ageTier: age,
        pool: pool,
      );
      expect(d.status, RequestStatus.pending);
      expect(d.autoApproved, isFalse);
    });
  });

  group('C5 周累计自动放行上限 = min(100/40, 周池×25%)', () {
    const age = AgeTier.high;

    test('默认池 400 → 上限 100；autoReleased=90, cost=10 刚好放行', () {
      final pool = WeeklyPool(weekKey: '2026-09-07', budget: 400, autoReleased: 90);
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 10,
        ageTier: age,
        pool: pool,
      );
      expect(d.status, RequestStatus.verified);
    });

    test('默认池 400 → 上限 100；autoReleased=95, cost=10 超上限 → 进待核销', () {
      final pool = WeeklyPool(weekKey: '2026-09-07', budget: 400, autoReleased: 95);
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 10,
        ageTier: age,
        pool: pool,
      );
      expect(d.status, RequestStatus.pending);
    });

    test('口径裁定示例：池降到 200 → 上限随之降到 50（高）', () {
      // autoCap = min(100, 200*0.25=50) = 50
      final pool = WeeklyPool(weekKey: '2026-09-07', budget: 200, autoReleased: 40);
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 10,
        ageTier: age,
        pool: pool,
      );
      expect(d.status, RequestStatus.verified); // 40+10=50 <= 50

      final pool2 = WeeklyPool(weekKey: '2026-09-07', budget: 200, autoReleased: 45);
      final d2 = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 10,
        ageTier: age,
        pool: pool2,
      );
      expect(d2.status, RequestStatus.pending); // 45+10=55 > 50
    });

    test('低年段：池=200 → 公式上限 40（C5 分母已裁定为 40）', () {
      // min(40, 200*0.25=50) = 40
      final pool = WeeklyPool(weekKey: '2026-09-07', budget: 200, autoReleased: 30);
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 10,
        ageTier: AgeTier.low,
        pool: pool,
      );
      expect(d.status, RequestStatus.verified); // 30+10=40 <= 40

      final pool2 = WeeklyPool(weekKey: '2026-09-07', budget: 200, autoReleased: 35);
      final d2 = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 10,
        ageTier: AgeTier.low,
        pool: pool2,
      );
      expect(d2.status, RequestStatus.pending); // 35+10=45 > 40
    });
  });

  group('整体池余量：used 占满时不得自动放行（防超额）', () {
    test('池=100, used=90, cost=20 → 超整体池 → 排队', () {
      final pool = WeeklyPool(weekKey: '2026-09-07', budget: 100, used: 90);
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 20,
        ageTier: AgeTier.high,
        pool: pool,
      );
      expect(d.status, RequestStatus.queued);
    });

    test('池未满但累计自动已达 25% 上限 → 待核销', () {
      // 池=100，25% 上限=25；autoReleased=10, cost=20 → 累计 30>25 不自动放行，但池余量充足 → pending
      final pool = WeeklyPool(weekKey: '2026-09-07', budget: 100, autoReleased: 10);
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 20,
        ageTier: AgeTier.high,
        pool: pool,
      );
      expect(d.status, RequestStatus.pending);
    });

    test('池=100, used=0, cost=20 → 小额自动放行（25% 上限 25，整体余量充足）', () {
      final pool = WeeklyPool(weekKey: '2026-09-07', budget: 100);
      final d = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 20,
        ageTier: AgeTier.high,
        pool: pool,
      );
      expect(d.status, RequestStatus.verified);
    });
  });

  group('低年段单笔放行边界（天花板 40，非 50）', () {
    test('cost=40 放行 / cost=41 进待核销（默认池 160 → 上限 40）', () {
      final pool = WeeklyPool(weekKey: '2026-09-07', budget: kPoolBudgetDefaultLow);
      final ok = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 40,
        ageTier: AgeTier.low,
        pool: pool,
      );
      expect(ok.status, RequestStatus.verified);
      final no = RedemptionService.decide(
        template: tpl(RewardCategory.parentHandled),
        cost: 41,
        ageTier: AgeTier.low,
        pool: pool,
      );
      expect(no.status, RequestStatus.pending);
    });
  });
}
