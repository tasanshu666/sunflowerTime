/// 三档 AgeTier 参数单点测试（§1.3 / §3.2）。
///
/// 纯 Dart：仅依赖 domain/entities 与 core/constants，无 Flutter 依赖。
import 'package:sunflower_time/core/constants/age_tier_params.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

void main() {
  group('tierForAge 分档映射', () {
    test('6–8 岁 = low', () {
      expect(tierForAge(6), AgeTier.low);
      expect(tierForAge(7), AgeTier.low);
      expect(tierForAge(8), AgeTier.low);
    });
    test('9–10 岁 = mid', () {
      expect(tierForAge(9), AgeTier.mid);
      expect(tierForAge(10), AgeTier.mid);
    });
    test('11–12 岁 = high', () {
      expect(tierForAge(11), AgeTier.high);
      expect(tierForAge(12), AgeTier.high);
    });
    test('越界取最近端点', () {
      expect(tierForAge(0), AgeTier.low); // 下越界 → low
      expect(tierForAge(5), AgeTier.low);
      expect(tierForAge(13), AgeTier.high); // 上越界 → high
      expect(tierForAge(99), AgeTier.high);
    });
  });

  group('ageTierK 分龄系数', () {
    test('低1.0 / 中1.2 / 高1.5', () {
      expect(ageTierK(AgeTier.low), 1.0);
      expect(ageTierK(AgeTier.mid), 1.2);
      expect(ageTierK(AgeTier.high), 1.5);
    });
  });

  group('capFor C5② 月度自动放行上限', () {
    test('低档 160 → min(40, 160×25%)=40', () {
      expect(capFor(AgeTier.low, 160), 40);
    });
    test('高档 400 → min(100, 400×25%)=100', () {
      expect(capFor(AgeTier.high, 400), 100);
    });
    test('中档沿用低档值（160 → 40）', () {
      expect(capFor(AgeTier.mid, 160), 40);
    });
    test('池调低时上限随池下降到 月池×25%', () {
      // 低档天花板 40，但池 100 × 25% = 25 → 取 25
      expect(capFor(AgeTier.low, 100), 25);
    });
  });

  // ── 玄参 2026-09-22 拍板：三档每日专注上限改为阶梯（低 60 / 中 90 / 高 120）──
  // 原实现是「低=中=90、高=60」（中档沿用低档、高年段反而更少），已作废。
  group('每日专注上限三档阶梯', () {
    test('低 60 / 中 90 / 高 120', () {
      expect(kAgeTierParams[AgeTier.low]!.dailyFocusCap, 60);
      expect(kAgeTierParams[AgeTier.mid]!.dailyFocusCap, 90);
      expect(kAgeTierParams[AgeTier.high]!.dailyFocusCap, 120);
    });
    test('年龄越大上限越高（单调递增，锁死阶梯语义）', () {
      expect(
        kAgeTierParams[AgeTier.low]!.dailyFocusCap <
            kAgeTierParams[AgeTier.mid]!.dailyFocusCap,
        isTrue,
      );
      expect(
        kAgeTierParams[AgeTier.mid]!.dailyFocusCap <
            kAgeTierParams[AgeTier.high]!.dailyFocusCap,
        isTrue,
      );
    });
    test('家长端下拉选项 = 三档常量（60/90/120），旧的孤儿值 75 不再出现', () {
      final List<int> options = <int>[
        kDailyFocusCapLow,
        kDailyFocusCapMid,
        kDailyFocusCapHigh,
      ];
      expect(options, <int>[60, 90, 120]);
      expect(options.contains(75), isFalse);
    });
    test('中档不再沿用低档值（U1 例外项）', () {
      expect(kAgeTierParams[AgeTier.mid]!.dailyFocusCap,
          isNot(kAgeTierParams[AgeTier.low]!.dailyFocusCap));
    });
  });

  // ── 玄参 2026-09-22 拍板：周池可调上限 1200 → 500，并收敛为常量（不再写在 UI 里）──
  group('周阳光池可调区间', () {
    test('区间常量 = 50–500', () {
      expect(kWeeklyPoolBudgetMin, 50);
      expect(kWeeklyPoolBudgetMax, 500);
    });
    test('两档默认预算都落在可调区间内（默认值必须合法）', () {
      expect(kPoolBudgetDefaultLow >= kWeeklyPoolBudgetMin, isTrue);
      expect(kPoolBudgetDefaultLow <= kWeeklyPoolBudgetMax, isTrue);
      expect(kPoolBudgetDefaultHigh >= kWeeklyPoolBudgetMin, isTrue);
      expect(kPoolBudgetDefaultHigh <= kWeeklyPoolBudgetMax, isTrue);
    });
    test('周池上限已收到比月池遗留上限小', () {
      expect(kWeeklyPoolBudgetMax < kMonthlyPoolMax, isTrue);
    });
  });
}
