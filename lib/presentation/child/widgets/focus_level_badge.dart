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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart'
    show nextLevelGapTextOf, titleOfLevel, titleRowsOfLevel;
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart'
    show GoldNoticeItem, showGoldNoticeDialog;
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
///
/// **C80 改版**：改为 [ConsumerWidget] —— `watch` [entitlementProvider] 判定
/// `FeatureKey.titlePerks`（矩阵单点 [featureAllowedFor]）后给每行属性徽章下发
/// `perkUnlocked`（三态：橙实心 / 锁标 / 灰字）。卡开着时购买返回 → entitlement
/// 变化自动重建，锁标行即时恢复橙实心（R-V3-3 已消解；P1-1 零回调代码）。
class FocusLevelDetailDialog extends ConsumerWidget {
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

  /// 卡内**内容框**（`ConstrainedBox(maxWidth: kLevelDetailCardMaxWidth)`）的 Key。
  ///
  /// widget 测试量「卡宽 ≤ 310」用（`Dialog` 外层含 `insetPadding` 铺满屏，量它无意义）。
  static const Key cardKey = Key('focusLevelDetailCard');

  /// 9 行右侧「称号专属属性」小徽章的 Key 前缀（第 i 个称号节点）。
  static const String titleRowPerkKeyPrefix = 'focusLevelDetailTitleRowPerk';

  /// 第 [level] 个称号节点行的属性徽章 Key。
  static Key titleRowPerkKeyOf(int level) =>
      Key('$titleRowPerkKeyPrefix$level');

  /// C81 ①：属性锁标态点按弹出的**升级提示卡** Key（widget 测试断言用）。
  ///
  /// 「只弹提示、不跳转」——不 pop 详情卡、不 push 购买页（V3-Q1 结案）。
  static const Key perkLockedHintKey = Key('focusLevelDetailPerkLockedHint');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // C80：付费是否解锁称号专属属性（矩阵单点判定，与 provider / 域层同源）。
    final bool perkUnlocked = featureAllowedFor(
        FeatureKey.titlePerks, ref.watch(entitlementProvider).tier);
    // C81 ⑥：卡宽乘 [uiScaleOf]（平板 1.3×）——修**满级 5 字长称号**在 iPad 被
    // ellipsis 截断（手机 = 1.0 → 零像素回归；C61/C65：定尺寸元素乘 uiScale）。
    final double s = uiScaleOf(context);
    return Dialog(
      key: dialogKey,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kLevelDetailCardRadius),
      ),
      child: ConstrainedBox(
        key: cardKey,
        constraints: BoxConstraints(
          maxWidth: kLevelDetailCardMaxWidth * s,
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
                _buildTitleList(perkUnlocked),
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

  /// 第三块：**9 个称号全列表**（当前称号高亮，属性徽章**恒靠右且 9 行严格对齐**）。
  ///
  /// · 每行 = 节点圆牌 + 称号（弹性宽、ellipsis）+ 属性徽章靠右
  ///   （[perkEmojiOfTitleNode] / [perkNameOfTitleNode] / [perkShortTextOf] 同源派生，
  ///   不在页面拼九种文案，防孪生 S2）；当前行以**高亮底 + 加粗**标示。
  ///   **C80 改版**：删底部图例区（属性说明上机进徽章行，P0-1/P0-2）；属性徽章
  ///   三态由 [perkUnlocked] 下发（[_PerkPill]，P0-3/P0-6）。
  ///   **C81 ⑤**：删掉行尾 ✨（原 `kLevelDetailCurrentMark`，常量已随删）——它排在
  ///   `_PerkPill` 之后会把**当前行右列**往左挤一个 ✨ 宽 ⇒ 9 行右列不再对齐（玄参
  ///   真机反馈）；删后当前行语义由高亮底 + w800 承担，右列 9 行严格右对齐。
  /// · 行高用 minHeight（C65/C75⑤：平板 textScaler 1.6 时内容自然增高、零溢出）。
  Widget _buildTitleList(bool perkUnlocked) {
    final List<FocusLevelTitleRow> rows = titleRowsOfLevel(progress.level);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final FocusLevelTitleRow row in rows)
          ConstrainedBox(
            key: titleRowKeyOf(row.level),
            // 🔴 C65/C75⑤：行高用 minHeight（**不是**固定 height）——平板 textScaler 1.6 时
            // 右侧上下两行的内在高可能 > 44，固定高会 RenderFlex 纵向 overflow。
            constraints: const BoxConstraints(minHeight: kLevelDetailRowHeight),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: row.isCurrent ? _kDetailHighlightBg : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  _TitleNodeChip(row: row),
                  const SizedBox(width: 10),
                  // C80：称号占满剩余空间（Flexible + ellipsis 优先级最高），
                  // 属性徽章**恒靠右**（不在 Expanded 内、不吃挤压，P1-2）。
                  Expanded(
                    child: Text(
                      row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kLevelDetailRowFontSize,
                        fontWeight: row.isCurrent
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: row.unlocked
                            ? _kBadgeTitleColor
                            : _kDetailLockedColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _PerkPill(
                    key: FocusLevelDetailDialog.titleRowPerkKeyOf(
                      row.level,
                    ),
                    level: row.level,
                    unlocked: row.unlocked,
                    perkUnlocked: perkUnlocked,
                  ),
                ],
              ),
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
              : FittedBox(
                  // 🔴 两位数截断修复（真机 Lv.40 → 「Lv.4」）：
                  // `Lv.N` 是无空格单一词，两位数（Lv.10~Lv.40）的词宽在等比字号下
                  // 超过圆内可用宽（直径 − 2×白描边），又无换行点 ⇒ 水平被裁掉末位。
                  // [FittedBox.scaleDown] 让标签**只在小到放不下时**整体等比缩小：
                  // 一位数视觉零变化；两位数缩到恰好填满内宽，单行完整显示。
                  // ⚠️ 这是「装进固定圆」的布局适配，不违反 C65 红线 —— 文字仍只走
                  // `MediaQuery.textScaler`（FittedBox 不乘 uiScaleOf、不改 textScaler）。
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$kLevelBadgeTextPrefix$level',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: labelFontSize ??
                          (diameter / kLevelBadgeDiameter) *
                              kLevelLabelFontSize,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
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

/// 详情卡每行右侧的**专属属性小徽章**（如「🔒 👁 护眼 +1 ☀」）。
///
/// **C81 形态**（玄参真机验收后定稿）：
///  顺序 = `[🔒（有锁才显示）] [属性 emoji] [属性名] [数值] [☀]`（单一 `Row`）；
///  · 属性 emoji 走 [perkEmojiOfTitleNode]、属性名走 [perkNameOfTitleNode]、
///    数值走 [perkShortTextOf]（**纯数值带符号**，C81 ③ 去描述词）——三者同源单点；
///  · 阳光图标**9 行统一恒带**（C81 ②：不再按达等级条件渲染）。
///
/// **三态视觉**（P0-3 + P0-6）：
///  · **橙实心**（`unlocked && perkUnlocked`）：数值/属性名暖橙 w700 + ☀ 原色；
///  · **锁标态**（`unlocked && !perkUnlocked`）：整体置灰（[_kDetailLockedColor]）+
///    🔒 前缀 + ☀ 同置灰；**可点** → 只弹**升级提示卡**（C81 ①：不 pop、不跳转）；
///    热区扩展 ≥ 44pt（P1-2 孩子手指）；
///  · **灰字**（`!unlocked`）：灰字无锁、不可点（P0-6 边界），☀ 一并置灰（统一）。
///
/// 属性 emoji / 名称 / 数值**全部**走 `plant_perk.dart` 纯函数——不在页面拼九种
/// 文案（防孪生 S2）；C61 图形素材乘 [uiScaleOf]。
class _PerkPill extends StatelessWidget {
  const _PerkPill({
    super.key,
    required this.level,
    required this.unlocked,
    required this.perkUnlocked,
  });

  /// 称号节点等级（决定 emoji / 名称 / 属性量）。
  final int level;

  /// 该节点是否已达等级（决定行色系与是否可点）。
  final bool unlocked;

  /// C80：付费是否解锁称号专属属性（= `featureAllowedFor(FeatureKey.titlePerks, tier)`）。
  final bool perkUnlocked;

  /// 锁标态点按 → 弹「请升级到完整版本功能」提示卡（C81 ①）。
  ///
  /// 只提示、**不** pop 详情卡、**不** push 购买页（V3-Q1 结案：孩子端已无购买入口）。
  ///
  /// F141 ⑤：改走孩子端统一**通知卡**壳 `GoldNoticeDialog`。原 `AlertDialog`
  /// 只有一句 content、**没有标题** ⇒ `title` 传 null（壳内不渲染标题行）。
  /// `key` 必须落在弹窗根 Widget 上：`focus_level_detail_dialog_test` 用
  /// `find.byKey(perkLockedHintKey)` 断言「在场 / 关闭后不在场」。
  static Future<void> _showLockedHint(BuildContext context) {
    return showGoldNoticeDialog(
      context,
      dialogKey: FocusLevelDetailDialog.perkLockedHintKey,
      badgeIcon: Icons.lock,
      items: const <GoldNoticeItem>[],
      footerText: kPremiumUpsellHintText,
      confirmLabel: kLevelDetailHintConfirmText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double s = uiScaleOf(context);
    final String emoji = perkEmojiOfTitleNode(level);
    final String name = perkNameOfTitleNode(level);
    final String value = perkShortTextOf(perkOfTitleNode(level));
    // 三态判定（顺序敏感：未达等级 > 未购买 > 已购实心）。
    final bool locked = unlocked && !perkUnlocked; // 锁标态（可点）
    final bool orange = unlocked && perkUnlocked; // 橙实心
    final Color color = orange ? _kBarFill : _kDetailLockedColor;
    final TextStyle labelStyle = TextStyle(
      fontSize: kLevelDetailPerkFontSize,
      fontWeight: orange ? FontWeight.w700 : FontWeight.w500,
      color: color,
    );

    Widget pill = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // C81 ④ 顺序：🔒 在最前（仅锁标态）→ emoji → 属性名 → 数值 → ☀。
        if (locked) ...<Widget>[
          const Text('🔒',
              style: TextStyle(fontSize: kLevelDetailPerkFontSize)),
          const SizedBox(width: 2),
        ],
        Text(emoji, style: const TextStyle(fontSize: kLevelDetailPerkFontSize)),
        const SizedBox(width: 2),
        Text(name, style: labelStyle),
        const SizedBox(width: 2),
        Text(value, style: labelStyle),
        // C81 ②：阳光图标**9 行统一恒带**（橙实心原色 / 锁标·灰字置灰）。
        const SizedBox(width: 3),
        Image.asset(
          'assets/rewards/sunlight.png',
          width: kLevelDetailPerkSunIconSize * s,
          height: kLevelDetailPerkSunIconSize * s,
          fit: BoxFit.contain,
          color: orange ? null : _kDetailLockedColor,
          errorBuilder: (_, __, ___) => Icon(
            Icons.wb_sunny,
            color: color,
            size: kLevelDetailPerkSunIconSize * s,
          ),
        ),
      ],
    );

    if (locked) {
      // C81 ①：仅锁标态可点 → 只弹升级提示卡（不 pop、不跳转）；
      // 热区扩展 ≥ 44pt（P1-2 孩子手指）。
      pill = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _showLockedHint(context),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(child: pill),
        ),
      );
    }
    return pill;
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
