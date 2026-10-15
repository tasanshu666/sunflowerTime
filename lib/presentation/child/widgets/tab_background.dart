/// C44 tab 整页背景组件（2026-10-09 玄参「上半场景+下半留白」底图）。
///
/// 用法：包住 tab 页内容，`BoxFit.cover` 铺满（含 shell 透明 AppBar
/// 底下——外壳对今日/成长/商店开了 `extendBodyBehindAppBar`，见 child_shell_page）。
///  · 图片加载失败 → 回退 [fallbackColor] 纯色（原奶油底），**绝不阻塞内容**；
///  · 下半留白区即内容区，白卡直接浮在上面（与设计稿分层一致）。
///
/// ## C64（2026-10-13 玄参 iPad 实测反馈）——「背景上半部分留的太多」
/// 平板比底图「宽得多」时 cover 只能按宽度放大 → 竖向裁掉 35%~45%；原先固定
/// `topCenter` 会把**上半段场景整体拉大**、卡片压在插画上。现改为：按
/// [panelTargetRatio] 算出垂直对齐值，使底图「场景 ↔ 留白」分界线正好落在该屏高比例处。
///
/// ⚠️ **C67（2026-10-13 晚）起本参数与「卡片起点」不再必为同一个值**：
/// 成长/商店两页仍是卡片起点（C64 口径不变）；但**今日页**玄参要求「卡片再下移、
/// 底图保持不动」→ 今日传 `kTodayBgPanelTargetRatio`（0.37，冻结），而卡片起点是
/// `kTodayCardTopRatio`（0.40）。故这里**不能**再假定「本参数 = 页面卡片起点」。
///
/// ⚠️ 三条边界（都由 [tabBgAlignmentY] 保证，**手机端零回归**）：
///  ① **仅平板**做对齐（`shortestSide ≥ 600`）：手机端恒 `topCenter`，与原像素一致；
///  ② 竖向没有可移动余量（绘制高 ≈ 容器高，如手机上的商店底图）→ 退回 `topCenter`；
///  ③ 余量不足（想往下移但无处可移）→ 对齐值钳到 `-1` = `topCenter`。
library tab_background;

import 'package:flutter/material.dart';

import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/shared/tab_bg_layout.dart';

import 'growth_icons.dart';

class TabBackground extends StatelessWidget {
  /// 底图 [DecoratedBox] 的 Key。
  ///
  /// 玄参纪律「AI 不截图不自查 UI」→ 布局只能靠**可度量的断言**证明
  /// （`test/m3/tab_bg_alignment_test.dart` 用本 Key 读回
  /// `DecorationImage.alignment` 反算「分界线是否落在卡片起点」）。
  static const Key decorationKey = Key('tab_background_decoration');

  final String asset;

  /// 底图「场景 ↔ 留白」分界线要对齐到的**屏高比例**（本页在屏幕坐标系下的目标 y）。
  ///
  /// 成长 `kGrowthListTopRatio` / 商店 `kStoreListTopRatio` = 卡片起点（C64 口径：
  /// 分界线落在卡片起点，两者同源）。
  /// **今日 `kTodayBgPanelTargetRatio`（0.37）≠ 卡片起点 `kTodayCardTopRatio`（0.40）**
  /// —— C67 有意留出 3% 屏高的奶油呼吸带，此时传的是**底图锚点**、不是卡片起点。
  final double panelTargetRatio;

  /// 图片缺失/解码失败时的兜底底色（各页原奶油底 / 白底）。
  final Color fallbackColor;

  final Widget child;

  const TabBackground({
    super.key,
    required this.asset,
    required this.panelTargetRatio,
    required this.fallbackColor,
    required this.child,
  });

  /// 底图几何 `(源尺寸, 分界线归一化 y)`；未登记的图返回 null（→ 退回 topCenter）。
  ///
  /// 常量本体在 `lib/shared/tab_bg_layout.dart`（由 `tools/probe_tab_bg_panel_top.py`
  /// 实测），换底图必须同步。
  static (Size, double)? geometryOf(String asset) => switch (asset) {
        kTodayBgAsset => (kTodayBgSrcSize, kTodayBgPanelTopFraction),
        kGrowthBgAsset => (kGrowthBgSrcSize, kGrowthBgPanelTopFraction),
        kStoreBgAsset => (kStoreBgSrcSize, kStoreBgPanelTopFraction),
        _ => null,
      };

  /// 底图分界线在**容器坐标系**下的 y（body 顶部 = 屏顶 ⇒ 数值等于屏幕 y）。
  ///
  /// 与 [build] 走**同一套**几何（[geometryOf] + [tabBgAlignmentY] + [panelTopScreenY]）
  /// 反算，保证「页面读到的分界线」与「底图真正画出的分界线」逐像素同源 —— 页面
  /// 不再自己二手推算 cover 结果（C64 起这类重复口径已多次引起对不齐）。
  ///
  /// ⚠️ 手机端恒 `topCenter`（C64 手机零像素回归）→ 分界线落在 cover 几何处，
  /// **不一定**等于 [panelTargetRatio] × 屏高：这正是「今日页卡片骑在面板圆角上」
  /// 的根因（C67 的 0.40 是按「分界线 + 3% 呼吸带」标定的，平板才成立）。
  ///
  /// 底图未登记几何 / 约束无界时返回 `-inf` —— 调用方应退回冻结的卡片起点。
  static double panelLineY({
    required BuildContext context,
    required Size box,
    required String asset,
    required double targetRatio,
  }) {
    final (Size, double)? geo = geometryOf(asset);
    if (geo == null || !box.width.isFinite || !box.height.isFinite) {
      return double.negativeInfinity;
    }
    // 与 build 同款闸门：仅平板做对齐，手机恒 topCenter。
    double alignmentY = -1;
    if (isTabletOf(context)) {
      final double? a = tabBgAlignmentY(
        box: box,
        src: geo.$1,
        panelTopFraction: geo.$2,
        targetY: MediaQuery.sizeOf(context).height * targetRatio,
      );
      if (a != null) alignmentY = a;
    }
    return panelTopScreenY(
      box: box,
      src: geo.$1,
      panelTopFraction: geo.$2,
      alignmentY: alignmentY,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ 必须量到**真实容器尺寸**才能算 cover 绘制高；body 恒为紧约束，
    // 但保险起见对无界约束直接退回 topCenter（不猜）。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final (Size, double)? geo = geometryOf(asset);
        Alignment alignment = Alignment.topCenter;
        if (geo != null &&
            c.hasBoundedWidth &&
            c.hasBoundedHeight &&
            isTabletOf(context)) {
          final double? a = tabBgAlignmentY(
            box: c.biggest,
            src: geo.$1,
            panelTopFraction: geo.$2,
            // 卡片起点是**屏幕坐标系**（body 顶部 = 屏顶，见 shell 的
            // extendBodyBehindAppBar），故用 MediaQuery 屏高而非容器高。
            targetY: MediaQuery.sizeOf(context).height * panelTargetRatio,
          );
          if (a != null) alignment = Alignment(0, a);
        }
        return DecoratedBox(
          key: decorationKey,
          decoration: BoxDecoration(
            color: fallbackColor,
            image: DecorationImage(
              image: AssetImage(asset),
              fit: BoxFit.cover,
              alignment: alignment,
              onError: (Object _, StackTrace? __) {
                // 静默：兜底色已由 decoration.color 承载，不打日志刷屏。
              },
            ),
          ),
          child: child,
        );
      },
    );
  }
}
