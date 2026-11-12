/// 花园页**天气对话框**（页面中部弹出；玄参 2026-11-07 拍板，第三批）。
///
/// ## 入口
/// 点左下角天气状态灯（`GardenWeatherBadge`）→ 宿主调 [showGardenWeatherDialog]。
/// `showDialog` 默认 `barrierDismissible` —— 点遮罩 / 系统返回即可关闭。
///
/// ## 内容结构
/// ```text
///        ┌──────────────────────────┐
///        │      ┌────────┐          │
///        │      │ [88×88] │          │  天气位图坐在日型主题淡色圆角托上
///        │      └────────┘          │  （kGardenWeatherDialogArtTint 淡色表）
///        │        干旱 (!)           │  日型名（w700 16pt；极端 todo 加红色警示徽章）
///        │ 太晒太干啦！快给花浇浇水…   │  孩子视角行动指引（garden_weather_guide_*）
///        │ 🌿 今天花儿长得慢一点点    │  天气对成长的影响（第十批：garden_weather_growth_*，
///        │                          │    定性一行，12pt 次级正文，页面拼好串传入）
///        │      明天 · 微风           │  明日预告行（次级灰，第五批承接）
///        │  [ 🏖 遮阳棚 · 10 ☀ ]      │  极端日且未购：买棚按钮（kShelterButtonHitKey，
///        │                          │    点了先关本框再走页面 _onShelterTap 链路）
///        │ (done 态) 圆角淡底小字条    │  额外动作提醒（第九批 kGardenWeatherDialogExtraHintKey：
///        │                          │    干旱=未浇水 / 暴雨=未施肥；页面拼好串传入）
///        │        [ 知道啦 ]          │  关闭键
///        └──────────────────────────┘
///
/// ## 第十批（2026-11-08）：天气对成长的影响一行
/// 玄参：「每天浇水但进度不一样，孩子会迷茫」⇒ 正文之后、明日预告之前加一行
/// **定性**说明（`garden_weather_growth_*`，方向与 `prd_params.dart` 的 `g` / `w` / `f`
/// 常量一致，arb @description 逐个注明依据）。同样是页面解析好、本组件零 l10n。
///
/// ## 第九批（2026-11-07）：done 态额外动作提醒
/// 买棚 done 后（对勾态），干旱日若当日浇水 = 0 / 暴雨日若当日施肥 = 0，卡片内
/// 明日预告行之后显示一行提醒小字条（页面从账本读当日浇水 / 施肥计数拼好串传入，
/// 本组件零 l10n 解析）；当日完成对应动作 ≥1 次后页面不再传入（提示消失，
/// **done 判据不回退**）。大风 / 极寒买棚即全部完成，无此行。
///
/// ## 第七批（2026-11-07）：盾牌行退场
/// done 态原本在框内渲染「🛡 已获保护」盾牌行（`kGardenWeatherDialogShieldKey`），
/// 玄参拍板盾牌语义移到**天气 badge 左侧**（`GardenWeatherBadge` 左侧 56×s 盾牌
/// 位图（第八批与状态灯同高），`kGardenWeatherBadgeShelterKey`）⇒ 本框盾牌行整体删除；
/// **买棚按钮退场逻辑保留**（`spec.done` = true 仍不渲染按钮 + 不渲染警示徽章）。
/// ```
///
/// ## 🔴 弹窗铁律（i18n B1）：builder 在页级 `L10nScope` **之外**
/// `showDialog` 的 route 挂在 root navigator，其 builder 的 context 位于页面
/// `L10nScope` 之上 —— 故本组件**不做任何 l10n 解析**：全部文案由页面在
/// **自己的 context** 里解析好，装进 [GardenWeatherDialogSpec] 传入
/// （与 `_onShelterTap` 的确认卡同一纪律）。
///
/// ## 🔴 命中盒纪律
/// 买棚按钮的命中盒是**真实 ≥44×44**（`Padding` 外扩 + `HitTestBehavior.opaque`），
/// 不用 `ConstrainedBox + OverflowBox` 假 44（与 `weather_status_bar.dart` 同一条
/// A2-10 纪律）。
///
/// ## 盾牌资产映射（第七批后仍保留）
/// kind → refType 用 `WeatherKind.shelterRefType`（domain 既有 getter），
/// refType → 盾牌位图用 `shelterArtOf`（`weather_status_bar.dart` 既有单点映射，
/// **不另造表**）；素材缺失时其内部 `errorBuilder` 回退 Material 盾牌图标
/// （「美术永不阻塞」纪律）。第七批起**本组件不再渲染盾牌**（迁往
/// `GardenWeatherBadge` 左侧），本文件也不再有 `shelterArtOf` 调用点；
/// 买棚按钮退场逻辑（done 态不渲染按钮）保留。
library garden_weather_dialog;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart'
    show kShelterButtonHitKey, kWeatherTextColor, weatherArtOf;
import 'package:sunflower_time/shared/responsive.dart' show uiScaleOf;

// ── 稳定 Key ────────────────────────────────────────────────────────────────

/// 对话框**内容卡**的稳定 Key（测试断言「对话框在屏幕中部弹出」用）。
const Key kGardenWeatherDialogKey = ValueKey<String>('garden_weather_dialog');

/// **明日预告行**的稳定 Key（测试断言「明日预告在场」用）。
const Key kGardenWeatherDialogTomorrowKey =
    ValueKey<String>('garden_weather_dialog_tomorrow');

/// 大图标**柔和底色托**的稳定 Key（第六批卡片美化，测试断结构用）。
const Key kGardenWeatherDialogArtTrayKey =
    ValueKey<String>('garden_weather_dialog_art_tray');

/// 极端日标题旁**红色警示小徽章**的稳定 Key（todo 态在场；done 态不吓人）。
const Key kGardenWeatherDialogAlertMarkKey =
    ValueKey<String>('garden_weather_dialog_alert_mark');

/// done 态**额外动作提醒小字条**的稳定 Key（第九批 2026-11-07：干旱=未浇水 /
/// 暴雨=未施肥时给一行提示；页面拼好串传入，`null` = 不渲染）。
const Key kGardenWeatherDialogExtraHintKey =
    ValueKey<String>('garden_weather_dialog_extra_hint');

/// 「**今天天气对成长的影响**」行的稳定 Key（第十批 2026-11-08 玄参：每天浇水但
/// 进度不一样，孩子会迷茫 ⇒ 在正文之后、明日预告之前补一行定性说明）。
const Key kGardenWeatherDialogGrowthKey =
    ValueKey<String>('garden_weather_dialog_growth');

// ── 布局常量 ────────────────────────────────────────────────────────────────

/// 对话框内**大图标**边长 = **88**（玄参：「对话框里要一个大图标」）。
const double kGardenWeatherDialogArtSize = 88;

/// 对话框内容卡圆角 = **20**（与确认卡 / 一键胶囊同族）。
const double kGardenWeatherDialogRadius = 20;

/// 对话框内容卡内边距 = **20**（第六批卡片美化定版）。
const double kGardenWeatherDialogPadding = 20;

/// 买棚按钮命中盒的**垂直外扩**（视觉 40 + 上下各 4 = 命中 48 ≥ 44）。
const double kGardenWeatherDialogBuyPadV = 4;

/// 买棚按钮的阳光金底（与旧条幅按钮同族 `0xFFF6C445`）。
const Color kGardenWeatherDialogBuyBg = Color(0xFFF6C445);

/// 极端日标题旁警示小徽章的红底（与状态灯叹号角标同族 `0xFFE24B4A`，不新造色）。
const Color kGardenWeatherDialogAlertMarkColor = Color(0xFFE24B4A);

/// 大图标**柔和底色托**的日型主题淡色表（第六批 2026-11-07 卡片美化）。
///
/// 玄参暖色奶油风：图标不再直接坐在白卡上，而是坐在一块与日型主题呼应的
/// 淡色圆角托上 —— **零渐变**（项目纪律），色值全部为低饱和淡色。
/// 雨系两型（lightRain / rainstorm）共用淡蓝，温和日其余三型各配一色。
/// （第八批 2026-11-07：极寒托加深为雾霾青蓝 —— 纯白雪花在第七批淡青托上
/// 仍看不清；与状态灯 alert 底 `kGardenWeatherBadgeStatusAlertColor` 同色。）
const Map<WeatherKind, Color> kGardenWeatherDialogArtTint =
    <WeatherKind, Color>{
  WeatherKind.sunny: Color(0xFFFAEEDA), // 晴 = 淡金
  WeatherKind.breeze: Color(0xFFEDF4E3), // 微风 = 淡草绿
  WeatherKind.cloudy: Color(0xFFEFF2F6), // 多云 = 淡灰蓝
  WeatherKind.overcast: Color(0xFFEEEFF1), // 阴 = 淡灰
  WeatherKind.lightRain: Color(0xFFE6F1FB), // 小雨 = 淡蓝（雨系）
  WeatherKind.drought: Color(0xFFFAECE7), // 干旱 = 淡橙
  WeatherKind.wind: Color(0xFFE9F0E9), // 大风 = 淡绿灰
  WeatherKind.cold: Color(0xFF6FA3A0), // 极寒 = 雾霾青蓝（第八批加深：纯白雪花要清晰）
  WeatherKind.rainstorm: Color(0xFFE6F1FB), // 暴雨 = 淡蓝（雨系）
};

/// 天气对话框的**全部文案 / 数据包**（页面 context 解析好后传入 —— 弹窗铁律）。
@immutable
class GardenWeatherDialogSpec {
  /// 构造。
  const GardenWeatherDialogSpec({
    required this.kind,
    required this.name,
    required this.detail,
    required this.growthHint,
    required this.tomorrowLabel,
    required this.closeLabel,
    this.tomorrowKind,
    this.shelterRefType,
    this.buyLabel,
    this.done = false,
    this.extraActionHint,
  });

  /// 今日日型（决定大图标；页面快照传入）。
  final WeatherKind kind;

  /// 日型名（页面解析好）。
  final String name;

  /// 详情文案：孩子视角的具体行动指引（`garden_weather_guide_*`，页面解析好；
  /// 数字 / 动作集合与 `prd_params.dart` 常量对齐，见 arb 注释）。
  final String detail;

  /// 「**今天天气对成长的影响**」一行（第十批 2026-11-08；`garden_weather_growth_*`，
  /// 页面解析好）。
  ///
  /// 玄参：「每天浇水但进度不一样，孩子会迷茫」⇒ 用一句**定性**说明（「长得更快
  /// 一点」「长得慢一点点」「和平时一样」）把当日 `g` / `w` / `f` 的方向讲给孩子。
  /// 🔴 措辞方向必须与 `prd_params.dart` 的乘数常量一致（见 arb 各键 @description），
  /// 本组件只渲染、不判断方向、不解析 l10n。
  final String growthHint;

  /// 明日预告整行文案（「明天 · {明日日型名}」，页面解析好）。
  ///
  /// 🔴 第五批（玄参 2026-11-07「就放在天气的弹窗里面吧」）：底部提示框
  /// ticker 撤除后，「明天 · …」预告由本行承接。明日 kind 的计算在**页面**
  /// build 顶层（`WeatherSystem.ofDay(快照 observedAt + 1 天)` 纯函数），
  /// 本组件零天气计算、零 l10n 解析（弹窗铁律），只渲染页面拼好的字符串。
  final String tomorrowLabel;

  /// 明日日型（B13.16：明日预告胶囊里的**图标**；页面 `WeatherSystem.ofDay`
  /// 算好传入，`null` = 只渲染文字胶囊不渲染图标 —— 兼容旧测试构造）。
  final WeatherKind? tomorrowKind;

  /// 当日推荐道具 refType（极端日非 null；`null` = 温和日，无买棚按钮）。
  ///
  /// 🔴 B13.18（2026-11-12 玄参）：原 `shelterEffect`（买棚收益行）已整体删除 ——
  /// 正文（guide）与收益行内容重复，收益并入正文合并句
  /// （`garden_weather_guide_*` 极端日 4 条 =「{天气}，搭上{棚}，植物成长进度
  /// 会受到保护」），页面不再传收益文案，ARb 4 条收益键同删。
  final String? shelterRefType;

  /// 买棚按钮文案（「遮阳棚 · 10 ☀」，页面拼好；极端日必填）。
  final String? buyLabel;

  /// done 态（已购保护）：不显示买棚按钮（第七批起盾牌行已迁往天气 badge 左侧，
  /// 框内不再有「已获保护」行）。
  final bool done;

  /// done 态**额外动作提醒**文案（第九批 2026-11-07 玄参：「已买棚但还没浇水」
  /// 给一句中间提示，依此类推）。页面 context 解析好传入（弹窗铁律）：
  /// · 干旱 + 当日浇水 = 0 →「植物极度口渴，记得多浇水哦」；
  /// · 暴雨 + 当日施肥 = 0 →「雨水替你浇花啦，记得施一次肥哦」；
  /// · 大风 / 极寒买棚即全部完成 → 不传（`null` = 不渲染此行）；
  /// · 当日完成对应动作 ≥1 次后页面不再传（提示自动消失）。
  final String? extraActionHint;

  /// 关闭键文案（「知道啦」）。
  final String closeLabel;
}

/// 弹出天气对话框（页面中部；点遮罩可关）。
///
/// [onBuy] = 宿主的买棚链路（页面 `_onShelterTap`）：**先关本对话框再触发**
/// （避免确认卡叠在天气对话框上两层弹窗）。
Future<void> showGardenWeatherDialog({
  required BuildContext context,
  required GardenWeatherDialogSpec spec,
  required VoidCallback onBuy,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      final double s = uiScaleOf(dialogContext);
      final bool extreme = spec.shelterRefType != null;

      final Widget buyButton = (extreme && !spec.done)
          ? // 🔴 命中盒 = 真实 ≥44：`GestureDetector` **自身** = 视觉 40 + 上下各 4
            // 透明 padding（child = Padding(4) 包视觉件）⇒ 命中盒 48 ≥ 44，透明区
            // 一并吃点击。Key 挂在 GestureDetector 上 —— 它才是真实命中的那层。
            GestureDetector(
                key: kShelterButtonHitKey,
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // 先关本框（确认卡不叠两层弹窗），再走页面买棚链路（含其二次确认）。
                  Navigator.of(dialogContext).pop();
                  onBuy();
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      vertical: kGardenWeatherDialogBuyPadV * s),
                  child: Container(
                    height: 40 * s,
                    padding: EdgeInsets.symmetric(horizontal: 16 * s),
                    decoration: BoxDecoration(
                      color: kGardenWeatherDialogBuyBg,
                      borderRadius: BorderRadius.circular(20 * s),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      spec.buyLabel ?? '',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: Color(0xFF5D4200),
                        ),
                    ),
                  ),
                ),
              )
          : const SizedBox.shrink();

      // 🔴 第七批（2026-11-07）：done 态盾牌行整体退场 —— 盾牌位图迁往天气
      //    badge 左侧（`GardenWeatherBadge`，kGardenWeatherBadgeShelterKey）；
      //    本框 done 态只剩「买棚按钮退场」（不渲染按钮、不渲染警示徽章）。

      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          key: kGardenWeatherDialogKey,
          constraints: BoxConstraints(maxWidth: 320 * s),
          padding: EdgeInsets.all(kGardenWeatherDialogPadding * s),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(kGardenWeatherDialogRadius),
            // elevation 4 口径的柔和投影（暖色奶油风，无渐变）。
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0x33000000),
                blurRadius: 18 * s,
                offset: Offset(0, 6 * s),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ── 图标区：88×88 天气位图坐在日型主题淡色圆角托上（第六批美化）──
              Container(
                key: kGardenWeatherDialogArtTrayKey,
                padding: EdgeInsets.all(10 * s),
                decoration: BoxDecoration(
                  color: kGardenWeatherDialogArtTint[spec.kind] ??
                      const Color(0xFFF5EFE2),
                  borderRadius: BorderRadius.circular(20 * s),
                ),
                child: weatherArtOf(
                  spec.kind,
                  size: kGardenWeatherDialogArtSize * s,
                ),
              ),
              SizedBox(height: 12 * s),
              // ── 标题区：日型名（w700 16pt）+（极端 todo）红色警示小徽章 ──────
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      spec.name,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: kWeatherTextColor,
                      ),
                    ),
                  ),
                  // 警示小徽章只出现在「待处理」的极端日（done 态不吓人）。
                  if (extreme && !spec.done) ...<Widget>[
                    SizedBox(width: 6 * s),
                    Container(
                      key: kGardenWeatherDialogAlertMarkKey,
                      width: 18 * s,
                      height: 18 * s,
                      decoration: const BoxDecoration(
                        color: kGardenWeatherDialogAlertMarkColor,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12 * s,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 10 * s),
              // ── 正文：孩子视角行动指引（13pt / 行高 1.5）────────────────────
              Text(
                spec.detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                  color: kWeatherTextColor,
                ),
              ),
              // ── 今天天气对成长的影响（第十批 2026-11-08）────────────────────
              // 一行 12pt 次级正文 + 中性叶子图标：正文讲「今天该做什么」，本行讲
              // 「为什么每天的进度不一样」。放在正文之后、明日预告之前（玄参口径）。
              SizedBox(height: 8 * s),
              Row(
                key: kGardenWeatherDialogGrowthKey,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 中性图标：不用「上升箭头」——「长得慢一点」配上升箭头会自相矛盾。
                  Padding(
                    padding: EdgeInsets.only(top: 1 * s),
                    child: Icon(
                      Icons.eco_rounded,
                      size: 14 * s,
                      color: kWeatherTextColor.withValues(alpha: 0.60),
                    ),
                  ),
                  SizedBox(width: 4 * s),
                  Flexible(
                    child: Text(
                      spec.growthHint,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: kWeatherTextColor.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
              // ── 明日预告胶囊（B13.16 重排版：淡奶油底胶囊 + 明日日型图标 +
              //    深色 w700 文字；🔴 B13.17（2026-11-12 玄参）「将天气 UI 放在
              //    天气的后面，这个胶囊放大一些」：图标改到**文字之后**，胶囊
              //    整体放大 —— 内距 h14/v7 → h18/v9、字号 13 → 14、图标 20 → 24）──
              SizedBox(height: 10 * s),
              Container(
                key: kGardenWeatherDialogTomorrowKey,
                padding: EdgeInsets.symmetric(
                    horizontal: 18 * s, vertical: 9 * s),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5EFE2),
                  borderRadius: BorderRadius.circular(999 * s),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        spec.tomorrowLabel,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          letterSpacing: 0.25,
                          color: kWeatherTextColor,
                        ),
                      ),
                    ),
                    if (spec.tomorrowKind != null) ...<Widget>[
                      // 明日日型图标（B13.17：移到天气名**之后**；同一
                      // weatherArtOf 单点映射，B13.17 放大到 24）。
                      SizedBox(width: 8 * s),
                      weatherArtOf(spec.tomorrowKind!, size: 24 * s),
                    ],
                  ],
                ),
              ),
              // 🔴 B13.18（2026-11-12 玄参）：「买棚收益行」整体退场 —— 正文与
              //    收益行内容重复（玄参原话「这 2 个地方重复了啊，删除上面那一句，
              //    合并一下」），收益并入正文合并句（guide 极端日 4 条）。
              // ── done 态额外动作提醒小字条（第九批 2026-11-07）───────────────
              // 仅 done 态 + 对应动作未完成时由页面传入（干旱=未浇水 / 暴雨=
              // 未施肥；大风/极寒无）。圆角淡底小条，底色复用日型淡色托同表
              // （零渐变纪律），放在明日预告之后、买棚按钮退场后的空位。
              if (spec.extraActionHint != null) ...<Widget>[
                SizedBox(height: 10 * s),
                Container(
                  key: kGardenWeatherDialogExtraHintKey,
                  width: double.infinity,
                  padding:
                      EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
                  decoration: BoxDecoration(
                    color: kGardenWeatherDialogArtTint[spec.kind] ??
                        const Color(0xFFF5EFE2),
                    borderRadius: BorderRadius.circular(12 * s),
                  ),
                  child: Text(
                    spec.extraActionHint!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: kWeatherTextColor.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
              // ── 操作区：买棚按钮（奶油金主按钮）/ done 盾牌行 ────────────────
              SizedBox(height: 16 * s),
              // done 态：买棚按钮退场（第七批起框内也不再有盾牌行 —— 已迁往
              // 天气 badge 左侧），操作区只剩关闭键。
              if (extreme) buyButton,
              SizedBox(height: 4 * s),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  spec.closeLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    color: kWeatherTextColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
