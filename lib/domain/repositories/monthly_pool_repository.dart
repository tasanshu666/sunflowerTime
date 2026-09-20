import 'package:sunflower_time/domain/entities/monthly_pool.dart';

/// 月度池仓储抽象（§2.1 / §3.2）。
abstract class MonthlyPoolRepository {
  /// 按 monthKey 读取当月池（不存在返回 null）。
  Future<MonthlyPool?> get(String monthKey);

  /// 写入 / 更新当月池（按 monthKey 主键 upsert）。
  Future<void> upsert(MonthlyPool pool);

  /// 返回 fromKey..toKey 之间的所有月份键（含端点），用于跨月补跑。
  List<String> monthsBetween(String fromKey, String toKey);
}
