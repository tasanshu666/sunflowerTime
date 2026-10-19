/// 孩子端「金色确认卡」的**统一实现**（家长端处理结果告知孩子的唯一样式源）。
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
library gold_notice_dialog;

import 'package:flutter/material.dart';

/// 金色确认卡的样式常量（单点维护：配色 / 圆角 / 尺寸改这里，两张卡同时生效）。
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
  /// 用深金/琥珀 `0xFF8D6E00` 而非 `[amount]` 的亮金：孩子一眼能看出「这一行
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

  /// 卡片内容的最大高度占屏幕高度的比例（超出则**卡内滚动**，不溢出屏幕）。
  ///
  /// 为什么是 0.7：`Dialog` 自带 `insetPadding` 垂直 24，320×568 的小屏上
  /// 「3 条 + 最长合计文案 + 1.3 倍字号」真实需要约 520+，留出上下呼吸空间；
  /// 取 0.7 后大屏（>800 高）根本达不到该上界，故对正常机无任何影响。
  static const double maxHeightRatio = 0.7;
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

  /// 条目右侧金额文案（含符号与单位；金额不适用时可为说明性文字）。
  final String amountText;

  /// 金额是否**弱化显示**（默认金色加粗）。
  ///
  /// true 用于「这条确认了，但钱没到」的情形（F126 二轮：当日成长奖励额度
  /// 已满 → 实发 0 阳光）—— 此时 [amountText] 放「今日额度已满」这类文字，
  /// 用 [GoldNoticeStyle.amountMuted] + 非加粗渲染，绝不显示「+0 阳光」冒充到账。
  final bool amountMuted;

  const GoldNoticeItem({
    required this.icon,
    required this.name,
    required this.amountText,
    this.amountMuted = false,
  });
}

/// 金色确认卡本体（米色底 + 金色圆徽 + 标题 + 条目列表 + 合计 + 「知道啦」）。
///
/// 纯展示组件：不读 Provider、不做异步、不弹窗 —— 弹窗时机由调用方掌握
/// （孩子端外壳的已读去重逻辑在 `child_shell_page.dart`）。
class GoldNoticeDialog extends StatelessWidget {
  /// 卡头标题（含 emoji，例如 `🎉 家长已确认你的兑换`）。
  final String title;

  /// 明细条目（1..N 条；空列表时只显示标题 + 合计 + 按钮，仍可正常使用）。
  final List<GoldNoticeItem> items;

  /// 底部合计文案（例如 `共扣除 10 阳光` / `共获得 8 阳光`）。
  final String footerText;

  /// 卡头圆徽内的图标（默认金色奖杯 = 庆祝语义）。
  final IconData badgeIcon;

  /// 点「知道啦」的回调（默认由 [showGoldNoticeDialog] 传 `Navigator.pop`）。
  final VoidCallback? onConfirm;

  const GoldNoticeDialog({
    super.key,
    required this.title,
    required this.items,
    required this.footerText,
    this.badgeIcon = Icons.emoji_events,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
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
                  // 卡头庆祝元素：金色圆形徽 + 标题。
                  Center(
                    child: Column(
                      children: <Widget>[
                        Container(
                          width: GoldNoticeStyle.badgeSize,
                          height: GoldNoticeStyle.badgeSize,
                          decoration: const BoxDecoration(
                            color: GoldNoticeStyle.gold,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            badgeIcon,
                            color: Colors.white,
                            size: GoldNoticeStyle.badgeIconSize,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // ⚠️ 标题文案由调用方给：既有兑换卡的字面量被
                        // `nav_structure_test` 钉死，不要在本层改写。
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: GoldNoticeStyle.goldDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
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
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: GoldNoticeStyle.dividerColor,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      footerText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: GoldNoticeStyle.gold,
                      foregroundColor: GoldNoticeStyle.buttonFg,
                      minimumSize: const Size(0, 48),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: onConfirm ?? () => Navigator.of(context).pop(),
                    child: const Text(GoldNoticeStyle.confirmLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单条明细行（图标方块 + 名称 + 右侧金色金额）。
class _GoldNoticeItemRow extends StatelessWidget {
  final GoldNoticeItem item;

  const _GoldNoticeItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
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
          Expanded(
            child: Text(
              item.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            item.amountText,
            style: TextStyle(
              fontSize: 16,
              // 弱化行不抢视觉：非加粗 + 深金（见 [GoldNoticeItem.amountMuted]）。
              fontWeight: item.amountMuted ? FontWeight.w500 : FontWeight.bold,
              color: item.amountMuted
                  ? GoldNoticeStyle.amountMuted
                  : GoldNoticeStyle.amount,
            ),
          ),
        ],
      ),
    );
  }
}

/// 以模态方式弹出金色确认卡（唯一弹窗入口，保证两条通知的弹出方式一致）。
///
/// 返回的 Future 在用户关闭卡片后完成 —— 调用方**必须**在 `await` 之后再写
/// 已读快照，否则「未看先读」会把卡片永久吞掉。
Future<void> showGoldNoticeDialog(
  BuildContext context, {
  required String title,
  required List<GoldNoticeItem> items,
  required String footerText,
  IconData badgeIcon = Icons.emoji_events,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => GoldNoticeDialog(
      title: title,
      items: items,
      footerText: footerText,
      badgeIcon: badgeIcon,
      onConfirm: () => Navigator.of(ctx).pop(),
    ),
  );
}
