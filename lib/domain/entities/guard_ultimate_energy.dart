/// 向日葵守卫 · 大招能量实体与纯状态转移函数（纯 Dart / 零 Flutter / 零 drift / 零 CJK）。
///
/// 与旧入场券能量 [GuardEnergy] **完全独立**：另起实体、另起 prefs key
/// （见 `GuardUltimateEnergyPrefsStore`），不碰 `balance` / `creditedSessionIds`。
///
/// 状态模型（PRD §5.1）：
/// ```
/// UltimateEnergy = { filledCells: 0..2, fractionMin: 0..29 }
/// ```
/// 不变量（架构 §1.2，不可绕开）：
/// * `0 <= filledCells <= 2`；
/// * `0 <= fractionMin <= 29`；
/// * `filledCells == 2 => fractionMin == 0`（满 2 格那一刻丢弃溢出、强制归 0）。
///
/// [totalFocusMin] 仅作累计总量记录 / 调试统计（便于追查"到底攒了多少分钟"），
/// **不参与** `filledCells/fractionMin` 的状态派生；满 2 格后停止增长（PRD §10-B1）。
/// 状态机以 `filledCells/fractionMin` 为唯一真源。
library guard_ultimate_energy;

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 大招能量快照（不可变）。
class UltimateEnergy {
  const UltimateEnergy({
    this.filledCells = 0,
    this.fractionMin = 0,
    this.totalFocusMin = 0.0,
  });

  /// 满格数上限（= [kMaxUltimateCells]，架构 §1.2）。
  static const int maxCells = kMaxUltimateCells;

  /// 每格所需累计专注分钟（= [kMinPerUltimateCell]）。
  static const int minutesPerCell = kMinPerUltimateCell;

  /// 已攒满格数（0..2）。
  final int filledCells;

  /// 当前未满格的零头分钟（0..29；满 2 格时恒 0）。
  final int fractionMin;

  /// 累计专注分钟总量（仅统计，满 2 格后停止增长）。
  final double totalFocusMin;

  /// 空能量（两格均空）。
  static const UltimateEnergy empty = UltimateEnergy();

  /// 是否已满（2 格）。
  bool get isFull => filledCells >= maxCells;

  /// 🔒 语义标签的 i18n key（P1-02：领域层零 CJK，只返回 key，UI 层解析）。
  String get lockSemanticsKey => kUltimateLockSemanticsKey;

  /// 稳定 JSON（prefs 持久化，字段与架构 §3.3 一致）。
  Map<String, Object?> toJson() => <String, Object?>{
        'filledCells': filledCells,
        'fractionMin': fractionMin,
        'totalFocusMin': totalFocusMin,
      };

  /// 宽容解码：坏数据降级为空能量，且强制满足不变量。
  factory UltimateEnergy.fromJson(Map<String, Object?> json) {
    final int cells = _clampInt(json['filledCells'], 0, maxCells);
    int frac = _clampInt(json['fractionMin'], 0, minutesPerCell - 1);
    if (cells >= maxCells) frac = 0;
    final Object? rawTotal = json['totalFocusMin'];
    final double total = rawTotal is num && rawTotal.isFinite && rawTotal >= 0
        ? rawTotal.toDouble()
        : 0.0;
    return UltimateEnergy(
      filledCells: cells,
      fractionMin: frac,
      totalFocusMin: total,
    );
  }

  @override
  String toString() =>
      'UltimateEnergy(filled=$filledCells, frac=$fractionMin, total=$totalFocusMin)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UltimateEnergy &&
          other.filledCells == filledCells &&
          other.fractionMin == fractionMin &&
          other.totalFocusMin == totalFocusMin;

  @override
  int get hashCode => Object.hash(filledCells, fractionMin, totalFocusMin);
}

int _clampInt(Object? value, int min, int max) {
  if (value is! int) return min;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// 攒能量（架构 §1.2 定死点②）：返回新状态；池满时原样返回（溢出丢弃）。
///
/// * 本次 [focusMin] 向下取整为整分钟入账（架构 U-2）；
/// * 每满 30 分钟进位一格，满 2 格那一刻 `frac` 强制归 0；
/// * [totalFocusMin] 累加原始 double（满 2 格早返回时不增长）。
UltimateEnergy credit(UltimateEnergy e, double focusMin) {
  if (e.filledCells >= kMaxUltimateCells) return e;
  final double safeMin =
      focusMin.isFinite && focusMin > 0 ? focusMin : 0.0;
  int cells = e.filledCells;
  int frac = e.fractionMin + safeMin.floor();
  while (frac >= kMinPerUltimateCell && cells < kMaxUltimateCells) {
    frac -= kMinPerUltimateCell;
    cells += 1;
  }
  if (cells >= kMaxUltimateCells) frac = 0;
  return UltimateEnergy(
    filledCells: cells,
    fractionMin: frac,
    totalFocusMin: e.totalFocusMin + safeMin,
  );
}

/// 释放：只扣整格，`fractionMin` 不动（PRD §5.1）。
UltimateEnergy spend(UltimateEnergy e) => e.filledCells == 0
    ? e
    : UltimateEnergy(
        filledCells: e.filledCells - 1,
        fractionMin: e.fractionMin,
        totalFocusMin: e.totalFocusMin,
      );

/// 第 [cellIndex] 格的填充百分比（0.0..100.0，保留一位小数）。
///
/// 满格恒 100%；未满格取 `fractionMin / 30`；已点亮格之后的空格为 0%。
/// 🔴 必须先 ×10 再 round 再 ÷10（架构 §1.2 / §8-S2）：先 round 会把
/// 29→9.7（错），正确 29→96.7。
double fillPercent(UltimateEnergy e, int cellIndex) =>
    cellIndex < e.filledCells
        ? 100.0
        : (cellIndex == e.filledCells && e.filledCells < kMaxUltimateCells)
            ? (e.fractionMin * 100 / kMinPerUltimateCell * 10).roundToDouble() /
                10
            : 0.0;

/// 不变量断言（架构 §1.2）：`0<=cells<=2 ∧ 0<=frac<=29 ∧ (cells==2 ⇒ frac==0)`。
bool isValid(UltimateEnergy e) =>
    e.filledCells >= 0 &&
    e.filledCells <= kMaxUltimateCells &&
    e.fractionMin >= 0 &&
    e.fractionMin < kMinPerUltimateCell &&
    !(e.filledCells == kMaxUltimateCells && e.fractionMin != 0);
