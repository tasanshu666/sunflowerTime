import 'package:sunflower_time/domain/entities/enums.dart';

/// 阳光账本单行（§3.1 sunlight_ledger，append-only）。
/// 设计铁律（§3.2）：单一账本 + 独立月池，三套规则可追溯对账。
class SunlightEntry {
  final String id;
  final DateTime ts;
  final SunlightType type;
  final double gross; // 原始 S（产出侧不乘 K）
  final double net; // 有效阳光（signed：earn 为正，redeem 为负）
  final double balanceAfter;
  final String? refType;
  final String? refId;
  final String dayKey;

  const SunlightEntry({
    required this.id,
    required this.ts,
    required this.type,
    required this.gross,
    required this.net,
    required this.balanceAfter,
    this.refType,
    this.refId,
    required this.dayKey,
  });
}
