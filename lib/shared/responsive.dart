/// 响应式基线（C61 平板适配，2026-10-13 玄参拍板）。
///
/// ## 定位
/// 「随屏幕尺寸变化」的**派生值单点收口**：所有页面一律调用本文件的纯函数，
/// 不得内联算式（对齐 `prd_params.dart` 的「防孪生」总纪律）。
///
/// ## 判定口径
/// 一律用 **shortestSide（屏短边）**，不用窗口宽度 —— 本 App 全局锁竖屏，只有
/// 专注 / 护眼 / 结算三处临时横屏，按窗口宽度判会把手机横屏（≈780 宽）误判成
/// 平板。shortestSide 表达「设备物理上多大」，才是正确抽象。
///
/// ## 手机零回归
/// `shortestSide < kTabletShortestSideThreshold` 时，本文件所有派生值与原实现
/// **逐位相等**（仅「乘法 + min 钳制」，手机侧 min 永不生效），故手机端零像素变化。
library responsive;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/constants/prd_params.dart';

/// 是否平板：`shortestSide >= kTabletShortestSideThreshold`。
bool isTabletShortestSide(double shortestSide) =>
    shortestSide >= kTabletShortestSideThreshold;

/// 从 `BuildContext` 判定是否平板。
///
/// ⚠️ 用 `MediaQuery.sizeOf`（只订阅 size）而非 `MediaQuery.of(context).size`
/// （订阅整棵 MediaQuery，键盘弹出等无关变化也会触发重建）。
bool isTabletOf(BuildContext context) =>
    isTabletShortestSide(MediaQuery.sizeOf(context).shortestSide);

/// 平板 UI 放大倍率（F129：**随屏短边线性放大**，取代原固定 1.3）。
///
/// 锚点 = [kTabletUiScaleBaseShortestSide]（834 → 1.3，iPad 11″ 零回归）；
/// 更大屏按 `834 的比例` 上调，钳到 [kTabletTextScaleMax]（1.6）；
/// **只放不缩**：小平板（如 iPad mini 744）仍为 1.3，不因本次改动变小。
/// 手机（< 600）恒 1.0。
///
/// 举例：834 → 1.3 ／ 1024 → 1.596 ／ **1032（iPad 13″）→ 1.6**（钳制）／ 1200 → 1.6。
double tabletUiScaleFor(double shortestSide) {
  if (!isTabletShortestSide(shortestSide)) return 1.0;
  // 线性外推：短边越大，屏越大，同一绝对字号「相对屏幕」越小 → 必须继续放大。
  final double scaled =
      kTabletUiScale * (shortestSide / kTabletUiScaleBaseShortestSide);
  // max：只放不缩（iPad mini 744 / 荣耀平板 800 都是 1.3，不因外推变小）；
  // min：上限 1.6，否则 1032 会算成 1.609、大屏会一路飙到 2.0+ 撑破布局。
  return math.max(kTabletUiScale, math.min(scaled, kTabletTextScaleMax));
}

/// 平板 **UI 放大倍率**：按当前屏短边派生 [tabletUiScaleFor]，手机 = 1.0。
///
/// 用于「文字之外的定尺寸元素」——素材图片 / 徽标 / 图标等的 width/height。
/// 文字不经过这里（走 [tabletTextScaler] 注入的 `MediaQuery.textScaler` 自动缩放），
/// 但两者**同源同函数**，故文字与图形恒等比，不会漂移。
///
/// ⚠️ 乘在尺寸上的写法：`width: 16 * uiScaleOf(context)`。不要改宽度常量本身
/// （那些常量被测试与路由尺寸复用）。
double uiScaleOf(BuildContext context) =>
    tabletUiScaleFor(MediaQuery.sizeOf(context).shortestSide);

/// 平板文字缩放器（C65；F129 加 `shortestSide` 入参）：
/// `设备自带缩放 × tabletUiScaleFor(shortestSide)`，并钳到 [kTabletTextScaleMax]。
///
/// 手机端应**不要**调用本函数（调用方 `app.dart` 已带平板闸门）；返回值恒 ≥ 1.0，
/// 保证「平板上文字一定不小于手机」。
///
/// [shortestSide] 必须由调用方传入（而非在此内部读 `MediaQuery`）：本函数是纯函数，
/// 才能被无宿主的单测直接覆盖真值表。
TextScaler tabletTextScaler(TextScaler device, {required double shortestSide}) {
  final double total = (device.scale(1.0) * tabletUiScaleFor(shortestSide))
      .clamp(1.0, kTabletTextScaleMax);
  return TextScaler.linear(total);
}

/// 按设备档位给 [MediaQueryData] 套上平板文字放大（C65 的**唯一注入点**）。
///
/// `app.dart` 的 `MaterialApp.router(builder:)` 只调用本函数，保证「是否平板」
/// 这条判据与 [tabletTextScaler] 的钳制规则都能被**纯单测**直接覆盖。
///
/// 行为：
///  - `shortestSide < 600`（手机）→ **原样返回**（调用方不包 `MediaQuery`，零回归）；
///  - 平板 → `copyWith(textScaler: tabletTextScaler(..., shortestSide: mq.size.shortestSide))`，
///    倍率随屏短边派生（F129：iPad 11″ 1.3 ／ iPad 13″ 1.6）。
///
/// ⚠️ 调用点必须位于「尚未注入」的那一层。`MaterialApp.router` 的 `builder` 每次
/// 都用**外壳 context**（在注入子树之上）回调，故不会叠加复用；**禁止**在已注入的
/// 子树里再调一次（会把 1.3 累乘成 1.69、1.6 累乘成 2.56）。
MediaQueryData applyTabletTextScaling(MediaQueryData mq) {
  if (!isTabletShortestSide(mq.size.shortestSide)) return mq;
  return mq.copyWith(
    textScaler: tabletTextScaler(
      mq.textScaler,
      // F129：倍率随屏短边派生 —— 注入点在这里把尺寸交给纯函数，调用方（app.dart）无感。
      shortestSide: mq.size.shortestSide,
    ),
  );
}

/// 花盆底部区（细进度条 + 标签胶囊）高度（C65）。
///
/// **必须由所有消费方共用**（`garden_pot.dart` 三类格子 + `care_effect_overlay.dart`
/// 的落点计算）：三类格子靠它保证同行盆底对齐；养护动效的盆口线也由它推导。
///
/// 取值 = 手机基准 [kGardenPotFooterHeight] + 放大增量 `(倍率−1) × kGardenPotLabelLineHeight`。
/// 手机（倍率 1.0）→ **逐位等于 32**（零回归）；平板 1.3 → 36.8。
double gardenPotFooterHeightOf(BuildContext context) =>
    gardenPotFooterHeightFor(MediaQuery.textScalerOf(context).scale(1.0));

/// [gardenPotFooterHeightOf] 的**几何内核**（纯函数，便于无宿主单测）。
double gardenPotFooterHeightFor(double textScale) =>
    kGardenPotFooterHeight + (textScale - 1.0) * kGardenPotLabelLineHeight;

/// 成长演出卡宽度 = `shortestSide × kGrowFxCardWidthRatio`，**平板钳到上限**。
///
/// 手机 390 → 304.2（不变）；平板 800 → 360（原 624 会糊满整屏）。
double growFxCardWidthOf(double shortestSide) => math.min(
      shortestSide * kGrowFxCardWidthRatio,
      kGrowFxCardMaxWidth,
    );

/// 花园花盆网格**自身净宽** = `页面宽 − 左右内边距 ×2`，**平板钳到上限**。
///
/// 手机 390（`pagePadH=12`）→ 366（不变）；平板 834 → 620（居中，两侧留白）。
///
/// ⚠️ 页面把这个值**同时**用于：① 给 `GardenGrid` 的渲染宽度；
/// ② 传给 `gardenGridVisibleHeight` 的 `gridInnerWidth`。
/// 二者必须同源，否则「量出来的行高」与「画出来的行高」不一致 → 溢出或空白。
double gardenGridNetWidthOf(
  double pageWidth, {
  required double pagePadH,
}) =>
    math.min(pageWidth - pagePadH * 2, kGardenGridMaxWidth);
