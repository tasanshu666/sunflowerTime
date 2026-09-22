import 'package:sunflower_time/domain/entities/weekly_pool.dart';

/// 周阳光池仓储抽象（§2.1 / §3.2）。
abstract class WeeklyPoolRepository {
  /// 按 weekKey 读取当周池（不存在返回 null）。
  Future<WeeklyPool?> get(String weekKey);

  /// 写入 / 更新当周池（按 weekKey 主键 upsert）。
  Future<void> upsert(WeeklyPool pool);

  /// 返回 fromKey..toKey 之间的所有周键（含端点），用于跨周补跑。
  List<String> weeksBetween(String fromKey, String toKey);
}
