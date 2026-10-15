/// C74 · 今日页「专注等级」**徽章 + 详情卡**（2026-10-14 下午「摘要 + 点按详情」方案）。
///
/// ## 形态演进（玄参三轮真机反馈后定稿）
///  · v0：徽章 + 胶囊**下方**独立提示行 → 提示行横穿向日葵花脸（❌）；
///  · v1：提示行收进气泡内作第二行 → 「累计 8 小时·距 Lv.6 还需 3 小时」在小小的
///    胶囊里**断成 2 行**，且白胶囊与「今日」pill 视觉打架（❌）；
///  · **v2（本版）**：徽章降级为**摘要** —— 只剩 `Lv.N` 圆徽 + 称号一行 +
///    细进度条三件，尺寸 **≈144×44pt**（旧 220×54）；「还差多久 / 9 个称号全貌」
///    改由**点按徽章弹出详情卡**承载（本文件 [showFocusLevelDetailDialog]）。
///
/// ## 展示口径（C74 §2/§3）
///  · **等级 40 级 · 称号 9 个**：称号只在 1/5/10/15/20/25/30/35/40 解锁，
///    **当前称号 = 已解锁的最高称号节点**（Lv.7 → 仍显示 Lv.5 节点的称号）；
///  · **未解锁**（累计 < 60 分钟，`level == 0`）：圆徽显示 🌱、称号位显示
///    [kLevelBadgeLockedTitle]，进度条指向 Lv.1；
///  · **进度指向下一级**（不是下一个称号）；满级隐藏进度条（无处可进）。
///
/// ## 空间约束（🔴 硬约束，设计 §5.24.5 + 2026-10-14 追加）
///  1. 本组件**不改动**今日页 `kTodayCardTopRatio`(0.40) / `kTodayBgPanelTargetRatio`(0.37)
///     —— 二者是 C67 冻结常量；
///  2. 锚点（`kTodayBadgeLeftRatio` / `kTodayBadgeTopRatio`（手机）/
///     `kTodayBadgeTopRatioTablet`（平板））由**页面** (`child_today_page._buildLayout`)
///     给，本组件只管自身内容尺寸；
///  3. 徽章整体不得与向日葵立绘（`kTodayBgSunflowerNormalizedRect`）及「今日」
///     标题 pill 相交（手机端，度量护栏 `today_badge_bounds_test.dart`）；
///  4. 平板：所有定尺寸元素一律乘 [uiScaleOf]（C65：图片不吃 `textScaler`）；
///     手机 = 1.0 → **零像素回归**。
///
/// ## 三级降级（空间紧张时按序选用，由调用方传 [tier]）
///  · [FocusLevelBadgeTier.full]（默认）：圆徽 + 称号 + 细进度条；
///  · [FocusLevelBadgeTier.compact]：去细进度条；
///  · [FocusLevelBadgeTier.minimal]：只圆徽 + 称号（同 compact 视觉，语义保留）。
///
/// 🔴 数据来源：只用 [FocusLevelProgress]（由累计专注分钟纯派生），**不读库、不算账**，
/// 也不影响任何玩法数值（C74 §6）。文案一律走 `focus_level_service.dart` 的纯函数，
/// 本文件**不内联文案算式**（S14）。
library focus_level_badge;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart'
    show nextLevelGapTextOf, sunlightOfLevel, titleOfLevel, titleRowsOfLevel;
import 'package:sunflower_time/shared/responsive.dart';

/// 徽章展示档位（空间紧张时的三级降级，§5.24.5）。
enum FocusLevelBadgeTier {
  /// 完整：圆徽 + 称号 + 细进度条。
  full,

  /// 紧凑：去细进度条。
  compact,

  /// 最紧：只圆徽 + 称号。
  minimal,
}

// —— 视觉色值（仅本文件使用，故就近定义；与 App 奶油/阳光风同源）——

/// 胶囊底（半透明白，压在场景插画上仍可读）。
const Color _kBadgeBg = Color(0xE6FFFFFF);

/// 胶囊描边（暖黄）。
const Color _kBadgeEdge = Color(0x66E8A600);

/// 渐变徽章底 · 未满级（阳光黄）。
const List<Color> _kBadgeCircleColors = <Color>[
  Color(0xFFFFD469),
  Color(0xFFF2A30A),
];

/// 渐变徽章底 · 满级（金色，比普通级更亮）。
const List<Color> _kBadgeCircleMaxColors = <Color>[
  Color(0xFFFFE9A8),
  Color(0xFFFFC02E),
];

/// 满级金边（描边加粗 + 外发光用）。
const Color _kBadgeMaxRing = Color(0xFFFFDC6B);

/// 未解锁替身符号的**奶油圆底**色（玄参 2026-10-14「🌱 太小看不清」）。
///
/// 与 App 奶油风同源（= 状态卡渐变末端 `Color(0xFFFDF3DD)`），不用刺眼纯白；
/// 圆底把 emoji「托」起来，压在场景插画上也看得清。
const Color _kLockedPlateBg = Color(0xFFFDF3DD);

/// 称号文字色（暖棕）。
const Color _kBadgeTitleColor = Color(0xFF6B563F);

/// 未解锁时详情卡里展示的「下一档称号」（= Lv.1 节点的称号，由 [titleOfLevel] 派生）。
String get _kLockedNextTitle => titleOfLevel(1);

/// 进度条底色。
const Color _kBarTrack = Color(0x1F8A5A00);

/// 进度条填充色（阳光橙）。
const Color _kBarFill = Color(0xFFE8A600);

/// 详情卡：次级文字色（浅一档棕）。
const Color _kDetailSoftColor = Color(0xFF8A7A66);

/// 详情卡：当前称号行**高亮底**（阳光黄低透明度）。
const Color _kDetailHighlightBg = Color(0x33E8A600);

/// 详情卡：未解锁节点圆牌底（浅灰）+ 锁符号。
const Color _kDetailLockedChipBg = Color(0x1F8A5A00);

/// 详情卡：未解锁称号文字色。
const Color _kDetailLockedColor = Color(0xFFB0A08C);

/// 今日页等级徽章胶囊（**摘要态**：圆徽 + 称号 + 细进度条；点按出详情卡）。
class FocusLevelBadge extends StatelessWidget {
  const FocusLevelBadge({
    super.key,
    required this.progress,
    this.tier = FocusLevelBadgeTier.full,
    this.totalMinutes = 0,
  });

  /// 展示数据（`progressOf(totalMinutes)` 产出，纯派生）。
  final FocusLevelProgress progress;

  /// 降级档位（默认 [FocusLevelBadgeTier.full]）。
  final FocusLevelBadgeTier tier;

  /// 当前累计专注分钟（详情卡预留；当前详情卡只用 [progress]，为本 UI 未来扩展
  /// （如「累计 X 小时」）留口，调用方照旧注入即可）。
  final double totalMinutes;

  /// 徽章整体 Key（widget 测试定位用）。
  static const Key badgeKey = Key('focusLevelBadge');

  /// 圆形等级徽章 Key（尺寸/位置度量用）。
  static const Key badgeCircleKey = Key('focusLevelBadgeCircle');

  /// 点击热区 Key（详情卡打开用例用）。
  static const Key badgeTapKey = Key('focusLevelBadgeTap');

  /// 细进度条 Key（含/不含、宽度度量用）。
  static const Key badgeBarKey = Key('focusLevelBadgeBar');

  @override
  Widget build(BuildContext context) {
    // C65：平板所有定尺寸元素显式乘 UI 倍率（手机 = 1.0 → 零回归）。
    final double s = uiScaleOf(context);
    final double circle = kLevelBadgeDiameter * s;
    final bool showBar = tier == FocusLevelBadgeTier.full && !progress.isMax;

    // 气泡**包内容自适应高**：高 = max(圆徽 38, 文案列≈22) + 2×3 = **44pt**（手机），
    // 宽 = 10 + 38 + 8 + max(称号实测量≈78, 进度条 72) + 10 ≈ **144pt**
    // （顺序必须是「先量自然宽、再由 [kLevelBadgeMaxWidth] 封顶」）。
    // 高度/宽度如何作用到墙区余量，见 `today_badge_bounds_test.dart` 的机型表。
    //
    // v4（玄参 iPad 溢出修复）：文案列包进 [Flexible] —— 文字列拿到「剩余宽」的
    // 有限约束，超量时 Text 走 ellipsis 而非 RenderFlex overflow（iPad 1.3×uiScale +
    // textScaler 上限 1.6 时「尚未解锁称号」6 字会撑爆 maxWidth）。同时称号字号
    // **不再乘 [uiScaleOf]**（C65：文字走 `MediaQuery.textScaler` 自动缩放）—— 旧版
    // `* s` 是双重缩放，在 textScaler 1.3+ 时把 6 字称号撑到 132pt 撑爆胶囊。
    final Widget capsule = Container(
      padding: EdgeInsets.symmetric(
        horizontal: kLevelBadgePadH * s,
        vertical: kLevelBadgePadV * s,
      ),
      constraints: BoxConstraints(maxWidth: kLevelBadgeMaxWidth * s),
      decoration: BoxDecoration(
        color: _kBadgeBg,
        borderRadius: BorderRadius.circular(kLevelBadgeRadius * s),
        border: Border.all(color: _kBadgeEdge),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LevelBadgeCircle(
            level: progress.level,
            diameter: circle,
            isMax: progress.isMax,
          ),
          SizedBox(width: kLevelBadgeGap * s),
          // v4：Column 包进 [Flexible] —— 文字列拿到「剩余宽」的有限约束，超量时
          // Text 走 ellipsis 而非 RenderFlex overflow（见上方 capsule 注）。
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  progress.isLocked ? kLevelBadgeLockedTitle : progress.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // 显式 height：文案高度确定化（测试 Ahem 与真机同式），
                  // 墙区预算才量得住（见 today_badge_bounds_test.dart 头注）。
                  // C65：文字不乘 [uiScaleOf] —— 走 `MediaQuery.textScaler` 自动缩放
                  // （app.dart 的 applyTabletTextScaling 注入）。手机端 s=1.0、textScaler
                  // 不注入 ⇒ 零回归；平板走单层 textScaler（1.3~1.6），不再双重缩放。
                  style: const TextStyle(
                    fontSize: kLevelTitleFontSize,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    color: _kBadgeTitleColor,
                  ),
                ),
                if (showBar) ...<Widget>[
                  SizedBox(height: kLevelBadgeTextGap * s),
                  _ProgressBar(
                    key: badgeBarKey,
                    progress: progress.progress,
                    scale: s,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    // 玄参「不加可点暗示」：外层不放按钮样式 / 「详情 ›」箭头，只保留 Material
    // 涟漪 —— 点到就有 tactile 反馈，视觉仍是纯摘要。
    return KeyedSubtree(
      key: badgeKey,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: badgeTapKey,
          borderRadius: BorderRadius.circular(kLevelBadgeRadius * s),
          onTap: () => showFocusLevelDetailDialog(context, progress: progress),
          child: capsule,
        ),
      ),
    );
  }
}

/// 打开**等级详情卡**（屏幕居中对话框；点 barrier 可关闭）。
///
/// ⚠️ 刻意走 `showDialog`（一次性摘要 → 详情），**不走** C32 的根 Overlay 演出
/// 管道：那是「升级瞬时反馈」的通道，与「用户主动查询」语义不同。
Future<void> showFocusLevelDetailDialog(
  BuildContext context, {
  required FocusLevelProgress progress,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) =>
        FocusLevelDetailDialog(progress: progress),
  );
}

/// 等级详情卡内容（三块：当前等级+称号 / 距下一级 / 9 个称号全列表）。
class FocusLevelDetailDialog extends StatelessWidget {
  const FocusLevelDetailDialog({super.key, required this.progress});

  /// 第一块里那枚**大圆徽**的 Key（区别于今日页摘要徽章那枚，避免重复 Key）。
  static const Key detailBadgeCircleKey = Key('focusLevelDetailBadgeCircle');

  /// 展示数据（由徽章透传的纯派生模型）。
  final FocusLevelProgress progress;

  /// 整卡 Key（widget 测试定位用）。
  static const Key dialogKey = Key('focusLevelDetailDialog');

  /// 第二块文案 Key（「距 Lv.N 还差 X」/ 满级文案，满级用例断言它）。
  static const Key gapTextKey = Key('focusLevelDetailGapText');

  /// 9 个称号列表行的 Key 前缀（第 i 个称号节点）。
  static const String titleRowKeyPrefix = 'focusLevelDetailTitleRow';

  /// 第 [level] 个称号节点的行 Key。
  static Key titleRowKeyOf(int level) => Key('$titleRowKeyPrefix$level');

  /// 9 行右侧「阳光奖励」widget 的 Key 前缀（第 i 个称号节点）。
  static const String titleRowRewardKeyPrefix = 'focusLevelDetailTitleRowReward';

  /// 第 [level] 个称号节点行的奖励 widget Key。
  static Key titleRowRewardKeyOf(int level) =>
      Key('$titleRowRewardKeyPrefix$level');

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: dialogKey,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kLevelDetailCardRadius),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: kLevelDetailCardMaxWidth,
          // 矮屏兜底：内容超高时可滚（`showDialog` 不会因为溢出给 ALT 红条）。
          maxHeight: MediaQuery.sizeOf(context).height *
              kLevelDetailMaxHeightRatio,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(kLevelDetailCardPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _buildHead(context),
                const SizedBox(height: kLevelDetailSectionGap),
                Text(
                  nextLevelGapTextOf(progress),
                  key: gapTextKey,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: kLevelDetailBodyFontSize,
                    fontWeight: FontWeight.w600,
                    color: _kDetailSoftColor,
                  ),
                ),
                const SizedBox(height: kLevelDetailSectionGap),
                _buildTitleList(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 第一块：大圆徽（内含 Lv.N）+ 称号大字（v3 玄参拍板）。
  ///
  /// 顶部只留两件：大圆徽（[LevelBadgeCircle]，已含 `Lv.N`）+ 称号大字；
  /// **删掉了右侧重复的小号「Lv.N」标签**（v2 时等级出现 2 次：圆徽内 1 次 +
  /// 右侧标签 1 次，玄参觉得冗余）。未解锁时圆徽显示 🌱、称号位显示「下一档
  /// 称号」（[_kLockedNextTitle]），让孩子看见将要解锁的目标。
  Widget _buildHead(BuildContext context) {
    final String title = progress.isLocked ? _kLockedNextTitle : progress.title;
    return Row(
      children: <Widget>[
        LevelBadgeCircle(
          circleKey: FocusLevelDetailDialog.detailBadgeCircleKey,
          level: progress.level,
          diameter: kLevelDetailBadgeDiameter,
          isMax: progress.isMax,
        ),
        const SizedBox(width: kLevelDetailSectionGap),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: kLevelDetailTitleFontSize,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: _kBadgeTitleColor,
            ),
          ),
        ),
      ],
    );
  }

  /// 第三块：**9 个称号全列表**（当前称号高亮 + ✨，每行右侧「小太阳 +
  /// 阳光奖励数」，v3 玄参拍板）。
  ///
  /// · 每行右侧加「小太阳 + 该称号节点阳光奖励数」（C74 §4：3/5/7/9/11/13/
  ///   16/18/20，共 102 ☀）；已解锁 = 实心彩色太阳（已领取），未解锁 = 灰色
  ///   太阳（预告激励，让孩子有盼头）；当前行保留高亮底 + ✨。
  /// · 🔑 奖励数取自 [sunlightOfLevel]（复用 `kFocusLevelUpSunlight` 现有常量，
  ///   **不写第二份数据源**，C74 §4）。
  /// · 仍少文字：不加额外说明句、不加底部汇总行。
  Widget _buildTitleList() {
    final List<FocusLevelTitleRow> rows = titleRowsOfLevel(progress.level);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final FocusLevelTitleRow row in rows)
          Container(
            key: titleRowKeyOf(row.level),
            height: kLevelDetailRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: row.isCurrent ? _kDetailHighlightBg : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                _TitleNodeChip(row: row),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kLevelDetailRowFontSize,
                      fontWeight:
                          row.isCurrent ? FontWeight.w800 : FontWeight.w500,
                      color: row.unlocked
                          ? _kBadgeTitleColor
                          : _kDetailLockedColor,
                    ),
                  ),
                ),
                if (row.isCurrent)
                  const Text(
                    kLevelDetailCurrentMark,
                    style: TextStyle(fontSize: kLevelDetailRowFontSize),
                  ),
                const SizedBox(width: 8),
                _TitleRowReward(
                  key: FocusLevelDetailDialog.titleRowRewardKeyOf(row.level),
                  amount: sunlightOfLevel(row.level),
                  unlocked: row.unlocked,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 9 个称号列表左侧的**节点小圆牌**：已解锁显示节点等级数字，未解锁显示锁 🔒。
class _TitleNodeChip extends StatelessWidget {
  const _TitleNodeChip({required this.row});

  final FocusLevelTitleRow row;

  /// 未解锁节点的锁符号（emoji；✏️ 待玄参提供美术后替换，届时只改本处）。
  static const String _kLockedGlyph = '🔒';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kLevelDetailRowChipSize,
      height: kLevelDetailRowChipSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: row.unlocked ? null : _kDetailLockedChipBg,
        gradient: row.unlocked
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: row.isCurrent
                    ? _kBadgeCircleMaxColors
                    : _kBadgeCircleColors,
              )
            : null,
      ),
      child: Center(
        child: Text(
          row.unlocked ? '${row.level}' : _kLockedGlyph,
          style: TextStyle(
            fontSize: row.unlocked ? 12 : 13,
            fontWeight: FontWeight.w700,
            color: row.unlocked ? Colors.white : _kDetailSoftColor,
          ),
        ),
      ),
    );
  }
}

/// 圆形等级徽章（`Lv.N` / 未解锁 🌱）—— 今日页胶囊与升级演出卡**共用同一枚**（防孪生）。
///
/// 满级（Lv.40）走**金边加粗**视觉。
class LevelBadgeCircle extends StatelessWidget {
  const LevelBadgeCircle({
    super.key,
    required this.level,
    required this.diameter,
    required this.isMax,
    this.circleKey,
    this.labelFontSize,
    this.maxRingEnabled = true,
  });

  /// 等级（0 = 未解锁 → 显示 `kLevelLockedGlyph`）。
  final int level;

  /// 直径（已含 uiScale）。
  final double diameter;

  /// 是否满级（改变渐变与描边）。
  final bool isMax;

  /// 本枚圆徽的 Key（省略 → 今日页徽章那枚 [FocusLevelBadge.badgeCircleKey]）。
  ///
  /// ⚠️ 详情卡 head 里是**第二枚**圆徽，必须传独立 Key（`kDetailBadgeCircleKey`），
  /// 否则同一棵 widget 树里出现重复 Key（详情卡展开时今日页那枚还在下层）。
  final Key? circleKey;

  /// 数字字号（省略 → 随直径等比：`diameter / kLevelBadgeDiameter × kLevelLabelFontSize`）。
  final double? labelFontSize;

  /// 是否画满级金边。
  final bool maxRingEnabled;

  @override
  Widget build(BuildContext context) {
    final bool locked = level <= 0;
    return KeyedSubtree(
      key: circleKey ?? FocusLevelBadge.badgeCircleKey,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isMax ? _kBadgeCircleMaxColors : _kBadgeCircleColors,
          ),
          border: Border.all(
            color: Colors.white,
            width: isMax && maxRingEnabled ? 3 : 2,
          ),
          boxShadow: <BoxShadow>[
            if (isMax && maxRingEnabled)
              const BoxShadow(
                color: _kBadgeMaxRing,
                blurRadius: 10,
                spreadRadius: 1,
              ),
            const BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: locked
              // 玄参「🌱 太小看不清」→ 放大符号（18 → 26）并**叠奶油圆底**
              // （圆底直径取 max(直径 − 8, 30) ⇒ 今日徽章缩到 38 后符号不变小）。
              ? _LockedGlyphPlate(
                  diameter: diameter,
                  fontSize: labelFontSize ?? kLevelLockedFontSize,
                )
              : Text(
                  '$kLevelBadgeTextPrefix$level',
                  style: TextStyle(
                    fontSize: labelFontSize ??
                        (diameter / kLevelBadgeDiameter) * kLevelLabelFontSize,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 未解锁替身符号的**奶油圆底 + 放大符号**（玄参 2026-10-14「🌱 太小」反馈）。
///
/// 圆底直径取「徽章直径 − 8」并在此基础上不小于 [kLevelLockedBgDiameter] × scale，
/// 保证符号在今日页的 38pt 圆徽里也不缩小（手机 = 1.0 → 零回归）。
class _LockedGlyphPlate extends StatelessWidget {
  const _LockedGlyphPlate({required this.diameter, required this.fontSize});

  /// 外层徽章圆直径（已含 uiScale）。
  final double diameter;

  /// 符号字号（已含 uiScale 逻辑）。
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final double s = uiScaleOf(context);
    // 圆底 = max(徽章直径 − 8, kLevelLockedBgDiameter × s)，两者取大保证「看得清」。
    final double plate =
        math.max(diameter - 8, kLevelLockedBgDiameter * s);
    return Container(
      width: plate,
      height: plate,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _kLockedPlateBg,
      ),
      child: Center(
        child: Text(
          kLevelLockedGlyph,
          style: TextStyle(fontSize: fontSize),
        ),
      ),
    );
  }
}

/// 详情卡 9 行右侧的「小太阳 + 阳光奖励数」（v3 玄参拍板）。
///
/// · 已解锁（[unlocked] = true）：实心彩色太阳（阳光橙 [_kUnlockedSunColor]）+
///   数字 —— 已领取语义；
/// · 未解锁：灰色太阳（[_kLockedSunColor]）+ 数字 —— 预告激励，让孩子看见下一档
///   能领多少 ☀。
///
/// 🔑 奖励金额来自调用方传入（实为 [sunlightOfLevel] 的返回，复用
/// `kFocusLevelUpSunlight` 现有常量，不写第二份数据源，C74 §4）。太阳用内置
/// `Icons.wb_sunny`（实心），与全 App 阳光素材缺失回退图标同源；灰态 = 同一枚
/// 图标换色，可靠且可测（颜色直接读 [Icon.color]）。
class _TitleRowReward extends StatelessWidget {
  const _TitleRowReward({
    super.key,
    required this.amount,
    required this.unlocked,
  });

  /// 该称号节点的阳光奖励（3/5/7/9/11/13/16/18/20，C74 §4）。
  final int amount;

  /// 该节点是否已解锁（决定太阳颜色与字重）。
  final bool unlocked;

  /// 已解锁太阳色（阳光橙，与进度条填充 [_kBarFill] 同源）。
  static const Color _kUnlockedSunColor = Color(0xFFE8A600);

  /// 未解锁太阳色（与未解锁称号文字 [_kDetailLockedColor] 同源灰）。
  static const Color _kLockedSunColor = Color(0xFFB0A08C);

  @override
  Widget build(BuildContext context) {
    final Color color = unlocked ? _kUnlockedSunColor : _kLockedSunColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.wb_sunny, color: color, size: 16),
        const SizedBox(width: 3),
        Text(
          '$amount',
          style: TextStyle(
            fontSize: kLevelDetailRowFontSize,
            fontWeight: unlocked ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 细进度条（宽 [kLevelBarWidth] × 高 [kLevelBarHeight]，圆角 [kLevelBarRadius]；
/// 已乘 [scale]）。
///
/// 2026-10-14 下午**回归**：徽章转摘要态后提示文案撤出，高度预算够放下这一根。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({super.key, required this.progress, required this.scale});

  final double progress;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kLevelBarRadius * scale),
      child: SizedBox(
        width: kLevelBarWidth * scale,
        height: kLevelBarHeight * scale,
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          backgroundColor: _kBarTrack,
          valueColor: const AlwaysStoppedAnimation<Color>(_kBarFill),
        ),
      ),
    );
  }
}
