/// 向日葵战士**头顶**大招能量条（P0-03 / P0-09 / P1-01 / P1-02）。
///
/// 两格独立渲染：
/// * 已满格 → 即时点亮（金色实心 + 描边）；未满格 → 显示进度百分比（细填充条）；
/// * 未满格 `fillPercent` 走 domain 纯函数（29→96.7% 等，期望由测试钉死）；
/// * 免费档 [unlocked]==false → 两格改画**灰色虚线空框**（玄参真机反馈 2 二次
///   反馈：纯半透明虚化观感不佳，弃用；去掉 🔒 叠加与全部亮色填充，只保留
///   灰色虚线轮廓，避免「灰框里还有亮色填充」的矛盾；能量仍按口径 12 累计）；
/// * 买断档 [unlocked]==true → 外观逐位不变（金色实心 / 青绿填充 / 实线描边）；
/// * P1-01：点亮过渡走 [AnimatedContainer] 短动效（200ms），不阻塞战斗帧率；
/// * P1-02：语义标签走 i18n（`guard_ultimate_energy_semantics`）—— 去锁后
///   读屏与视觉一致，不再拼 lock 后缀；本文件零中文硬编码。
///
/// 🔴 孩子端零权益 token：只吃 [UltimateEnergy]（domain 实体）+ [unlocked] bool，
///   不读 entitlementProvider / FeatureKey（门控判定在 shared 层下沉）。
library guard_ultimate_energy_bar;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show kMaxUltimateCells;
import 'package:sunflower_time/core/i18n/l10n_scope.dart' show l10nOf;
import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart'
    show UltimateEnergy, fillPercent;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart'
    show GuardArt;
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart'
    show GuardCardLayout;

/// 战士头顶大招能量条。
class GuardUltimateEnergyBar extends StatelessWidget {
  const GuardUltimateEnergyBar({
    required this.energy,
    required this.unlocked,
    required this.uiScale,
    super.key,
  });

  /// 当前大招能量（domain 纯实体）。
  final UltimateEnergy energy;

  /// 是否已解锁（由 shared 门控 helper 派生的中性 bool）。
  final bool unlocked;

  /// 平板放大倍率（与场景卡同一把尺子）。
  final double uiScale;

  /// 未满格内条填充色 —— 🔴 **与大招能量点（入场券能量球，橙黄 0xFFF5B301）区分**：
  /// 改用冷调青绿，避免玄参真机把「大招能量格」和「头顶能量球」看成同一条链路。
  /// 满格点亮态仍走 [GuardArt.ultimateEnergyCellDecoration] 的项目主金色（不刺眼）。
  static const Color _litFill = Color(0xFF3FB6A8);

  /// 免费档虚线描边色 —— 中性灰（与 `garden_pot` 的 dead 色同调），不带任何
  /// 金 / 青绿亮色，避免空框里出现「可用」暗示。
  static const Color _lockedBorder = Color(0xFF9E9E9E);

  /// 免费档虚线线型：实线段 4pt / 空白段 3pt / 线宽 1.2pt。
  static const double _dashWidth = 4.0;
  static const double _dashSpace = 3.0;
  static const double _dashStrokeWidth = 1.2;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final GuardCardLayout layout =
            GuardCardLayout(constraints.maxWidth, uiScale);
        // 🔴 真机反馈 2：免费档不再半透明虚化，改画灰色虚线空框；买断档
        //    原样走 _cell（金色实心 / 青绿填充 / 实线描边），逐位零回归。
        return Stack(
          children: <Widget>[
            for (int i = 0; i < kMaxUltimateCells; i++)
              unlocked
                  ? _cell(context, t, layout, i)
                  : _lockedCell(context, t, layout, i),
          ],
        );
      },
    );
  }

  /// 免费档单格：只画灰色虚线轮廓，不画底色 / 百分比条 / 金色实心。
  Widget _lockedCell(
    BuildContext context,
    AppLocalizations t,
    GuardCardLayout layout,
    int index,
  ) {
    final double percent = fillPercent(energy, index);
    final Rect rect = layout.ultimateBarRect(index);
    final String semantics = t.guard_ultimate_energy_semantics(
      '${index + 1}',
      '${percent.round()}',
    );
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        // 与买断档同口径：读屏仍报真实累计，不再拼 lock 后缀。
        label: semantics,
        child: CustomPaint(
          painter: _DashedCellPainter(
            radius: rect.height / 2,
            color: _lockedBorder,
            strokeWidth: _dashStrokeWidth,
            dashWidth: _dashWidth,
            dashSpace: _dashSpace,
          ),
          // 无 child 的 CustomPaint 默认 preferred size = 0，显式给格子尺寸，
          // 避免宽松约束下虚线框塌缩成零尺寸。
          size: rect.size,
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    AppLocalizations t,
    GuardCardLayout layout,
    int index,
  ) {
    final double percent = fillPercent(energy, index);
    final bool lit = percent >= 100.0;
    final Rect rect = layout.ultimateBarRect(index);
    final BoxDecoration cellDecoration = GuardArt.ultimateEnergyCellDecoration(
      lit: lit,
      radius: rect.height / 2,
    );
    final String semantics = t.guard_ultimate_energy_semantics(
      '${index + 1}',
      '${percent.round()}',
    );

    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        // 去锁后读屏文案与视觉一致：不再拼 guard_ultimate_lock_semantics。
        label: semantics,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            // 点亮底色走 AnimatedContainer（P1-01 200ms 动效）；描边拆到
            // DecoratedBox 叠加层 —— 保留「卡根无外框」布局护栏（旧测试扫描
            // 卡内所有 Container 的 border，AnimatedContainer 内部也会落到
            // Container 上，故不能把 border 放进 AnimatedContainer.decoration）。
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: cellDecoration.color,
                  borderRadius: BorderRadius.circular(rect.height / 2),
                ),
              ),
            ),
            // 未满格：按百分比填充的内条（即时刷新；满格整条已点亮）。
            if (!lit)
              FractionallySizedBox(
                widthFactor: (percent / 100).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: _litFill.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(rect.height / 2),
                  ),
                ),
              ),
            // 单格描边（能量条 UI 自身，不是场景卡外框）。
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: cellDecoration.border,
                  borderRadius: BorderRadius.circular(rect.height / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆角矩形虚线描边画师（Flutter 无内置 dashed border，且本轮不新增依赖）。
///
/// 沿 [RRect] 路径按 [dashWidth] / [dashSpace] 逐段 `Canvas.drawPath`，圆角处
/// 由 `PathMetric.extractPath` 自动沿弧长切分，不会出现直角虚线的折角断裂。
class _DashedCellPainter extends CustomPainter {
  const _DashedCellPainter({
    required this.radius,
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
  });

  final double radius;
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCellPainter oldDelegate) =>
      radius != oldDelegate.radius ||
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      dashWidth != oldDelegate.dashWidth ||
      dashSpace != oldDelegate.dashSpace;
}
