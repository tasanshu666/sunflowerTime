/// C64 tab 整页底图「场景 ↔ 留白」**对齐几何的纯函数 + 实测常量**（2026-10-13）。
///
/// ## 为什么需要
/// 「今日 / 成长 / 商店」三页是**整页底图**（`assets/backgrounds/*.webp`），设计稿口径
/// 是「上半场景 + 下半留白面板」，页面里的白卡浮在留白区上、起点为 `屏高 × 比例`
/// （今日 0.42 / 成长 0.34 / 商店 0.41）。
///
/// 手机（如 402×874，长宽比 ≈0.46）与底图长宽比接近 → `BoxFit.cover` 竖向几乎不裁，
/// 「分界线」天然落在卡片起点附近（这正是当年手调比例的依据）。
/// **平板**（如 834×1210，≈0.69）比底图「宽得多」→ cover 只能按**宽度**放大
/// （绘制高 ≈ 容器高 × 1.66）→ 竖向要裁掉 35%~45%；原先固定 `topCenter` ⇒
/// 看到的是「上半段场景」被整体拉大、卡片反而压在插画上
/// （玄参 2026-10-13 iPad 实测原话：「背景素材上半部分留的太多了」）。
///
/// ## 口径（C64）
/// 让**分界线落在页面卡片的起点**：`targetY` 由调用方按屏高比例给出
/// （与页面里 `SizedBox(height: 屏高 × ratio)` **同源**）→ 改卡片位置时底图自动跟随。
/// 竖向没有可移动余量（绘制高 ≈ 容器高）时返回 null，调用方退回 `topCenter`。
///
/// ⚠️ 本文件**不 import flutter/material**（只依赖 `dart:ui`），可被纯 dart 测试直接调用
/// —— 与 [garden_background_layout]（花园底图几何）同款做法。
library tab_bg_layout;

import 'dart:math' as math;
import 'dart:ui';

// ───────────────────────────────────────────────────────────────────────────
// 实测常量（2026-10-13）
//
// 源尺寸：`sips -g pixelWidth -g pixelHeight assets/backgrounds/*.webp`。
// 分界线：「场景 ↔ 留白」分界的**归一化 y**，由 `tools/probe_tab_bg_panel_top.py`
//   逐行统计（留白面板沿宽度方向 std ≈14~20，场景区 std > 40）实测取得。
// ⚠️ 换底图必须重跑该脚本并同步这几个常量，否则卡片会压到插画上。
// ───────────────────────────────────────────────────────────────────────────

/// 「今日」底图源尺寸（1440×3200，长宽比 0.450）。
const Size kTodayBgSrcSize = Size(1440, 3200);

/// 「今日」底图分界线（源图 y 1278 / 3200）。其下为平坦奶油留白面板。
const double kTodayBgPanelTopFraction = 0.399;

/// 「成长」底图源尺寸（1408×3104，长宽比 0.454）。
const Size kGrowthBgSrcSize = Size(1408, 3104);

/// 「成长」底图分界线（源图 y 1081 / 3104）——书桌插画下沿，其下有 ~70px 柔和渐变带。
const double kGrowthBgPanelTopFraction = 0.348;

/// 「商店」底图源尺寸（1600×2848，长宽比 0.562，三张里最「矮胖」）。
const Size kStoreBgSrcSize = Size(1600, 2848);

/// 「商店」底图分界线（源图 y 1318 / 2848）——货架下沿。
const double kStoreBgPanelTopFraction = 0.463;

/// `BoxFit.cover` 下底图的**实际绘制高**（恒 ≥ 容器高，超出部分被裁）。
double coverDrawnHeight({required Size box, required Size src}) =>
    src.height * math.max(box.width / src.width, box.height / src.height);

/// 让底图分界线（`panelTopFraction × 绘制高`）落到 [targetY] 所需的**垂直对齐值**。
///
/// 返回 `Alignment.y ∈ [-1, 1]`：`-1` = topCenter（原行为）、`0` = center、`1` = bottomCenter；
/// 竖向**没有可移动余量**（`绘制高 ≈ 容器高`，例如手机上的商店底图按高度绑定）
/// 时返回 `null` → 调用方退回 topCenter。
///
/// 推导：`DecorationImage` 的 `alignment` 经 `Alignment.inscribe` 变成顶部偏移
/// `top = (容器高 − 绘制高) × (a + 1) / 2`（`slack = 容器高 − 绘制高 ≤ 0`），
/// 令 `top = targetY − 分界线 × 绘制高` 即可解出 `a`；越界时钳到 `[-1, 1]`
/// （钳到 -1 即「想往下移但无处可移」→ 保持 topCenter，正是手机端的情形）。
double? tabBgAlignmentY({
  required Size box,
  required Size src,
  required double panelTopFraction,
  required double targetY,
}) {
  final double drawnH = coverDrawnHeight(box: box, src: src);
  final double slack = box.height - drawnH;
  // 竖向无裁剪余量（±1px 内视为相等）→ 对齐无意义。
  if (slack > -1.0) return null;
  final double wantedTop = targetY - panelTopFraction * drawnH;
  return (2 * (wantedTop / slack) - 1).clamp(-1.0, 1.0);
}

/// 给定对齐值下底图分界线**实际落在的屏幕 y**（容器坐标系）。
///
/// 供测试反算断言（生产代码只用 [tabBgAlignmentY]）。
double panelTopScreenY({
  required Size box,
  required Size src,
  required double panelTopFraction,
  required double alignmentY,
}) {
  final double drawnH = coverDrawnHeight(box: box, src: src);
  final double top = (box.height - drawnH) * (alignmentY + 1) / 2;
  return top + panelTopFraction * drawnH;
}
