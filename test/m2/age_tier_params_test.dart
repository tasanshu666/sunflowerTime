/// 三档 AgeTier 参数单点测试（§1.3 / §3.2）。
///
/// 纯 Dart：仅依赖 domain/entities 与 core/constants，无 Flutter 依赖。
import 'package:sunflower_time/core/constants/age_tier_params.dart';
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
}
