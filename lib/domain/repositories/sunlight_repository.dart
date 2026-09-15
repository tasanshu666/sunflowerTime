import 'package:sunflower_time/domain/entities/sunlight_entry.dart';

/// 阳光账本仓储抽象（§2.1 / §3.2）。append-only 账本；所有扣减/产出均经此。
abstract class SunlightRepository {
  /// 追加一条账本记录（earn / redeem / queueRelease）。返回写入后的余额。
  Future<double> append(SunlightEntry entry);

  /// 当前余额（sum(net)）。
  Future<double> balance();

  /// 某日净产出（软顶校验用，§3.2）。
  Future<double> dayNet(String dayKey);

  /// 已核销总额对账（§3.2）。
  Future<double> verifiedRedeemTotal();
}
