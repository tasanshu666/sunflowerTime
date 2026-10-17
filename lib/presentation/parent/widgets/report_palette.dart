/// 专注报告 v2 · 配色单点（C76 / T03）。
///
/// 为什么单独成文件：报告段的六块内容（期间条 / Hero / 趋势 / 稳定性 / 热力图 /
/// 护眼）必须**同一套色值**，否则深色模式下必然出现「一半看得清、一半看不清」。
/// 本文件把老页 `parent_report_page.dart`（**C87 已删除**）的私有 `_ReportPalette`
/// （`:28-95`）**逐值搬出**（色值一字未改，仅从私有类变为公共类），供新组件共用。
///
/// 🔴 纪律：
///  · **色值不得改**——老页与新报告段要视觉一致（`test/m3` 与真机观感都依赖它）；
///  · 本文件**不含任何权益标识符**（见 `test/qa/entitlement_gate_guard_test.dart`），
///    门控判定只在 `focus_report_section.dart` 一处；
///  · 取值一律走 [ReportPalette.of]（随主题亮度切换），**禁止**内联 `Colors.*` 硬编码，
///    否则深色模式又会「深字压深卡」。
library report_palette;

import 'package:flutter/material.dart';

/// 报告配色（随主题亮度切换，深浅两套都保持可读对比度）。
///
/// 字段与老页 `_ReportPalette` 一一对应：
/// [ink] 主文字 / 轴标签；[accent] 家长端主色；[valid] 有效专注日；
/// [idle] 未构成有效专注日；[warn] / [good] 结论语分档；[heroGradient] /
/// [heroBorder] 顶部主卡；[softBg] 中性浅底块。
class ReportPalette {
  /// 主要文字 / 轴标签。
  final Color ink;

  /// 家长端主色（当前周、标题色条、选中档底色）。
  final Color accent;

  /// 有效专注日（达标）。
  final Color valid;

  /// 未构成有效专注日（灰柱 / 空格子）。
  final Color idle;

  /// 结论语按稳定性分档取色（偏低）。
  final Color warn;

  /// 结论语按稳定性分档取色（良好）。
  final Color good;

  /// 顶部主卡渐变。
  final List<Color> heroGradient;

  /// 顶部主卡描边。
  final Color heroBorder;

  /// 中性浅底块（空数据提示、图例底等）。
  final Color softBg;

  const ReportPalette({
    required this.ink,
    required this.accent,
    required this.valid,
    required this.idle,
    required this.warn,
    required this.good,
    required this.heroGradient,
    required this.heroBorder,
    required this.softBg,
  });

  /// 浅色一套（与老页 `_light` 逐值相等）。
  static const ReportPalette _light = ReportPalette(
    ink: Color(0xFF27454F),
    accent: Color(0xFF3F7F99),
    valid: Color(0xFF4A9A6B),
    idle: Color(0xFFC3D4DB),
    warn: Color(0xFFC77B2B),
    good: Color(0xFF3E8259),
    heroGradient: <Color>[Color(0xFFF6E7B4), Color(0xFFEAF2F5)],
    heroBorder: Color(0xFFE2D6A8),
    softBg: Color(0xFFF1F6F8),
  );

  /// 深色一套（与老页 `_dark` 逐值相等）：文字提亮、柱体降饱和。
  static const ReportPalette _dark = ReportPalette(
    ink: Color(0xFFDCE9EE),
    accent: Color(0xFF7CBCD4),
    valid: Color(0xFF6FCB96),
    idle: Color(0xFF4E626C),
    warn: Color(0xFFE0A85C),
    good: Color(0xFF6FCB96),
    heroGradient: <Color>[Color(0xFF3B3524), Color(0xFF22313A)],
    heroBorder: Color(0xFF4C4530),
    softBg: Color(0xFF1E2A31),
  );

  /// 取当前主题亮度对应的那一套（唯一入口）。
  static ReportPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  /// 带透明度派生（统一入口，避免各处各写一个 opacity）。
  ///
  /// 用 `withValues`（非 deprecated 的 `withOpacity`），行为等价。
  Color inkAt(double opacity) => ink.withValues(alpha: opacity);
}
