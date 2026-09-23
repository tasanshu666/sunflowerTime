import 'package:sunflower_time/domain/entities/sunlight_entry.dart';

/// 阳光账本仓储抽象（§2.1 / §3.2）。append-only 账本；所有扣减/产出均经此。
abstract class SunlightRepository {
  /// 追加一条账本记录（earn / redeem / queueRelease）。返回写入后的余额。
  Future<double> append(SunlightEntry entry);

  /// 当前余额（sum(net)）。
  Future<double> balance();

  /// 全部账本记录（阳光来源记录页用，按时间倒序）。
  Future<List<SunlightEntry>> all();

  /// 某日净产出（软顶校验用，§3.2）。
  ///
  /// 注意：按**全部类型**求和（earn / redeem / plant / queueRelease）。任务打卡
  /// 的软顶差额核算**不可**复用本方法，请用 [earnGrossOnDay] / [earnNetOnDay]。
  Future<double> dayNet(String dayKey);

  /// 某日 **earn 类型** 的 gross（毛产出）合计（任务打卡软顶核算用，§4.5）。
  Future<double> earnGrossOnDay(String dayKey);

  /// 某日 **earn 类型** 的 net（实际发放）合计（任务打卡软顶核算用，§4.5）。
  Future<double> earnNetOnDay(String dayKey);

  /// 已核销总额对账（§3.2）。
  Future<double> verifiedRedeemTotal();

  /// 指定 refType 在某日的净阳光合计（家长赠予日上限核算用，§4.5）。
  Future<double> netByRefTypeOnDay(String refType, String dayKey);

  /// 指定 refType 在某月的净阳光合计（按 dayKey 前缀匹配 monthKey，月上限核算用）。
  Future<double> netByRefTypeInMonth(String refType, String monthKey);

  /// 指定 refType + refId 在某日的记账条数（植物每日养护次数上限，M3 修订）。
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String dayKey,
  );

  /// 指定 refType + refId 自 [since]（含）以来的记账条数（枯萎后养护恢复次数核算，2026-09-23）。
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  );

  /// 指定 refType + refId 的最近一次记账时间（浇水最小间隔，M3 修订）。
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId);
}
