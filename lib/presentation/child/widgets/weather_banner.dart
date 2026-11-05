/// 顶部**天气条幅**（A3）：极端日横跨整宽的 56pt 提示条。
///
/// ```
/// ┌──────────────────────────────────────────────┐  56 高 / 圆角 12 / 白 0.88
/// │ [位图图标 24]  今天很干，给花浇点水，          │ [道具按钮 32]
/// │                再搭个遮阳棚吧（最多 2 行）      │
/// └──────────────────────────────────────────────┘
/// ```
///
/// ## 为什么条幅要全宽（不是设计偏好，是算术）
/// A2 的薄行把 366pt 宽度用满了（chips 179 + 天气区 187）。条幅若与 chips 并排，
/// 剩余宽度 ≈ 366 − 179 − 24 − 90 ≈ 73pt ⇒ 英文 todo 文案（60 字符）要排 6 行，
/// 完全不可用。所以**极端日 chips 纵向让开**（见 `garden_page.dart` 的浮层装配）。
///
/// ## 与薄行（`weather_status_bar.dart`）的分工
///  · **温和日（5 种）**：本组件**不渲染**，薄行的胶囊 + hint 逐位照旧；
///  · **极端日（4 种）**：本组件承接「图标 + 指令 + 按钮 / ✓」，薄行的
///    `GardenWeatherRow` **不渲染**（信息不重复，见设计 §6）。
///
/// ## 三条硬约束
///  · 🔴 **零动画**：花园页已有两个无限动画，`pumpAndSettle` 会卡死；
///    条幅不许出现 `AnimatedContainer` / 入场动效（连 InkWell 水波都不用）。
///  · 🔴 **固定高 56**：三态不同高会让下面的 chips 跟着跳（跨零点时肉眼可见）。
///  · 🔴 **文案不许 ellipsis**：信息完整优先，放不下就 `FittedBox(scaleDown)`
///    等比缩小（`maxLines: 2`）。
library weather_banner;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/services/weather_banner_logic.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart';
import 'package:sunflower_time/shared/responsive.dart' show uiScaleOf;

// ── 稳定 Key（widget 测试按 Key 定位；A3 验收 V6/V7 逐字使用）──────────────────

/// 条幅**本体**的稳定 Key（视觉件：全宽 × 56 高）。
///
/// 🔴 **极端日必须存在、温和日必须不存在** —— 这是「极端日出条幅 / 温和日不出」
/// 这条契约的可执行形式（设计 §6 / V6 / V7）。
const Key kWeatherBannerKey = ValueKey<String>('weather_banner');

/// 条幅**图标位**的稳定 Key（24×24 盒子；`todo` 是天气位图，`done` 是 ✓）。
const Key kWeatherBannerIconKey = ValueKey<String>('weather_banner_icon');

/// 条幅**文案区**的稳定 Key（V7 用它量文案是否被挤成 0 宽）。
const Key kWeatherBannerTextKey = ValueKey<String>('weather_banner_text');

// ── 几何常量（数字件乘 `uiScaleOf`；圆角不乘，与胶囊 radius 20 同口径）────────

/// 条幅高 = **56**（设计 §9.9 原值；三态固定，不随内容变）。
const double kWeatherBannerHeight = 56;

/// 条幅圆角 = 12（比胶囊 20 更「方」，与整块提示条的语义相称）。
const double kWeatherBannerRadius = 12;

/// 条幅与下方 chips 行的**纵向间距** = 6。
///
/// 🔴 这个 6 与 chips 自己的 `Padding(top: 6)` **不是**同一段：
///    温和日 chips 顶 = 6(浮层 top) + 6(chips 内距) = 12；
///    极端日 chips 顶 = 6(浮层 top) + 56(条幅) + 6(本间距) = **68**（内距置 0）。
const double kWeatherBannerGap = 6;

/// 天气图标边长 = 24（位图 `weatherArtOf`，96px 源 ⇒ @4x 清晰）。
const double kWeatherBannerIconSize = 24;

/// 条幅内左 / 右内距 = 10。
const double kWeatherBannerPaddingH = 10;

/// 条幅内元素之间的水平间距 = 8。
const double kWeatherBannerInnerGap = 8;

/// 文案最多 2 行（超过就等比缩小，**绝不 ellipsis**）。
const int kWeatherBannerTextMaxLines = 2;

/// 给文案区留的**最小宽度**（= 48）：低于它就宁可把道具按钮降级为「图标 + 价格」。
///
/// 为什么需要：极窄屏 + 大字号 + 英文时，按钮的完整形态（`图标 + 遮雨棚 + 10 ☀`）
/// 会吃掉整行（320 宽 / 1.3 倍字号实测按钮自然宽 ≈ 299 > 整行 276）⇒ 文案被挤成 0 宽、
/// Row 直接 overflow。降级顺序与薄行的压缩阶梯同构：**先牺牲名字，再缩整件**。
const double kWeatherBannerMinTextWidth = 48;

/// 条幅底色 = 白 0.88（与 chips / 胶囊同一族半透明白，`0xE0` ≈ 87.8%）。
const Color kWeatherBannerBg = Color(0xE0FFFFFF);

/// 文案样式（13 / w600；与薄行天气名同字号，不新造字号）。
TextStyle weatherBannerTextStyle() => const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: kWeatherLetterSpacing,
      color: kWeatherTextColor,
    );

// ── 文案单点映射（ARB 下划线键；穷举 switch，新增日型时编译期就报错）───────────

/// 三态 + 日型 → 条幅文案（设计 §5.2 / §5.3 的 8 个键）。
///
/// 🔴 `none`（温和日）返回空串：条幅根本不渲染，这里只是让 switch 穷举；
///    任何「温和日也显示条幅」的实现都会立刻在这条路径上露馅（变异点 M-A3-2）。
String weatherBannerTextOf(WeatherBannerState state, AppLocalizations t) {
  return switch (state.mood) {
    WeatherBannerMood.none => '',
    WeatherBannerMood.todo => switch (state.kind) {
        WeatherKind.drought => t.garden_weather_banner_todo_drought,
        WeatherKind.wind => t.garden_weather_banner_todo_wind,
        WeatherKind.cold => t.garden_weather_banner_todo_cold,
        WeatherKind.rainstorm => t.garden_weather_banner_todo_rainstorm,
        // 温和日不会走到这里（`mood` 恒 none）—— 穷举兜底，保持无 default。
        WeatherKind.sunny ||
        WeatherKind.breeze ||
        WeatherKind.cloudy ||
        WeatherKind.overcast ||
        WeatherKind.lightRain =>
          '',
      },
    WeatherBannerMood.done => switch (state.kind) {
        WeatherKind.drought => t.garden_weather_banner_done_drought,
        WeatherKind.wind => t.garden_weather_banner_done_wind,
        WeatherKind.cold => t.garden_weather_banner_done_cold,
        WeatherKind.rainstorm => t.garden_weather_banner_done_rainstorm,
        WeatherKind.sunny ||
        WeatherKind.breeze ||
        WeatherKind.cloudy ||
        WeatherKind.overcast ||
        WeatherKind.lightRain =>
          '',
      },
  };
}

/// 天气条幅（A3）。
///
/// 纯展示 + 两个回调（整条 → 玩法说明；按钮 → 买棚三态分发），**不做业务判断**：
/// 三态由 [WeatherBannerState] 给死，按钮的可买 / 已购 / 灰态由 [ShelterBuyButton] 画。
class WeatherBanner extends StatelessWidget {
  /// 构造。
  const WeatherBanner({
    super.key,
    required this.state,
    required this.affordable,
    required this.showAction,
    required this.onTap,
    required this.onShelterTap,
  });

  /// 三态结论（`mood` 必不为 [WeatherBannerMood.none]；调用方负责不渲染）。
  final WeatherBannerState state;

  /// 余额 ≥ [kWeatherShelterPrice]（灰态判据，样式由 [ShelterBuyButton] 负责）。
  final bool affordable;

  /// 是否渲染道具按钮。
  ///
  /// `false` 的时机与薄行**同一条纪律**：账本未读完（`_loading`）时不渲染按钮，
  /// 免得「买」字闪一下又变；条幅本体仍然渲染（它承载天气名与指令）。
  final bool showAction;

  /// 点条幅空白处（→ 玩法说明）。
  final VoidCallback onTap;

  /// 点道具按钮（三态分发在页面侧：已购 → 余额不足 → 确认卡）。
  final VoidCallback onShelterTap;

  @override
  Widget build(BuildContext context) {
    final double s = uiScaleOf(context);
    final AppLocalizations t = l10nOf(context);
    final bool done = state.mood == WeatherBannerMood.done;
    final String? refType = state.shelterRefType;
    final double iconBox = kWeatherBannerIconSize * s;
    final String label = weatherBannerTextOf(state, t);

    return GestureDetector(
      // 🔴 `opaque`：整条（含图标与文案区）都吃点击 → 孩子点哪儿都能进玩法说明。
      //    按钮是**子节点**，命中测试先到子节点 ⇒ 点按钮只买棚、不会同时开说明
      //    （Arena 里内层 TapGestureRecognizer 先注册先胜）。
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        key: kWeatherBannerKey,
        height: kWeatherBannerHeight * s,
        decoration: const BoxDecoration(
          color: kWeatherBannerBg,
          borderRadius: BorderRadius.all(Radius.circular(kWeatherBannerRadius)),
        ),
        padding: EdgeInsets.symmetric(horizontal: kWeatherBannerPaddingH * s),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double available = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 0.0;

            // ── 道具按钮（三态样式全部交给既有 [ShelterBuyButton]，本文件不重画）──
            //
            // 宽度按**可用宽**分两档（与薄行的压缩阶梯同一条降级纪律）：
            //  · 先试完整形态（道具图标 + 道具名 + 价格）；
            //  · 若它把文案区挤到不足 [kWeatherBannerMinTextWidth]，降级为「图标 + 价格」。
            // 🔴 宽度预算走既有**唯一真源** `measureWeatherRowMetrics`（铁律 D-1）：
            //    条幅与薄行用同一套数字 ⇒ 两处的「10 ☀ / 遮阳棚」宽度不会漂。
            Widget? action;
            double actionW = 0;
            if (showAction && refType != null) {
              final WeatherRowMetrics metrics = measureWeatherRowMetrics(
                kind: state.kind,
                shelterRefType: refType,
                hasButton: true,
                t: t,
                scaler: MediaQuery.textScalerOf(context),
                scale: s,
              );
              // 除按钮之外的**必占宽度**：图标 + 两段内间距 + 文案最小宽。
              final double reserved = iconBox +
                  kWeatherBannerInnerGap * s * 2 +
                  kWeatherBannerMinTextWidth * s;
              bool showName = true;
              double width = metrics.buttonHitWidth(bought: done, showName: true);
              if (width + reserved > available) {
                showName = false;
                width = metrics.buttonHitWidth(bought: done, showName: false);
              }
              actionW = width;
              // 🔴 最后一道保险：按钮自然宽仍可能超过整行（极端窄屏 + 超大字号）。
              //    `Flexible + FittedBox(scaleDown)` 只在真放不下时等比缩按钮，
              //    常态下 `RenderFittedBox.size == child.size` ⇒ 几何逐位不变。
              action = Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: ShelterBuyButton(
                    key: kShelterButtonHitKey,
                    refType: refType,
                    metrics: metrics,
                    visualWidth:
                        metrics.buttonVisualWidth(bought: done, showName: showName),
                    bought: done,
                    affordable: affordable,
                    showShelterName: showName,
                    onTap: onShelterTap,
                  ),
                ),
              );
            }

            // 文案区宽度 = 总宽 − 图标 − 两段间距 − 按钮。极窄屏兜 0（不许负数，
            // 负宽会直接断言崩溃）；宽度为 0 时文案被 FittedBox 缩为 0 而不是溢出。
            final double textW = math.max(
              0.0,
              available -
                  iconBox -
                  kWeatherBannerInnerGap * s -
                  (actionW > 0 ? kWeatherBannerInnerGap * s + actionW : 0.0),
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  key: kWeatherBannerIconKey,
                  width: iconBox,
                  height: iconBox,
                  child: _WeatherBannerIcon(kind: state.kind, done: done, size: iconBox),
                ),
                SizedBox(width: kWeatherBannerInnerGap * s),
                SizedBox(
                  key: kWeatherBannerTextKey,
                  width: textW,
                  height: kWeatherBannerHeight * s,
                  child: FittedBox(
                    // `scaleDown` **只缩不放**：放得下时逐位 1.0（真机常态 2 行）。
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: textW,
                      child: Text(
                        label,
                        maxLines: kWeatherBannerTextMaxLines,
                        softWrap: true,
                        // 🔴 **不许 ellipsis**（信息完整优先）：宁可整句被裁在 2 行内，
                        //    也不出「…」把关键词吃掉；换行由宽度自然发生。
                        overflow: TextOverflow.clip,
                        style: weatherBannerTextStyle(),
                      ),
                    ),
                  ),
                ),
                if (action != null) ...<Widget>[
                  SizedBox(width: kWeatherBannerInnerGap * s),
                  action,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 条幅图标位（**A5-b 美术的唯一依赖点**：将来改名 / 换实现只改这一个类）。
///
/// · `todo`：天气**位图** `weatherArtOf(kind, size: 24×s)`。素材缺失 / 解码失败时
///   `weatherArtOf` 内部已 `errorBuilder` 回退同尺寸 Material 图标 ⇒ **美术永不阻塞**
///   （`growth_icons.dart` 立的规矩）。
/// · `done`：**不用位图**，固定 `Icons.check_circle_rounded` —— 它承载「做完了」的
///   语义，换成天气位图会让「今 天是干旱」与「干旱的事办完了」在视觉上不可区分。
class _WeatherBannerIcon extends StatelessWidget {
  const _WeatherBannerIcon({
    required this.kind,
    required this.done,
    required this.size,
  });

  /// 当日日型（`todo` 位图取它）。
  final WeatherKind kind;

  /// 是否完成态（`true` → ✓ 图标）。
  final bool done;

  /// 盒子边长（已乘倍率）。
  final double size;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Icon(Icons.check_circle_rounded, size: size, color: kShelterBoughtFg);
    }
    return weatherArtOf(kind, size: size);
  }
}
