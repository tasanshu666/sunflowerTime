/// 孩子端「二次确认卡」的**统一卡壳**（F135，玄参 2026-10-19 iPad Pro 13″ 实测反馈
/// 「太宽了，变窄一些」+ 三张确认卡样式不统一）。
///
/// ## 为什么再抽一层（上一轮已有 `plant_confirm_dialog.dart`）
/// 上一轮（F134）只把**种植**确认卡做成了奶油底 + 阳光金的漂亮卡片，其余三张
/// （扩容 / 铲除 / 一键护理）仍是 `AlertDialog` 默认白底 Material 卡 —— 同一个
/// App 里「点不同按钮弹出两种截然不同的卡片」，且平板上被撑到 968 宽（iPad 13″
/// 逻辑宽 1032 − 左右 inset 64），一行只有十来个字，像一张空白表格。
///
/// 故把**卡壳**（弹窗容器 / 圆角 / 投影 / 标题 / 明细面板 / 按钮排布 / 限宽限高）
/// 收成本文件，四张卡全部改成 `ChildConfirmCard` 的薄适配层：
/// ```text
///        ┌───────────────────┐  ← 宽度上限 340 × uiScale（手机 326 / iPad13 544）
///        │       ◯ 金徽       │  hero（可空：种植卡放物种预览图）
///        │    要一键浇水吗？     │  title（文案由调用方给，逐字不变）
///        │  铲除后这株会消失。   │  warning（可空：破坏性操作的后果说明）
///        │ ┌───────────────┐ │
///        │ │ ☀ 本次合计  −6 ☀│ │  rows（图标 + 名称 + 金额）
///        │ │ 🌞 当前阳光 1042☀│ │
///        │ └───────────────┘ │
///        │     将对 3 盆各浇 1 次 │  note（可空：高亮小结）
///        │   [ 取消 ]  [ 确定 ]  │
///        └───────────────────┘
/// ```
///
/// ## 宽度收敛（本轮核心诉求）
/// 上限 = [ChildConfirmStyle.maxWidth]（340）× [uiScaleOf]：
///  · 手机 390 逻辑宽：`Dialog` inset 32 → 可用 326，**取 326**（与改前一致，手机零回归）；
///  · iPad Pro 13″（1032 → 倍率 1.6）：上限 544，**远窄于改前的 968**；
///  · 手机 320 宽：卡片 = 320 − `insetPadding`(32×2) = **256**（宽度纯由屏幕约束决定，
///    与本卡 `maxWidth` 无关）。注：`Dialog` 本身没有最小宽度约束，`minWidth: 280`
///    是 `AlertDialog` 内部的硬编码常量 —— 本卡走的是 `Dialog`，不受它影响；
///    大字号下靠限高 + 卡内滚动兜底，不溢出。
///
/// ## 与 [GoldNoticeStyle] 的关系
/// 配色 / 投影**逐字复用** `GoldNoticeStyle`（米色卡底 / 阳光金 / 深金文字 / 卡片投影），
/// 不新造色值 —— 避免「两张卡各自漂移」的老问题（见 `gold_notice_dialog.dart` 头注释）。
/// 唯一新增的是**破坏性操作（铲除）的红档** [ConfirmCardTone.danger]。
///
/// ## 尺寸口径（C96 / C97，违反会在平板上溢出）
/// · **图形 / 圆角 / 间距**：一律 `常量 × uiScaleOf(context)`；
/// · **文字**：只由 `MediaQuery.textScaler` 放大，**本文件绝不乘 uiScale**（否则双重放大）。
library child_confirm_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart'
    show GoldNoticeStyle;
import 'package:sunflower_time/shared/responsive.dart' show uiScaleOf;

/// 确认按钮的**语气档位**。
enum ConfirmCardTone {
  /// 常规正向操作（种植 / 扩容 / 一键护理）：阳光金实心按钮。
  gold,

  /// **破坏性**操作（铲除）：红底白字按钮 + 红色徽标，让孩子一眼看出「这条不可撤回」。
  danger,
}

/// 确认卡里的一条**明细行**（左侧图标 + 名称，右侧金额）。
///
/// [value] 由调用方格式化（`−300 ☀` / `+150 ☀` / `1 张` / `免费`）：本文件只管排版，
/// 不把「阳光 / 种子 / 碎片」的语义渗进样式层。
@immutable
class ConfirmCardRow {
  /// 行首图标（阳光 / 种子券 / 碎片 / 铲除返还）。
  final IconData icon;

  /// 行名（`本次种植` / `当前阳光` / `返还种植阳光`）。
  final String name;

  /// 右侧取值文案（已含符号与单位）。
  final String value;

  /// 是否**弱化**（用于 `当前阳光` 这类「参考值」而非「本次动作」）。
  final bool muted;

  const ConfirmCardRow({
    required this.icon,
    required this.name,
    required this.value,
    this.muted = false,
  });
}

/// 确认卡的样式常量（与 [GoldNoticeStyle] 同源；改这里 = 四张卡同时生效）。
abstract final class ChildConfirmStyle {
  /// 卡片**最大宽度基准**（真实上限 = 本值 × `uiScaleOf(context)`）。
  ///
  /// 340 的来历：手机 390 − `Dialog` 左右 inset 64 = 326，取略大的 340 让手机
  /// 「顶满可用宽度」（与改前视觉一致），而平板上 340×1.6 = 544 才收得住
  /// —— 改前平板是 968（几乎铺满 1032 的屏），被玄参判为「太宽了」。
  static const double maxWidth = 340;

  /// 卡片圆角。
  static const double cardRadius = 26;

  /// 明细面板圆角。
  static const double panelRadius = 14;

  /// 卡片内容最大高度占屏幕高度的比例（小屏 + 大字号溢出兜底，F126 老坑位）。
  ///
  /// 超出则**卡内滚动**；内容不超高时 `ConstrainedBox` 只给上界，卡片高度
  /// 仍等于内容高度（不出现滚动条）。
  static const double maxHeightRatio = 0.7;

  /// 卡头圆形徽标直径。
  static const double badgeSize = 76;

  /// 卡头圆形徽标内图标尺寸。
  static const double badgeIconSize = 36;

  /// 取消按钮字面量（回归红线，勿改：多条既有用例用 `find.text('取消')` 钉死）。
  static const String cancelLabel = '取消';

  /// 破坏性操作的主色（红）。
  static const Color danger = Color(0xFFE5544B);

  /// 破坏性操作的**深红**（标题 / 高亮小结文字，保证米色底上的对比度）。
  static const Color dangerDeep = Color(0xFFB3261E);
}

/// 卡头圆形徽标（金档 = 阳光金 + 白图标；红档 = 警示红 + 白图标）。
///
/// 单独成类而不塞进 [ChildConfirmCard]：扩容 / 铲除 / 一键护理三张卡共用同一种
/// 「圆形图标徽」而**不需要**物种预览图，抽出来调用方一行就能给 `hero`。
class ConfirmCardBadge extends StatelessWidget {
  /// 徽标内图标（`Icons.yard` / `Icons.delete_outline` / `Icons.water_drop`）。
  final IconData icon;

  /// 语气档位（决定底色）。
  final ConfirmCardTone tone;

  const ConfirmCardBadge({
    super.key,
    required this.icon,
    this.tone = ConfirmCardTone.gold,
  });

  @override
  Widget build(BuildContext context) {
    final double s = uiScaleOf(context);
    return Container(
      width: ChildConfirmStyle.badgeSize * s,
      height: ChildConfirmStyle.badgeSize * s,
      decoration: BoxDecoration(
        color: tone == ConfirmCardTone.danger
            ? ChildConfirmStyle.danger
            : GoldNoticeStyle.gold,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: ChildConfirmStyle.badgeIconSize * s,
      ),
    );
  }
}

/// 孩子端二次确认卡本体（纯展示，无 Provider、无异步、无业务判断）。
///
/// 点「取消」→ `Navigator.pop(false)`；点确认 → `Navigator.pop(true)`；
/// 点卡外 / 系统返回 → `null`。调用方一律按 `ok == true` 才执行扣费类动作。
class ChildConfirmCard extends StatelessWidget {
  /// 卡片本体（奶油底圆角 Container）的 Key。
  ///
  /// 供测试用 `tester.getSize(find.byKey(...))` 断言**真实渲染宽度**
  /// （`find.byType(ChildConfirmCard)` 拿到的是 `Dialog` 的全屏 RenderObject，
  /// 量不出卡片宽度）。
  static const Key surfaceKey = Key('child_confirm_card_surface');

  /// 标题（文案由调用方给，**逐字不变** —— 被多条既有用例 `find.text` 钉死）。
  final String title;

  /// 卡头元素：物种预览图 / 圆形金徽；为 null 则卡头留白不留空。
  final Widget? hero;

  /// 明细行（0..N 条；空列表时只显示标题 + 小结 + 按钮）。
  final List<ConfirmCardRow> rows;

  /// **中性正文**（可选）：纯陈述句，既不是警告也不是数字小结。
  ///
  /// F141 新增：退出专注确认（`向日葵还在这儿陪着你，要现在结束专注吗？`）、
  /// 护眼提前结束确认、付费引导正文本质都是**中性陈述**，塞进 [warning] 会变
  /// 红字警告、塞进 [note] 会变成金色加粗小结 —— 按 C103 口径两者**禁混用**。
  /// 故单独开一槽，位置在 [title] 与 [warning] 之间，取
  /// [GoldNoticeStyle.buttonFg]（App 既有深棕正文色）而非新造色值。
  final String? message;

  /// **后果说明**（可选）：破坏性操作必填（如 `铲除后这株植物会消失。`）。
  ///
  /// 与 [note] 分开是因为两者语义不同：warning 讲「会发生什么」（警示色、小字、紧贴
  /// 标题），note 讲「小结数字」（强调色、加粗、紧贴明细面板）。
  final String? warning;

  /// 底部高亮小结（如 `花园容量：4 盆 → 5 盆` / `种下后剩余 742 ☀`）；null 不显示。
  final String? note;

  /// 确认按钮文案（`确定种植` / `确定，扣除` / `确定铲除` / `确定`）。
  final String confirmLabel;

  /// 取消按钮文案（默认 [ChildConfirmStyle.cancelLabel]）。
  final String cancelLabel;

  /// 确认按钮语气档（金 / 红）。
  final ConfirmCardTone confirmTone;

  const ChildConfirmCard({
    super.key,
    required this.title,
    this.hero,
    this.rows = const <ConfirmCardRow>[],
    this.message,
    this.warning,
    this.note,
    required this.confirmLabel,
    this.cancelLabel = ChildConfirmStyle.cancelLabel,
    this.confirmTone = ConfirmCardTone.gold,
  });

  @override
  Widget build(BuildContext context) {
    final double s = uiScaleOf(context);
    final Size screen = MediaQuery.sizeOf(context);
    final bool danger = confirmTone == ConfirmCardTone.danger;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      // 🔴 宽度收敛：340 × 倍率（手机 326 / iPad13 544）；限高 + 卡内滚动防溢出。
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ChildConfirmStyle.maxWidth * s,
          maxHeight: screen.height * ChildConfirmStyle.maxHeightRatio,
        ),
        child: Container(
          key: surfaceKey,
          decoration: BoxDecoration(
            color: GoldNoticeStyle.cardBg,
            borderRadius: BorderRadius.circular(ChildConfirmStyle.cardRadius),
            boxShadow: const <BoxShadow>[GoldNoticeStyle.shadow],
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20 * s, 20 * s, 20 * s, 16 * s),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (hero != null) ...<Widget>[
                    Center(child: hero!),
                    SizedBox(height: 12 * s),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: danger
                          ? ChildConfirmStyle.dangerDeep
                          : GoldNoticeStyle.goldDeep,
                    ),
                  ),
                  // F141：中性正文槽（在标题与 warning 之间；两者正交，可同时出现）。
                  if (message != null) ...<Widget>[
                    SizedBox(height: 8 * s),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: GoldNoticeStyle.buttonFg.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  if (warning != null) ...<Widget>[
                    SizedBox(height: 6 * s),
                    Text(
                      warning!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: danger
                            ? ChildConfirmStyle.dangerDeep
                                .withValues(alpha: 0.85)
                            : Colors.brown.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                  if (rows.isNotEmpty) ...<Widget>[
                    SizedBox(height: 14 * s),
                    _buildPanel(s),
                  ],
                  if (note != null) ...<Widget>[
                    SizedBox(height: 12 * s),
                    Center(
                      child: Text(
                        note!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: danger
                              ? ChildConfirmStyle.dangerDeep
                              : GoldNoticeStyle.amount,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: 18 * s),
                  _buildActions(context, s),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 明细面板：米白底圆角块 + 逐行（名称左、金额右），行间细线分隔。
  Widget _buildPanel(double s) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(ChildConfirmStyle.panelRadius * s),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 4 * s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: GoldNoticeStyle.dividerColor,
              ),
            _RowLine(row: rows[i], scale: s),
          ],
        ],
      ),
    );
  }

  /// 底部按钮：取消（弱化）+ 确认（实心，占主要宽度，儿童手指友好 48 高）。
  ///
  /// 窄卡（320 屏）上取消按钮**不占固定 72 宽**：用 `shrinkWrap` 语义的
  /// `minimal` 内边距 + 仅 44 最小宽，把宽度让给确认按钮，避免大字号下折行。
  Widget _buildActions(BuildContext context, double s) {
    final bool danger = confirmTone == ConfirmCardTone.danger;
    return Row(
      children: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: danger
                ? ChildConfirmStyle.dangerDeep.withValues(alpha: 0.75)
                : GoldNoticeStyle.goldDeep.withValues(alpha: 0.75),
            minimumSize: Size(56 * s, 48 * s),
            padding: EdgeInsets.symmetric(horizontal: 10 * s),
            textStyle: const TextStyle(fontSize: 16),
          ),
          child: Text(cancelLabel),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger
                  ? ChildConfirmStyle.danger
                  : GoldNoticeStyle.gold,
              foregroundColor:
                  danger ? Colors.white : GoldNoticeStyle.buttonFg,
              minimumSize: Size(0, 48 * s),
              padding: EdgeInsets.symmetric(horizontal: 12 * s),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16 * s),
              ),
            ),
            child: Text(confirmLabel),
          ),
        ),
      ],
    );
  }
}

/// 单行明细：图标 + 名称（可折行）+ 右侧金额（不折行）。
class _RowLine extends StatelessWidget {
  final ConfirmCardRow row;
  final double scale;

  const _RowLine({required this.row, required this.scale});

  @override
  Widget build(BuildContext context) {
    final Color nameColor = row.muted
        ? Colors.brown.withValues(alpha: 0.62)
        : const Color(0xFF5D4200);
    final Color valueColor =
        row.muted ? Colors.brown.withValues(alpha: 0.62) : GoldNoticeStyle.amount;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 9 * scale),
      child: Row(
        children: <Widget>[
          Icon(
            row.icon,
            size: 18 * scale,
            color: row.muted
                ? Colors.brown.withValues(alpha: 0.45)
                : GoldNoticeStyle.gold,
          ),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              row.name,
              style: TextStyle(
                fontSize: 15,
                color: nameColor,
                fontWeight: row.muted ? FontWeight.normal : FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 8 * scale),
          Text(
            row.value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: row.muted ? FontWeight.normal : FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// 以模态方式弹出统一确认卡（**唯一弹窗入口**，保证四张卡的弹出方式一致）。
///
/// 返回 `true` = 确认；`false` = 取消；`null` = 点外部 / 系统返回。
/// 调用方一律写 `if (ok != true) return;` —— 「取消分毫不扣」是硬契约。
///
/// [barrierDismissible] 默认 true（与 `showDialog` 默认一致）；原实现里
/// `barrierDismissible: false` 的两处（专注退出 / 护眼提前结束）**逐字透传 false**，
/// 保证「点卡外不误关」的既有语义不变。
Future<bool?> showChildConfirmCard({
  required BuildContext context,
  required String title,
  Widget? hero,
  List<ConfirmCardRow> rows = const <ConfirmCardRow>[],
  String? message,
  String? warning,
  String? note,
  required String confirmLabel,
  String cancelLabel = ChildConfirmStyle.cancelLabel,
  ConfirmCardTone confirmTone = ConfirmCardTone.gold,
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext ctx) => ChildConfirmCard(
      title: title,
      hero: hero,
      rows: rows,
      message: message,
      warning: warning,
      note: note,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmTone: confirmTone,
    ),
  );
}
