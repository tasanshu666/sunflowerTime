import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';

/// 埋点仓储抽象（§2.1 / §6 / §8.3）。
abstract class TrackingRepository {
  Future<void> track(TrackingEvent event);
  Future<List<TrackingEvent>> eventsOfType(TrackingType type);
}
