/// 花园页左下角的天气**图标状态灯**（玄参 2026-11-07 拍板，第三批）。
///
/// ```text
/// 右上角（2026-11-07 第三轮；第七批加左侧盾牌；第十批放大盾牌）：
///            ┌──────┐┌────────┐
///            │ 🛡72 ││        │← 叹号 / 对勾角标（todo / done 态，20×20 外扩 4）
///            └──────┘│  ☀/🌵  │   56×56（×s）圆角 12 状态底色块
///                    └────────┘
///              （已购棚时：盾牌在状态灯**左侧**，盒间距 7、垂直居中；
///                盾牌盒 72，位图内容按 bbox 裁掉透明边距后撑到 64 = 视觉与天气框相当）
/// ```
///
/// ## 历史（Dock → Badge 改名留痕）
///  · **第一轮（2026-11-06）**：顶部条幅/胶囊整体迁到「底部停靠条」（72 白条，
///    左区图标状态灯 + 右区一键 FAB）；
///  · **第二轮（2026-11-06）**：白条撤掉短语文字 / 买棚按钮，只留图标状态灯；
///  · **第三轮（2026-11-07，本文件）**：玄参拍板「**底下的白色长条删除**」——
///    72 白条与一键右区整体撤除，一键操作 FAB 回归 C29 原位（页面根 Stack
///    `Positioned(right:12, bottom:12)`），本组件退化为**独立图标状态灯**
///    `GardenWeatherBadge`（类名 / 文件名 / Key 里「Dock」语义已不准，全部改名；
///    旧白条断言 / 命中扩展盒 `kGardenWeatherDockHitExtension` 随白条一并退役）。
///
/// ## 图标状态灯（唯一的 mood 表达）
/// 56×56（×s）圆角容器（radius 12），天气位图居中（`weatherArtOf`）：
///  · **none**（温和日）→ 底色浅绿 `0xFFC0DD97`，**无**角标；
///  · **todo**（极端日待处理）→ **雾霾青蓝底 `0xFF6FA3A0` + 1.5 红描边 `0xFFE24B4A`**
///    + **右上角红底白「!」角标**（20×s 圆 `0xFFE24B4A`，外扩 4pt 压角不盖图标；
///    第八批 2026-11-07：第七批淡青底上的纯白雪花仍看不清，底色加深一档）；
///  · **done**（极端日已购保护）→ 底色浅绿 + **右上角绿底白对勾角标**（同位同尺寸；
///    绿 = 复用 `kShelterBoughtFg` 0xFF2E7D32，不新造色）。
///
/// ## 可点击
/// 整块 56×s 状态灯包一层 `GestureDetector`（`HitTestBehavior.opaque`），点击
/// 触发 [onTap]（宿主弹出天气对话框）。🔴 **命中区 = 真实 56×s 圆角块**：
/// `RenderBox.hitTest` 首行即 `size.contains(position)`，本组件不做任何
/// `ConstrainedBox + OverflowBox` 的「声明尺寸」把戏（56×s ≥ 44 热区下限，
/// 无需外扩）。
///
/// ## 为什么单独一个文件（与 `weather_status_bar.dart` 同模式）
///  · `garden_page.dart` 已 4200+ 行，状态灯不该再往里塞；
///  · 必须能在**不装配 Riverpod / 数据库**的前提下被 widget 测试直接渲染
///    （测试传真实 `WeatherBannerState` 即可跑）；
///  · 源码守卫纪律（A2-1 / A3 §13）：页面**禁止自己算天气 / 自己读钟** —— 天气快照
///    与三态结论都由页面 `build()` 顶层取好后**往下传**，本组件内**零 IO / 零时钟**。
///
/// ## 🔴 三条硬约束（与旧条幅 / 旧停靠条同一条纪律）
///  · 🔴 **零动画**：花园页已有两个无限动画，`pumpAndSettle` 会卡死；本组件
///    不出现 `AnimatedContainer` / 入场动效。
///  · 🔴 **文案零新增**：本组件不渲染任何天气描述文字（除角标「!」符号），
///    天气语义全部由「图标 + 底色 + 角标」承担。
///  · 🔴 **玩法常量一概不碰**：本文件只保留**布局 / 状态色**常量；
///    `kOneClick*` / `kWeather*` 权重价格概率一律不改。
library garden_weather_badge;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show
        kWeatherShelterRefTypeRain,
        kWeatherShelterRefTypeShade,
        kWeatherShelterRefTypeWarm,
        kWeatherShelterRefTypeWind;
import 'package:sunflower_time/domain/services/weather_banner_logic.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart'
    show GoldNoticeStyle;
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart'
    show
        kShelterBoughtFg,
        shelterArtOf,
        shelterArtPathOf,
        shelterIconOf,
        weatherArtOf;
import 'package:sunflower_time/shared/responsive.dart' show uiScaleOf;

// ── 稳定 Key（widget 测试按 Key 定位；页面级几何测试共用）────────────────────

/// 状态灯**根命中块**（56×s，`GestureDetector` 视觉同尺寸）的稳定 Key。
const Key kGardenWeatherBadgeKey = ValueKey<String>('garden_weather_badge');

/// 天气**图标状态灯容器**的稳定 Key（56×56 圆角底色盒；位图来自 `weatherArtOf`）。
const Key kGardenWeatherBadgeIconKey =
    ValueKey<String>('garden_weather_badge_icon');

/// 右上角**状态角标**的稳定 Key（todo = 红底白「!」；done = 绿底白对勾）。
const Key kGardenWeatherBadgeMarkKey =
    ValueKey<String>('garden_weather_badge_mark');

/// 状态灯**左侧保护盾牌**的稳定 Key（第七批 2026-11-07：盾牌从天气对话框迁出，
/// 已购棚时渲染在状态灯左侧；widget 测试按本 Key 定位）。
const Key kGardenWeatherBadgeShelterKey =
    ValueKey<String>('garden_weather_badge_shelter');

// ── 布局 / 状态色常量（数字件乘 `uiScaleOf`，K27 口径）──────────────────────

/// 图标状态灯容器边长 = **56**（玄参 2026-11-06：「图标太小了要单独拎出来放大」；
/// 96px/288px 源位图 ⇒ @5x 缩到 56 仍清晰）。
const double kGardenWeatherBadgeIconSize = 56;

/// 图标状态灯容器的圆角 = **12**（56 盒配 12 圆角，与 chips 圆角同族）。
const double kGardenWeatherBadgeIconContainerRadius = 12;

/// 状态灯底色（**正常 / 温和日**，`mood == none`）：浅绿 = 一切正常。
const Color kGardenWeatherBadgeStatusOkColor = Color(0xFFC0DD97);

/// 状态灯底色（**极端日 todo**，需处理）：**雾霾青蓝底 `0xFF6FA3A0`**（第八批
/// 2026-11-07 玄参「雪花纯白后仍看不清」：第七批淡青 `0xFFE1F5EE` 太浅，纯白
/// 雪花对比不足 ⇒ 底色加深一档。取值自查：白 vs 底对比度 ≈ **2.8**（≥2.5 达标，
/// 六瓣枝杈清晰可辨）；与红描边 / 红「!」角标靠色相差区分、不冲突；
/// 与天气对话框极寒托 `kGardenWeatherDialogArtTint[cold]` 同色）。
const Color kGardenWeatherBadgeStatusAlertColor = Color(0xFF6FA3A0);

/// todo 态的**红描边**色（与叹号角标红底同族原值 `0xFFE24B4A`，不新造色）。
const Color kGardenWeatherBadgeStatusAlertBorderColor = Color(0xFFE24B4A);

/// todo 态红描边宽度 = **1.5**。
const double kGardenWeatherBadgeStatusAlertBorderWidth = 1.5;

/// 叹号角标的红底色（与旧条幅红边同族原值 `0xFFE24B4A`）。
const Color kGardenWeatherBadgeAlertColor = Color(0xFFE24B4A);

/// 对勾角标的绿底色（**复用**已购态前景绿 `kShelterBoughtFg` 0xFF2E7D32，
/// 不新造色 —— 「完成 / 保护」语义同源）。
const Color kGardenWeatherBadgeDoneColor = kShelterBoughtFg;

/// 状态角标边长 = **20**（压在状态灯容器右上，约 1/3 容器边长）。
const double kGardenWeatherBadgeMarkSize = 20;

/// 状态角标相对容器右上角的**外扩偏移** = 4（往外探 4pt，「压在角上」的观感，
/// 不盖图标主体；容器 `Clip.none` 不裁）。
const double kGardenWeatherBadgeMarkOffset = 4;

/// 左侧**保护盾牌**盒边长 = **72**（第十批 2026-11-08 玄参：「还是小，要跟右边天气框
/// 差不多大」⇒ 第八批的 56 盒再放大一档）。
///
/// ⚠️ 这个 72 是**预留盒**，不是「画出来的盾牌有多大」—— 位图（`shelter_*.webp`）
/// 是 288² 画布 + 大量透明边距，`BoxFit.contain` 直接缩到 56 时**视觉主体只有
/// 27.6~47.8pt**（实测见 [kGardenWeatherBadgeShelterArtContentBBox]）。故本批同时做
/// 两件事：① 盒 56 → 72；② 位图按内容 bbox 裁掉透明边距、内容撑到
/// [kGardenWeatherBadgeShelterArtMaxSide]。两者合起来，盾牌视觉主体才真的与
/// 56 天气框相当。
const double kGardenWeatherBadgeShelterSize = 72;

/// 盾牌位图**内容**的长边目标 = **64**（×s）。
///
/// 取值依据：天气状态灯盒 56，其位图内容实测占画布的 47~72%（= 26~40pt 视觉主体），
/// 但**底色块本身是 56 的实心圆角块**，读上去就是「56 那么大」。盾牌是**无实底的
/// 线稿**（同尺寸时视觉权重天然更轻），故取 56 + 8 = 64 作补偿：长边略大于天气框
/// （方形的遮阳/遮雨/保温棚上下各出 4pt，扁平的挡风板只宽不高），观感「差不多大」。
///
/// 内容一律**右缘贴盒右缘**（[kGardenWeatherBadgeShelterGap] 才是**视觉**间距 7；
/// 盒内左侧多出的透明留白不可见，页面上那里也没有任何别的东西）。
const double kGardenWeatherBadgeShelterArtMaxSide = 64;

/// 盾牌位图（288² 画布）**内容实际 bbox 的归一化矩形**（实测，勿猜）。
///
/// 测量方式：`alpha > 8` 取 bbox，除以边长 288（2026-11-08，第十批）。
///  · shade → (45, 38, 254, 249) = 209×211 ⇒ 占画布 72.6% × 73.3%
///  · rain  → (77, 45, 219, 243) = 142×198 ⇒ 占画布 49.3% × 68.8%（最瘦的一件）
///  · warm  → (30, 57, 259, 226) = 229×169 ⇒ 占画布 79.5% × 58.7%
///  · wind  → (22, 87, 268, 210) = 246×123 ⇒ 占画布 85.4% × 42.7%（最扁的一件）
///
/// 「瘦的显小、扁的显矮」正是玄参「还是小」的真因：**同一盒尺寸下四件视觉主体
/// 差 1.7 倍**。按本表归一化后，四件的长边**统一**为
/// [kGardenWeatherBadgeShelterArtMaxSide]，视觉尺寸才一致。
///
/// 🔴 换素材 / 重新导出必须重测本表（与 `weather_status_bar.dart` 的
/// `shelterArtPathOf` 一套走：加第 5 种棚时两处都要补，缺表则按「整画布」兜底）。
const Map<String, Rect> kGardenWeatherBadgeShelterArtContentBBox =
    <String, Rect>{
  // 遮阳棚：209×211 @ (45, 38) / 288
  kWeatherShelterRefTypeShade:
      Rect.fromLTRB(0.15625, 0.131944, 0.881944, 0.864583),
  // 遮雨棚：142×198 @ (77, 45) / 288
  kWeatherShelterRefTypeRain:
      Rect.fromLTRB(0.267361, 0.15625, 0.760417, 0.84375),
  // 保温棚：229×169 @ (30, 57) / 288
  kWeatherShelterRefTypeWarm:
      Rect.fromLTRB(0.104167, 0.197917, 0.899306, 0.784722),
  // 挡风板：246×123 @ (22, 87) / 288
  kWeatherShelterRefTypeWind:
      Rect.fromLTRB(0.076389, 0.302083, 0.930556, 0.729167),
};

/// 盾牌与状态灯的**间距** = **7**（玄参口径 6~8pt 取中值；垂直方向两件居中对齐）。
///
/// 第十批后这是**盒间距**，同时因为盾牌内容右缘贴盒右缘，它也就是**视觉间距**。
const double kGardenWeatherBadgeShelterGap = 7;

/// 花园页右上角的天气**图标状态灯**（可点击，宿主传 [onTap] 打开天气对话框）。
///
/// 纯展示（**无白条 / 无按钮**），不做业务判断：
///  · 三态由 [WeatherBannerState] 给死（页面经 `resolveWeatherBanner` 算好传入），
///    组件只按 mood 画状态灯底色 / 角标；
///  · 买棚入口已迁入天气对话框（`garden_weather_dialog.dart`，走页面既有
///    `_onShelterTap` 链路）—— 旧 dock 的 `affordable` / `showAction` /
///    `onShelterTap` 占位参数随白条一并移除；
///  · **第七批（2026-11-07）**：[shelterBought] = true 时，状态灯**左侧**并排渲染
///    保护盾牌位图（间距 7、垂直居中）——盾牌语义从天气对话框迁出（玄参：「买了棚后
///    盾牌放在天气 badge 左边」；第八批放大到与状态灯同高；**第十批（2026-11-08）
///    盒 56 → 72 + 位图按内容 bbox 撑到 64**，见 [_ShelterArtFilled]）。
class GardenWeatherBadge extends StatelessWidget {
  /// 构造。
  const GardenWeatherBadge({
    super.key,
    required this.kind,
    required this.banner,
    required this.shelterBought,
    required this.onTap,
  });

  /// 今日日型（页面从 `todayWeatherProvider` 快照传入，本组件不自算天气）。
  final WeatherKind kind;

  /// 三态结论（`none` = 温和日；`todo` = 需处理（红底 + 叹号）；`done` = 完成
  /// （绿底 + 对勾））。
  final WeatherBannerState banner;

  /// 今日是否已购保护棚（页面 `_shelterBoughtToday` 传入）：true 且当日为极端日
  /// （[banner].shelterRefType 非 null）⇒ 状态灯左侧渲染盾牌位图。纯展示位：
  /// 只表达「棚已买」，与 done（= 棚 + 动作齐）解耦。
  final bool shelterBought;

  /// 点状态灯（宿主弹出天气对话框；`GestureDetector` 恒非 null，点了必须有响应
  /// —— 与 F166「`onTap: null` 让孩子点了毫无反馈是缺陷」同一条结论）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double s = uiScaleOf(context);

    // mood 只决定状态灯：none → 绿底无角标；todo → 红底 + 叹号；done → 绿底 + 对勾。
    // （三态结论依旧由页面 `resolveWeatherBanner` / `_rememberWeatherBannerDone`
    //  算好传入，badge 只是渲染端。）
    final bool todo = banner.mood == WeatherBannerMood.todo;
    final bool done = banner.mood == WeatherBannerMood.done;

    // 第七批：已购棚（且当日确有推荐棚）⇒ 状态灯左侧并排盾牌位图。
    final bool showShelter =
        shelterBought && banner.shelterRefType != null;

    // 🔴 命中区 = 真实 56×s 块：`SizedBox` 尺寸与 `GestureDetector` 视觉一致，
    //    不做「声明尺寸」假命中（见文件头）。Row(min) 外壳：盾牌在场时向**左**
    //    生长（宿主 `Positioned(right:12)` 锚右缘 ⇒ 状态灯右缘位置逐位不变）。
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (showShelter) ...<Widget>[
          // 宽 72（占位真实）+ 高 56（**不参与行高**）：盾牌盒 72×72 由 OverflowBox
          // 在 56 的行高里上下各溢出 8pt（溢出的是透明留白）。
          // 🔴 为什么不让行高变 72：宿主 `Positioned(right:12, top:12)` 锚顶 —— 行高
          //    一旦变 72，状态灯会被挤到 top 20，**买棚的那一刻天气框会往下跳 8pt**
          //    （玄参没要这个，属于新缺陷）。行高钉 56 ⇒ 状态灯 top 恒 12
          //    （与 A2/A3 全部基线一致），盾牌向上溢出的部分落在 chip 行右侧的空白处。
          SizedBox(
            width: kGardenWeatherBadgeShelterSize * s,
            height: kGardenWeatherBadgeIconSize * s,
            child: OverflowBox(
              minWidth: kGardenWeatherBadgeShelterSize * s,
              maxWidth: kGardenWeatherBadgeShelterSize * s,
              minHeight: kGardenWeatherBadgeShelterSize * s,
              maxHeight: kGardenWeatherBadgeShelterSize * s,
              child: SizedBox(
                key: kGardenWeatherBadgeShelterKey,
                width: kGardenWeatherBadgeShelterSize * s,
                height: kGardenWeatherBadgeShelterSize * s,
                // 盾牌位图（第十批）：不再 `BoxFit.contain` 直接缩整张 288² 画布
                // （透明边距会吃掉 30~57% 的盒子，四件视觉尺寸还差 1.7 倍），
                // 改为按内容 bbox 裁掉透明边距、长边统一撑到 64。
                child: _ShelterArtFilled(
                  refType: banner.shelterRefType!,
                  boxSize: kGardenWeatherBadgeShelterSize * s,
                  artMaxSide: kGardenWeatherBadgeShelterArtMaxSide * s,
                ),
              ),
            ),
          ),
          SizedBox(width: kGardenWeatherBadgeShelterGap * s),
        ],
        SizedBox(
          key: kGardenWeatherBadgeKey,
          width: kGardenWeatherBadgeIconSize * s,
          height: kGardenWeatherBadgeIconSize * s,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: _buildStatusIcon(s, todo: todo, done: done),
          ),
        ),
      ],
    );
  }

  /// 天气**图标状态灯**：56×56 圆角底色容器 + 天气位图 +（todo / done）右上角角标。
  ///
  ///  · 底色：none → 浅绿；todo → 雾霾青蓝底 + 1.5 红描边（第八批：纯白雪花
  ///    在第七批淡青底上仍看不清，底色加深一档；警示由描边 + 角标承担）；
  ///    done → 浅绿；
  ///  · 角标：约 20×20 圆，`Positioned` 外扩 4pt 压在容器右上（Stack `Clip.none`
  ///    不裁）：todo = 红底白「!」；done = 绿底白对勾。
  Widget _buildStatusIcon(double s, {required bool todo, required bool done}) {
    return Container(
      key: kGardenWeatherBadgeIconKey,
      width: kGardenWeatherBadgeIconSize * s,
      height: kGardenWeatherBadgeIconSize * s,
      decoration: BoxDecoration(
        color: todo
            ? kGardenWeatherBadgeStatusAlertColor
            : kGardenWeatherBadgeStatusOkColor,
        borderRadius:
            BorderRadius.circular(kGardenWeatherBadgeIconContainerRadius),
        // todo 态红描边（第六批：红底改奶油底 + 红描边，雪花位图不再被红底吃掉）。
        border: todo
            ? Border.all(
                color: kGardenWeatherBadgeStatusAlertBorderColor,
                width: kGardenWeatherBadgeStatusAlertBorderWidth,
              )
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Center(
            child: weatherArtOf(
              kind,
              size: kGardenWeatherBadgeIconSize * s,
            ),
          ),
          if (todo || done)
            Positioned(
              top: -kGardenWeatherBadgeMarkOffset * s,
              right: -kGardenWeatherBadgeMarkOffset * s,
              child: Container(
                key: kGardenWeatherBadgeMarkKey,
                width: kGardenWeatherBadgeMarkSize * s,
                height: kGardenWeatherBadgeMarkSize * s,
                decoration: BoxDecoration(
                  color: todo
                      ? kGardenWeatherBadgeAlertColor
                      : kGardenWeatherBadgeDoneColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: todo
                    ? Text(
                        '!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13 * s,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      )
                    : Icon(
                        Icons.check_rounded,
                        size: 15 * s,
                        color: Colors.white,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 盾牌位图**按内容 bbox 撑满**的渲染件（第十批 2026-11-08）。
///
/// ## 为什么不用 `shelterArtOf` 直接 `BoxFit.contain`
/// `shelterArtOf(refType, size: n)` 把整张 288² 画布按 `contain` 塞进 n×n，透明边距
/// 也算进去 ⇒ 内容实际只占 n 的 43%~85%（见
/// [kGardenWeatherBadgeShelterArtContentBBox]）。盒 56 时视觉主体只有
/// 27.6（遮雨棚）~47.8（挡风板）pt，玄参连说两次「还是小」。
///
/// ## 算法（等比，不拉伸）
///  · `c = artMaxSide / max(bbox.w, bbox.h)` ⇒ 整张画布要画多大；
///  · 内容**长边**恒等于 `artMaxSide`（四件棚视觉尺寸统一）；
///  · 内容**贴盒右缘**（`右缘 = boxSize`）⇒ 与状态灯的视觉间距仍是
///    [kGardenWeatherBadgeShelterGap]（7），左多出来的透明留白被 `ClipRect` 裁掉。
///
/// ## 素材缺失
/// `shelterArtPathOf` 返回 `null`（未知 refType）⇒ 直接回退 `shelterArtOf` 的
/// Material 图标；`Image.errorBuilder` 兜住「文件缺了 / 解码失败」，同样回退图标
/// —— 与 `weather_status_bar.dart` 的「美术永不阻塞」同一条纪律。
class _ShelterArtFilled extends StatelessWidget {
  const _ShelterArtFilled({
    required this.refType,
    required this.boxSize,
    required this.artMaxSide,
  });

  /// 当日推荐道具 refType（`WeatherKind.shelterRefType` 的四个常量之一）。
  final String refType;

  /// 预留盒边长（[kGardenWeatherBadgeShelterSize] × s）。
  final double boxSize;

  /// 内容长边目标（[kGardenWeatherBadgeShelterArtMaxSide] × s）。
  final double artMaxSide;

  @override
  Widget build(BuildContext context) {
    final String? path = shelterArtPathOf(refType);
    if (path == null) {
      // 未知 refType：不建 Image，直接给 Material 盾牌（同 shelterArtOf 的兜底）。
      return Center(
        child: shelterArtOf(refType, size: artMaxSide),
      );
    }
    // 缺表 ⇒ 按「整画布」兜底（等价于旧的 contain 行为，绝不抛异常）。
    final Rect bbox = kGardenWeatherBadgeShelterArtContentBBox[refType] ??
        const Rect.fromLTWH(0, 0, 1, 1);
    final double canvas = artMaxSide / math.max(bbox.width, bbox.height);
    final double contentW = bbox.width * canvas;
    final double contentH = bbox.height * canvas;
    // 内容贴盒右缘、盒内垂直居中 ⇒ 回推整张画布的摆放位置。
    final double left = boxSize - contentW - bbox.left * canvas;
    final double top = (boxSize - contentH) / 2 - bbox.top * canvas;

    return ClipRect(
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: left,
            top: top,
            width: canvas,
            height: canvas,
            child: Image.asset(
              path,
              width: canvas,
              height: canvas,
              // 画布按等比算好 ⇒ fill 与 contain 结果一致，但省掉一次内部换算。
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              // 三条 `_`：签名是 (BuildContext, Object, StackTrace?)。
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) => Icon(
                shelterIconOf(refType),
                size: artMaxSide,
                color: GoldNoticeStyle.buttonFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
