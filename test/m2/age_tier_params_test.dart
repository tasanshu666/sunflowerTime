/// 三档 AgeTier 参数单点测试（§1.3 / §3.2；**C90-C 修订**）。
///
/// C90-C（玄参 2026-10-18 拍板）：
///  · 年级分界统一（12 岁归中）：**≤8 低 / 9–12 中 / ≥13 高**（8 / 12 / 13 边界钉死）；
///  · 周阳光池默认额度：低 **300** / 中 **600** / 高**不限额**（哨兵 0）；
///    **同日二次修订（玄参）**：200/400 → 300/600，且家长手动设额入口已删除
///    （原「可调区间 50–500」常量 kWeeklyPoolBudgetMin/Max 随控件删除一并移除）；
///  · 自动放行（C5 双条件 / capFor）已全删 —— 原 capFor 分组移除。
library age_tier_params_test;
///
/// 纯 Dart：仅依赖 domain/entities 与 core/constants，无 Flutter 依赖。
import 'package:sunflower_time/core/constants/age_tier_params.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

void main() {
  group('tierForAge 分档映射（C90-C：12 岁归中）', () {
    test('≤8 岁 = low（8 为边界）', () {
      expect(tierForAge(6), AgeTier.low);
      expect(tierForAge(7), AgeTier.low);
      expect(tierForAge(8), AgeTier.low);
    });
    test('9–12 岁 = mid（9 / 12 均为边界）', () {
      expect(tierForAge(9), AgeTier.mid);
      expect(tierForAge(10), AgeTier.mid);
      expect(tierForAge(11), AgeTier.mid);
      expect(tierForAge(12), AgeTier.mid);
    });
    test('≥13 岁 = high（13 为边界）', () {
      expect(tierForAge(13), AgeTier.high);
      expect(tierForAge(14), AgeTier.high);
      expect(tierForAge(18), AgeTier.high);
    });
    test('越界取最近端点', () {
      expect(tierForAge(0), AgeTier.low); // 下越界 → low
      expect(tierForAge(5), AgeTier.low);
      expect(tierForAge(99), AgeTier.high);
    });
    test('C90-C 关键回归：12 岁不再落高档（原口径 11–12 = high 已作废）', () {
      expect(tierForAge(12), isNot(AgeTier.high));
      expect(tierForAge(12), AgeTier.mid);
    });
  });

  group('ageTierK 分龄系数', () {
    test('低1.0 / 中1.2 / 高1.5', () {
      expect(ageTierK(AgeTier.low), 1.0);
      expect(ageTierK(AgeTier.mid), 1.2);
      expect(ageTierK(AgeTier.high), 1.5);
    });
  });

  // ── C90-C：自动放行（C5 双条件 / capFor）已全删，原 capFor 分组移除 ──────

  // ── 玄参 2026-09-22 拍板：三档每日专注上限改为阶梯（低 60 / 中 90 / 高 120）──
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

  // ── C90-C：周阳光池默认额度（低 300 / 中 600 / 高不限额；同日二次修订）──
  group('周阳光池默认额度（C90-C 同日二次修订）', () {
    test('低 300 / 中 600（中档不再沿用低档值）', () {
      expect(kPoolBudgetDefaultLow, 300);
      expect(kPoolBudgetDefaultMid, 600);
      expect(kAgeTierParams[AgeTier.low]!.poolBudgetDefault,
          kPoolBudgetDefaultLow);
      expect(kAgeTierParams[AgeTier.mid]!.poolBudgetDefault,
          kPoolBudgetDefaultMid);
    });
    test('高年级默认不设上限（不限额哨兵 0，不预置额度）', () {
      expect(kWeeklyPoolBudgetUnlimited, 0);
      expect(kAgeTierParams[AgeTier.high]!.poolBudgetDefault,
          kWeeklyPoolBudgetUnlimited);
    });
    test('低 / 中两档默认值有效且不等于不限额哨兵（无家长编辑入口的守卫）', () {
      // C90-C 同日二次修订：手动设额控件删除后预算完全按年级默认值走，
      // 默认值必须是有意义的限额（> 哨兵 0），否则低/中年级将退化为不限额。
      expect(kPoolBudgetDefaultLow > kWeeklyPoolBudgetUnlimited, isTrue);
      expect(kPoolBudgetDefaultMid > kWeeklyPoolBudgetUnlimited, isTrue);
      expect(kPoolBudgetDefaultMid, isNot(kPoolBudgetDefaultLow));
    });
  });
}
