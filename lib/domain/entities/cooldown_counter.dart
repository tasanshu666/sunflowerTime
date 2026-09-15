import 'package:sunflower_time/domain/entities/enums.dart';

/// 冷却计数器（§3.1 cooldown_counter）。频次上限主阀门（§4.8 E6）。
class CooldownCounter {
  final String templateId;
  final CooldownPeriod period; // 周 / 月
  final int usedCount;

  const CooldownCounter({
    required this.templateId,
    required this.period,
    required this.usedCount,
  });
}
