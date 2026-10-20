/// 孩子端「金色通知卡」的**统一实现**（家长端处理结果告知孩子的唯一样式源）。
///
/// ## 为什么要抽这一个文件（F126，玄参 2026-10-19 反馈）
/// 家长核销**商店兑换**后孩子端会弹一张金色卡片（米色底 + 金色奖杯 + 条目 +
/// 「知道啦」），但家长审批**成长任务打卡**后孩子端**什么都没有** —— 孩子感知
/// 不到「任务被确认了」。给这条通知再写一份近似布局（旧内联实现 136 行）会让
/// 两份卡片各自漂移（改配色要改两处、加条目要改两处，且肉眼很难发现不一致）。
/// 故把卡片壳、配色、条目行、按钮全部收成本文件：
///  · 兑换核销通知（`child_shell_page.dart` 的 `_checkVerifiedNotices`）与
///  · 成长任务审批通知（同文件的 `_checkTaskVerifiedNotices`）
/// 调用**同一份**实现，标题 / 条目图标 / 条目金额符号 / 底部合计文案由调用方给。
///
/// ## 视觉口径来源
/// 布局与配色**逐字对齐**既有兑换核销卡（M2 验收形态），本文件只是把内联
/// Widget 树搬出来参数化，未改任何尺寸 / 颜色数值 —— 既有 UI 回归测试
/// （`nav_structure_test` / `c91`）的断言因此仍然成立。
///
/// ## F141 三轮扩能力（本文件本轮改动）
/// 1. **宽度收敛**：`Dialog` 只有 `insetPadding`（左右 40）而**没有最大宽度**，
///    iPad Pro 13″（逻辑宽 1032）上卡片实测 952 —— 玄参截图反馈「太宽了，变窄
///    一些」。本轮加 [GoldNoticeStyle.maxWidth]（× `uiScaleOf`）上界；
///    **不动 `insetPadding`**：手机 390 上可用宽度 = 390 − 80 = 310 < 340，上界
///    不生效 ⇒ 手机端**逐像素零回归**。
/// 2. **能力扩展**（为另外三张通知卡预留）：`title` / `footerText` 改可选
///    （锁标提示卡只有一句正文、没有标题）；新增 `confirmLabel`（完美日用
///    「太棒啦」）；新增 [NoticeTone]（兑换未通过是**坏消息**，纯金色不合适）。
/// 3. 因此本文件不再只是「发阳光 / 扣阳光」的庆祝卡 —— 语义升级为
///    「孩子端**单按钮**通知卡的唯一壳」（多按钮确认场景仍走
///    `child_confirm_card.dart` 的 `ChildConfirmCard`）。
library gold_notice_dialog;

import 'package:flutter/material.dart';

import 'package:sunflower_time/shared/responsive.dart' show uiScaleOf;

/// 通知卡的**语气档位**（单按钮通知卡的语义分档）。
///
/// 为什么需要：本卡原先只服务「家长已确认你的…」这类**好消息**（阳光金 +
/// 奖杯）。但同一位置还有「兑换未被通过」这类**坏消息**（F141 ②）—— 用金色
/// 奖杯庆祝「被拒绝」是反语义的。故加一档 [warn]：配色仍复用 App 既有警示
/// 色（与 `ChildConfirmStyle.danger` 同值），不新造色值族。
enum NoticeTone {
  /// 好消息 / 中性提示（默认）：阳光金徽 + 深金标题 + 金色按钮。
  gold,

  /// **坏消息**（申请被拒绝等）：警示红徽 + 深红标题 + 红底白字按钮。
  warn,
}

/// 金色通知卡的样式常量（单点维护：配色 / 圆角 / 尺寸改这里，两张卡同时生效）。
///
/// 全部取自 M2「家长已核销」卡片的既有数值（App 奶油风同源），不要随意改：
/// 改动会同时影响兑换核销卡与任务审批卡。
abstract final class GoldNoticeStyle {
  /// 卡片底色：米色（与 App 奶油风同源）。
  static const Color cardBg = Color(0xFFFFF9EC);

  /// 主金：徽标底色 / 按钮底色（阳光金）。
  static const Color gold = Color(0xFFF6C445);

  /// 深金：标题文字（保证米色底上的对比度）。
  static const Color goldDeep = Color(0xFF8D6E00);

  /// 阳光金额强调金（条目右侧 + 合计数字）。
  static const Color amount = Color(0xFFD98F00);

  /// 金额**不可用**时的弱化色（F126 二轮：当日额度已满，本次实发 0 阳光）。
  ///
  /// 用深金/琥珀 `0xFF8D6E00` 而非 [amount] 的亮金：孩子一眼能看出「这一行
  /// 不是到账数字」，但仍属同一色系，不会像纯灰那样像报错。与标题同色，
  /// 卡片整体仍协调。
  static const Color amountMuted = Color(0xFF8D6E00);

  /// 条目图标方块底色（浅金）。
  static const Color itemTileBg = Color(0xFFFFF1C2);

  /// 按钮前景（深棕，压在主金上可读）。
  static const Color buttonFg = Color(0xFF5D4200);

  /// 卡片投影。
  static const BoxShadow shadow = BoxShadow(
    color: Color(0x2E000000),
    blurRadius: 28,
    offset: Offset(0, 10),
  );

  /// 细分隔线颜色（棕 10%，不抢视觉）。
  static Color get dividerColor => Colors.brown.withValues(alpha: 0.10);

  /// 卡片圆角。
  static const double cardRadius = 24;

  /// 卡头圆形金徽直径。
  static const double badgeSize = 52;

  /// 卡头金徽内图标尺寸。
  static const double badgeIconSize = 30;

  /// 条目左侧图标方块边长。
  static const double itemTileSize = 34;

  /// 条目左侧图标方块圆角。
  static const double itemTileRadius = 10;

  /// 确认按钮统一文案（两张卡一致；改文案只改这里）。
  static const String confirmLabel = '知道啦';

  /// ![warn] 档的**徽标 / 按钮**底色（警示红）。
  ///
  /// ⚠️ 与 `ChildConfirmStyle.danger`（`child_confirm_card.dart`）**同值**，
  /// 改动须同步。为什么不直接复用那个常量：`child_confirm_card.dart` 已
  /// `import` 本文件（`show GoldNoticeStyle`），反向 import 会成环 —— 故本文件
  /// 自带一份同值常量，两处注释互相指认。
  static const Color warnBadge = Color(0xFFE5544B);

  /// ![warn] 档的**标题**文字色（深红，保证米色底上的对比度）。
  ///
  /// ⚠️ 与 `ChildConfirmStyle.dangerDeep` **同值**，改动须同步（同上：避免
  /// `child_confirm_card.dart` ↔ 本文件的循环 import）。
  static const Color warnDeep = Color(0xFFB3261E);

  /// 卡片内容的最大高度占屏幕高度的比例（超出则**卡内滚动**，不溢出屏幕）。
  ///
  /// 为什么是 0.7：`Dialog` 自带 `insetPadding` 垂直 24，320×568 的小屏上
  /// 「3 条 + 最长合计文案 + 1.3 倍字号」真实需要约 520+，留出上下呼吸空间；
  /// 取 0.7 后大屏（>800 高）根本达不到该上界，故对正常机无任何影响。
  static const double maxHeightRatio = 0.7;

  /// 卡片**最大宽度基准**（真实上限 = 本值 × `uiScaleOf(context)`）。
  ///
  /// 340 的来历与口径**与 `ChildConfirmStyle.maxWidth` 完全一致**：
  ///  · 手机 390：可用宽度 = 390 − `insetPadding`(40×2) = **310** < 340 ⇒
  ///    上界不生效，卡片仍 310（**改前改后逐像素相同，零回归**）；
  ///  · iPad 11″（834，倍率 1.3）：上限 **442**；
  ///  · iPad Pro 13″（1032，倍率 1.6）：上限 **544**（改前 952，收窄约 43%）。
  ///
  /// ⚠️ 与 `ChildConfirmStyle.maxWidth` **同值**，改动须同步（原因同
  /// [warnBadge]：避免与 `child_confirm_card.dart` 循环 import）。
  static const double maxWidth = 340;
}

/// 金色确认卡里的**一条明细**（一行：图标方块 + 名称 + 右侧金额）。
///
/// [amountText] 由调用方格式化（例如 `-10 阳光` / `+5 阳光`）—— 本文件不关心
/// 加减号与单位，只管排版，避免「兑换扣阳光」与「任务发阳光」的语义渗进样式层。
@immutable
class GoldNoticeItem {
  /// 条目左侧图标（兑换用 [Icons.redeem]，任务用 [Icons.task_alt]）。
  final IconData icon;

  /// 条目名称（奖励名 / 任务名）。
  final String name;

  /// 条目右侧金额文案（含符号与单位；金额不适用时可留空 `''` = 不渲染）。
  final String amountText;

  /// 条目**副行**（可选）：名称下方第二行的小字说明（家长备注 / 驳回理由等）。
  ///
  /// F141 修 1（QA 探针 F141-BUG-01）：兑换被拒的家长备注**不是金额**，塞进
  /// [amountText] 既语义错位、又会把右侧挤爆（旧实现右侧 `Text` 在 `Row` 里拿
  /// 无界主轴约束 → 长备注直接 RenderFlex 溢出 213px）。故单开一槽：
  /// 小字号 + 弱化色（复用 [GoldNoticeStyle.amountMuted]，不新造色值），
  /// 与 [name] 同列、可自由折行。
  final String? subtitle;

  /// 金额是否**弱化显示**（默认金色加粗）。
  ///
  /// true 用于「这条确认了，但钱没到」的情形（F126 二轮：当日成长奖励额度
  /// 已满 → 实发 0 阳光）—— 此时 [amountText] 放说明性文字，用
  /// [GoldNoticeStyle.amountMuted] + 非加粗渲染，绝不显示「+0 阳光」冒充到账。
  ///
  /// ⚠️ **NEW-F141-01 起请优先用 [subtitle] 表达「说明」**：金额列只占行内剩余
  /// 宽度的 40%（390 屏 ≈ 87px），「今日额度已满」这类 6 个汉字的说明会被顶成
  /// 两行并断在第 5 个字上。本字段保留给**短**金额的弱化（如 `-10 阳光`），
  /// 产能（`child_shell_page` 的成长任务审批卡）已改为「金额留空 + 说明走 subtitle」。
  final bool amountMuted;

  const GoldNoticeItem({
    required this.icon,
    required this.name,
    this.amountText = '',
    this.subtitle,
    this.amountMuted = false,
  });
}

/// 金色通知卡本体（米色底 + 圆形徽 + 可选标题 + 条目列表 + 可选合计 + 单按钮）。
///
/// 纯展示组件：不读 Provider、不做异步、不弹窗 —— 弹窗时机由调用方掌握
/// （孩子端外壳的已读去重逻辑在 `child_shell_page.dart`）。
///
/// ## 内容槽位（全部可选，除 [items]）
/// ```text
///        ┌───────────────────┐  ← 宽度上限 340 × uiScale（手机 310 / iPad13 544）
///        │       ◯ 圆徽       │  badge（[badgeIcon] + [tone] 决定配色）
///        │     卡片标题        │  title（null 则不渲染，锁标提示卡就是这种）
///        │  ───────────────  │  条目分隔线（无条目时不画）
///        │  ☑ 任务名   +5 阳光 │  items（可为空）
///        │  ───────────────  │
///        │     合计 / 正文      │  footerText（null 则不渲染）
///        │     [ 知道啦 ]      │  confirmLabel（可定制，如「太棒啦」）
///        └───────────────────┘
/// ```
///
/// 🔴 **`super.key` 只落在本 Widget 上**（它已是 `Dialog` 子树的根）——
/// 不要再往下传给内部的 [Dialog]，否则同一 Key 会在树上出现两次，
/// `find.byKey(...)` 变 findsNWidgets(2)。既有用例
/// `focus_level_detail_dialog_test.dart` 的锁标提示卡断言依赖这一点。
class GoldNoticeDialog extends StatelessWidget {
  /// 卡片本体（米色底圆角 Container）的 Key。
  ///
  /// 供测试用 `tester.getSize(find.byKey(...))` 断言**真实渲染宽度**——
  /// `find.byType(GoldNoticeDialog)` 拿到的是 `Dialog` 的全屏 RenderObject，
  /// 量不出卡片宽度（与 `ChildConfirmCard.surfaceKey` 同款做法）。
  static const Key surfaceKey = Key('gold_notice_card_surface');

  /// 卡头标题（含 emoji，例如 `🎉 家长已确认你的兑换`）；null = **不渲染标题**。
  ///
  /// 为 null 的场景：锁标提示卡（F141 ⑤）原文案只有一句正文、没有标题。
  final String? title;

  /// 明细条目（0..N 条；空列表时只显示徽标 + 合计 + 按钮，仍可正常使用）。
  final List<GoldNoticeItem> items;

  /// 底部文案（合计 / 正文，例如 `共扣除 10 阳光`）；null = **不渲染该行**。
  final String? footerText;

  /// 卡头圆徽内的图标（默认金色奖杯 = 庆祝语义）。
  final IconData badgeIcon;

  /// 语气档位（决定徽标 / 标题 / 按钮配色，见 [NoticeTone]）。
  final NoticeTone tone;

  /// 确认按钮文案（默认 [GoldNoticeStyle.confirmLabel]「知道啦」）。
  final String confirmLabel;

  /// 点确认按钮的回调（默认由 [showGoldNoticeDialog] 传 `Navigator.pop`）。
  final VoidCallback? onConfirm;

  const GoldNoticeDialog({
    super.key,
    this.title,
    required this.items,
    this.footerText,
    this.badgeIcon = Icons.emoji_events,
    this.tone = NoticeTone.gold,
    this.confirmLabel = GoldNoticeStyle.confirmLabel,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final bool warn = tone == NoticeTone.warn;
    final Color badgeBg = warn ? GoldNoticeStyle.warnBadge : GoldNoticeStyle.gold;
    final Color titleColor =
        warn ? GoldNoticeStyle.warnDeep : GoldNoticeStyle.goldDeep;
    final Color buttonBg = warn ? GoldNoticeStyle.warnBadge : GoldNoticeStyle.gold;
    final Color buttonFg = warn ? Colors.white : GoldNoticeStyle.buttonFg;
    // F141 修 3：极简通知（无标题、无条目）——只有一句正文 + 一个按钮。
    final bool compact = title == null && items.isEmpty;
    return Dialog(
      backgroundColor: Colors.transparent,
      // ⚠️ 不改这行：手机端「逐像素零回归」的前提（见 [GoldNoticeStyle.maxWidth]）。
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      // F141：宽度上界 —— 340 × uiScale（手机 310 不变 / iPad13 544）。
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: GoldNoticeStyle.maxWidth * uiScaleOf(context),
        ),
        child: Container(
          key: surfaceKey,
          decoration: BoxDecoration(
            color: GoldNoticeStyle.cardBg,
            borderRadius: BorderRadius.circular(GoldNoticeStyle.cardRadius),
            boxShadow: const <BoxShadow>[GoldNoticeStyle.shadow],
          ),
          // F126 三轮：小屏 + 大字号（如 320×568 逻辑像素 + textScaler 1.3）下，
          // 「3 条 + 长 total 文案」会把卡片顶出屏幕（QA 实测溢出 95px，长任务名
          // 125px），属既有无高度约束结构的缺陷被放大 —— 共享组件里一次修掉。
          // 口径：最多占屏幕高度 [GoldNoticeStyle.maxHeightRatio]，超出则**卡内滚动**；
          // 内容不超高时 `ConstrainedBox` 只给上界、`SingleChildScrollView` 取子高度，
          // 卡片尺寸与改动前**逐像素一致**（不出现滚动条、高度不变）。
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height *
                  GoldNoticeStyle.maxHeightRatio,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 卡头元素：圆形徽 + 可选标题。
                    Center(
                      child: Column(
                        children: <Widget>[
                          Container(
                            width: GoldNoticeStyle.badgeSize,
                            height: GoldNoticeStyle.badgeSize,
                            decoration: BoxDecoration(
                              color: badgeBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              badgeIcon,
                              color: Colors.white,
                              size: GoldNoticeStyle.badgeIconSize,
                            ),
                          ),
                          // F141：title 为空时**不渲染**标题（也不留空 SizedBox），
                          // 徽标下方直接接正文/条目（见 [title] 文档）。
                          if (title != null) ...<Widget>[
                            const SizedBox(height: 10),
                            // ⚠️ 标题文案由调用方给：既有兑换卡的字面量被
                            // `nav_structure_test` 钉死，不要在本层改写。
                            Text(
                              title!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: titleColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // F141 修 3：`title == null && items.isEmpty`（只有一句正文的
                    // 极简通知，如 ⑤ 锁标提示）时把徽标→正文的间距收紧到 6 —— 否则
                    // 26pt（14+12）的空白会让「一句提示」看起来像一张庆祝大卡。
                    SizedBox(height: compact ? 6 : 14),
                    // 条目列表：图标块 + 名称 + 金色金额 + 细线分隔（不画首条上边线）。
                    for (int i = 0; i < items.length; i++) ...<Widget>[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: GoldNoticeStyle.dividerColor,
                        ),
                      _GoldNoticeItemRow(item: items[i]),
                    ],
                    // 底部文案：无条目时不画那条悬挂分隔线（否则卡片顶部会出现
                    // 一条无来由的横线）。既有两处调用方均「有条目 + 有 footer」，
                    // 故它们的渲染结果**逐像素不变**。
                    if (footerText != null) ...<Widget>[
                      if (items.isNotEmpty)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: GoldNoticeStyle.dividerColor,
                        ),
                      // compact（无标题无条目）时这条 12 已并入上面的 6，不重复叠加。
                      if (!compact) const SizedBox(height: 12),
                      Center(
                        child: Text(
                          footerText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: buttonBg,
                        foregroundColor: buttonFg,
                        minimumSize: const Size(0, 48),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed:
                          onConfirm ?? () => Navigator.of(context).pop(),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单条明细行（图标方块 + 名称[+ 副行] + 右侧金色金额）。
///
/// ## 宽度纪律（F141 修 1，QA 探针 F141-BUG-01 打回）
/// 旧实现把右侧金额写成 `Row` 的**非 flex 子节点**：Row 给它无界主轴约束，
/// 它按单行自然宽度铺开 → 长家长备注直接把行挤爆（实测 24 字备注溢出 213px、
/// 320×568 + 1.3 倍连兜底串都溢出 55px）。现口径：
///  · 名称（+ 副行）走 `Expanded(flex: 3)`、金额走 `Expanded(flex: 2)` ——
///    两个都**是 flex 子节点**，各自拿到「剩余宽度 × 占比」的**上界**，任何长度
///    都会自动折行，永远不会 RenderFlex 溢出；金额 `textAlign.right` 使其右缘
///    始终贴齐卡片内容右缘（与原「自然宽度靠右」视觉一致）。
///  · 金额为空串（`''`）时**整块不渲染**（② 的条目只有名称 + 副行，不占右列）。
///  · 副行是「说明」不是「金额」：小字号 + [GoldNoticeStyle.amountMuted] 弱化色，
///    与名称同列可折行，不再占用右列（语义与排版的单点修正）。
class _GoldNoticeItemRow extends StatelessWidget {
  final GoldNoticeItem item;

  const _GoldNoticeItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final bool hasAmount = item.amountText.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: <Widget>[
          Container(
            width: GoldNoticeStyle.itemTileSize,
            height: GoldNoticeStyle.itemTileSize,
            decoration: BoxDecoration(
              color: GoldNoticeStyle.itemTileBg,
              borderRadius:
                  BorderRadius.circular(GoldNoticeStyle.itemTileRadius),
            ),
            child: Icon(
              item.icon,
              size: 20,
              color: GoldNoticeStyle.amount,
            ),
          ),
          const SizedBox(width: 10),
          // 名称 + 副行（同列，均可在列宽内自由折行）。
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      // 弱化口径与原「备注走 amountMuted」一致：非加粗（w500）+
                      // 现有深金常量，说明文字绝不抢名称的视觉（不新造色值）。
                      fontWeight: FontWeight.w500,
                      color: GoldNoticeStyle.amountMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasAmount) ...<Widget>[
            const SizedBox(width: 8),
            // ⚠️ 必须是 flex 子节点（Expanded/Flexible）：非 flex 的 Text 在 Row 里
            // 拿无界宽度 → 长金额/备注直接溢出（本行注释即那次的教训）。
            Expanded(
              flex: 2,
              child: Text(
                item.amountText,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 16,
                  // 弱化行不抢视觉：非加粗 + 深金（见 [GoldNoticeItem.amountMuted]）。
                  fontWeight:
                      item.amountMuted ? FontWeight.w500 : FontWeight.bold,
                  color: item.amountMuted
                      ? GoldNoticeStyle.amountMuted
                      : GoldNoticeStyle.amount,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 以模态方式弹出金色通知卡（唯一弹窗入口，保证所有通知的弹出方式一致）。
///
/// 返回的 Future 在用户关闭卡片后完成 —— 调用方**必须**在 `await` 之后再写
/// 已读快照，否则「未看先读」会把卡片永久吞掉。
///
/// [barrierDismissible] 默认 true（点卡外可关，与 `showDialog` 默认一致）；
/// 既有两处通知卡行为不变。
///
/// [dialogKey] 透传给 [GoldNoticeDialog] 的 `key`（**只挂一层**，落在 `Dialog`
/// 子树的根 Widget 上）—— 测试要用 `find.byKey(...)` 精确定位某一张通知卡时用；
/// 为 null 时不挂 Key（默认，既有调用方行为不变）。
Future<void> showGoldNoticeDialog(
  BuildContext context, {
  Key? dialogKey,
  String? title,
  List<GoldNoticeItem> items = const <GoldNoticeItem>[],
  String? footerText,
  IconData badgeIcon = Icons.emoji_events,
  NoticeTone tone = NoticeTone.gold,
  String confirmLabel = GoldNoticeStyle.confirmLabel,
  bool barrierDismissible = true,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext ctx) => GoldNoticeDialog(
      key: dialogKey,
      title: title,
      items: items,
      footerText: footerText,
      badgeIcon: badgeIcon,
      tone: tone,
      confirmLabel: confirmLabel,
      onConfirm: () => Navigator.of(ctx).pop(),
    ),
  );
}
