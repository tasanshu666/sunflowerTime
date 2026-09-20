import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';

/// 埋点仓储抽象（§2.1 / §6 / §8.3）。
abstract class TrackingRepository {
  Future<void> track(TrackingEvent event);
  Future<List<TrackingEvent>> eventsOfType(TrackingType type);

  /// 导出区间内事件为 JSONL 字符串（每行一条 JSON，'\n' 拼接）。
  /// 落盘由上层决定，此处只返回内容。
  Future<String> exportJsonl(DateTime from, DateTime to);
}
