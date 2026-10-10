/// 花园背景美术图的**几何映射纯函数**（2026-09-24 花园页 v3 改造）。
///
/// ## 为什么单独一个文件
/// 背景图 `assets/garden/background.png` 用 `BoxFit.cover` 铺满 body：图片比容器更
/// 「瘦长」时左右铺满、上下溢出；更「宽扁」时上下铺满、左右溢出。木牌热区与「花盆区
/// 底界」都要跟着这张图的**实际绘制矩形**走，否则换个屏幕比例就会错位。
///
/// 故把这些映射抽成**纯函数**：只依赖 `dart:ui` 的 `Rect` / `Size` 与 `dart:math`，
/// **不引入 flutter/material**，可被纯 dart 测试直接调用（无需 widget 测试宿主）。
library garden_background_layout;

import 'dart:math' as math;
import 'dart:ui';

/// 花园背景美术图的源尺寸（实测 `assets/garden/background.png` = 1056×2336，勿改）。
///
/// 说明：玄参 2026-09-23 晚更换了背景图（旧图 1161×2560），本尺寸与下方木牌标定、
/// 花盆区底界比例**成套**更新——改其一必改其二，否则木牌热区与菜地上沿整体偏移。
const Size kGardenBackgroundSize = Size(1056, 2336);

/// `BoxFit.cover` 下图片在容器内的**实际绘制矩形**（等比放大 + 居中，可能溢出容器）。
///
/// 算法与 `BoxFit.cover` 一致：
///  · `scale = max(box.width / src.width, box.height / src.height)`；
///  · 绘制尺寸 = 源尺寸 × scale；
///  · origin 居中（可为负值 → 上下或左右溢出容器）。
Rect gardenCoverRect(Size box) {
  final double scale = math.max(
    box.width / kGardenBackgroundSize.width,
    box.height / kGardenBackgroundSize.height,
  );
  final Size drawn = Size(
    kGardenBackgroundSize.width * scale,
    kGardenBackgroundSize.height * scale,
  );
  return Rect.fromLTWH(
    (box.width - drawn.width) / 2,
    (box.height - drawn.height) / 2,
    drawn.width,
    drawn.height,
  );
}

/// 木牌（背景图左下角木牌）在**源图中的归一化矩形**（2026-10-06 重新标定，勿改）：
/// 源图像素 x 54~272 / y 1507~1659（牌面实测 x 58~268 / y 1513~1652，四周留 ~5px
/// 点按余量；320 逻辑宽屏下热区高仍 ≥44）→
///   left = 54/1056 = 0.0511, top = 1507/2336 = 0.6451,
///   right = 272/1056 = 0.2576, bottom = 1659/2336 = 0.7102。
///
/// 标定方式：PIL 逐像素扫「浅木色」边界 + 叠网格目视复核（玄参 2026-10-06 反馈
/// 「热区比木牌大出不少」——旧标定 x 86.6~272.4 / y 1499.7~1686.6 底边下探 35px
/// 压到栅栏、左边缩进牌内 28px，已废弃）。
const Rect kGardenSignNormalizedRect = Rect.fromLTRB(0.0511, 0.6451, 0.2576, 0.7102);

/// 木牌在给定容器中的**屏幕矩形**（由 [gardenCoverRect] 映射而来）。
///
/// 调用方（`GardenPage`）用它与 `Positioned.fromRect` 摆放木牌热区。
Rect gardenSignScreenRect(Size box) {
  final Rect cover = gardenCoverRect(box);
  return Rect.fromLTRB(
    cover.left + kGardenSignNormalizedRect.left * cover.width,
    cover.top + kGardenSignNormalizedRect.top * cover.height,
    cover.left + kGardenSignNormalizedRect.right * cover.width,
    cover.top + kGardenSignNormalizedRect.bottom * cover.height,
  );
}

/// 草地「可摆花盆区」底界的**归一化 y**。
///
/// 依据：新图（1056×2336）菜地土块上沿约 0.725，花盆区底界必须落在此之上，
/// 保证滚动时花盆永不遮挡背景植物。
/// C48（玄参 2026-10-10）：0.70 → **0.64** —— 木牌牌面顶在 0.6451（源图 y 1507），
/// 0.70 时网格内容截断线落在木牌中下部，滚动中第 3 行会盖住「玩法」木牌；
/// 收到 0.64 在木牌顶之上留 ~5px 余量。
const double kGardenPotAreaBottomFraction = 0.64;

/// 花盆网格区底界的**屏幕 y**（容器坐标）。
double gardenPotAreaBottom(Size box) {
  final Rect cover = gardenCoverRect(box);
  return cover.top + kGardenPotAreaBottomFraction * cover.height;
}

/// 花盆网格的**可视高度**（容器坐标像素）——「锁死三行」的**唯一真源**。
///
/// 页面只调用本函数、不再自己内联算行高/行数，从而「改行数 → 测试必红」
/// （QA 缺陷 1：原实现把算式复刻在测试里，改生产代码测试不变红）。
///
/// 规则：`可视高度 = min([visibleRows] 行高度, 花盆区底界 - 网格区顶部 - bottomInset)`，负值钳到 0：
///  · N 行高度 = 行高 × [visibleRows] + 行间距 × ([visibleRows] - 1)；
///  · 行高 = 格宽 / [cellAspectRatio]，格宽 = (gridInnerWidth - 2 × [spacing]) / 3；
///  · 底界 = [gardenPotAreaBottom]（背景菜地上沿之上），再退 [bottomInset] 作呼吸间距。
///
/// C47e（玄参 2026-10-09）：`visibleRows` 由 2 放宽到 3——花盆尺寸统一后，网格区
/// 「锁 2 行」在草地上留出大片空白（实测 iPhone 17 上可用高度 590.8pt，2 行仅用
/// 387.2pt）。改为 3 行后一屏可见 **3×3 = 9 格**（容量上限 kGardenPotCapacityMax=12
/// 本就够），草地空白被填满；矮屏仍由 `min(...)` 钳制 + 网格区纵向滚动兜底。
///
/// ⚠️ [cellAspectRatio] **必须由调用方传入**：本文件不得 import flutter（保持纯 dart），
/// 故不能引用 `GardenGrid.cellAspectRatio`。页面传 `GardenGrid.cellAspectRatio`，二者恒等。
double gardenGridVisibleHeight({
  required Size box,
  required double gridInnerWidth,
  required double firstRowTop,
  required double cellAspectRatio,
  double spacing = 4, // C48：与 GardenGrid.mainAxisSpacing 同步（6 → 4）
  double bottomInset = 0,
  int visibleRows = 3,
}) {
  final double cellWidth = (gridInnerWidth - spacing * 2) / 3;
  final double rowHeight = cellWidth / cellAspectRatio;
  final double rowsHeight =
      rowHeight * visibleRows + spacing * (visibleRows - 1);
  final double available = gardenPotAreaBottom(box) - firstRowTop - bottomInset;
  final double height = math.min(rowsHeight, available);
  return height < 0 ? 0.0 : height;
}
