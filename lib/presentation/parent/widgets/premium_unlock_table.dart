/// 购买页「解锁前后对比表」（付费墙 · 阶段 5 · 购买页改版 v1 §4 / §5.2）。
///
/// ## 定位
/// 两栏对比表（**免费版** ／ **解锁全部功能 ★**），嵌入购买页主卡与主按钮之间，
/// 让家长一眼看清「免费能做什么 / 买断后多出什么」。
///
/// ## 🔴 本组件刻意保持「守卫干净」
/// 本文件**不含任何权益标识符**（能力键 / 门控矩阵 / 配额查询 / 权益档位 …）——
/// 所有派生工作都在**已列入守卫白名单**的 `premium_gate.dart`（[unlockRowsFor]）
/// 里完成，本组件**只吃纯数据 + 一个 bool**。这样：
///  · 权益标识符源码守卫无需为本文件新增白名单条目；
///  · 门控判定与展示解耦（对比表**不做**门控判定，只做展示）。
///
/// ## 数据来源
///  · **B 组「买断后解锁」4 行**：[unlockRowsFor]（读矩阵派生，改矩阵即改表）；
///  · **A 组「免费就能用」8 行**：静态文案（这些能力不在门控矩阵内，是纯描述）。
///
/// ## 🔴 合规红线
/// 只列**真实生效**项；未实现能力一律**不得**写进任何对外文案（Apple 3.1.1 /
/// 2.3.1 拒审风险），由源码守卫兜底。
library premium_unlock_table;

import 'package:flutter/material.dart';

import 'package:sunflower_time/presentation/shared/cream_card.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';
import 'package:sunflower_time/shared/responsive.dart';

// ── 配色令牌（阶段 5 · 购买页改版 v1 §5.1；**免费列中性米白 / 暖金只给买断列**）──
const Color _kFreeColBg = Color(0xFFF5F1E8); // 免费列底（中性米白）
const Color _kFreePillBg = Color(0xFFEFEAE0); // 免费列胶囊底
const Color _kFreePillFg = Color(0xFF9C917E); // 免费列胶囊字（= _kInkSoft）
const Color _kGoldColBorder = Color(0xFFE8C56A); // 买断列描边（金）
const Color _kGoldPillDeep = Color(0xFFE8A600); // 买断列胶囊深金
const Color _kGoldPillLight = Color(0xFFFFCE5C); // 买断列胶囊浅金
const Color _kGoldText = Color(0xFF8D6E00); // 金色文字（分组带 / 已拥有）
const Color _kBandBg = Color(0xFFFFF8E6); // 分组带底
const Color _kLabelFg = Color(0xFF6B6252); // 项目列字
const Color _kCheckFree = Color(0xFF2E7D32); // 免费列 ✓（既有"已解锁绿"）
const Color _kCrossFree = Color(0xFFB0A08C); // 免费列 ✗
const Color _kGoldCheck = Color(0xFFE8A600); // 买断列 ✓（金）

/// 解锁前后对比表（两栏：**免费版** ／ **解锁全部功能 ★**）。
class PremiumUnlockTable extends StatelessWidget {
  /// 用户当前是否已解锁（由**已白名单**的购买页读取权益后传入）。
  ///
  /// false → 买断列顶显示「解锁全部功能 ★」为"目标态"；true → 追加「已拥有」小徽标。
  final bool isUnlocked;

  const PremiumUnlockTable({this.isUnlocked = false, super.key});

  /// A 组（「免费就能用」）静态行 —— **8 行**（7 核心 + 「家长专注报告」）。
  ///
  /// 🔴 「家长专注报告」行**如实写**「近 7 天 / 近 7 天」（矩阵里两栏同值）——
  /// 绝不夸大为"买断解锁更多报告能力"（Apple 3.1.1）；更深的分层能力由表下极简
  /// 脚注如实覆盖。
  static const List<({String label, String free, String premium})> _kFreeRows =
      <({String label, String free, String premium})>[
    (label: '专注番茄钟', free: '✓', premium: '✓'),
    (label: '防沉迷与作息', free: '✓', premium: '✓'),
    (label: '少儿护眼休息', free: '✓', premium: '✓'),
    (label: '花园养成', free: '✓', premium: '✓'),
    (label: '阳光经济与账本', free: '✓', premium: '✓'),
    (label: '商店兑换', free: '✓', premium: '✓'),
    (label: '专注等级 + 9 称号', free: '✓', premium: '✓'),
    (label: '家长专注报告', free: '近 7 天', premium: '近 7 天'),
  ];

  @override
  Widget build(BuildContext context) {
    final double s = uiScaleOf(context);
    final List<PremiumUnlockRow> derived = unlockRowsFor();

    final List<Widget> body = <Widget>[
      _headerRow(s),
      _groupBand('免费就能用', s),
      for (final ({String label, String free, String premium}) r in _kFreeRows)
        _dataRow(r.label, r.free, r.premium, true, s, premiumOk: true),
      _footNote('更多报告能力开发中', s),
      _groupBand('买断后解锁', s),
      _dataRow(
        derived[0].label,
        derived[0].freeText,
        derived[0].premiumText,
        derived[0].freeOk,
        s,
        premiumOk: derived[0].premiumOk,
      ),
      _dataRow(
        derived[1].label,
        derived[1].freeText,
        derived[1].premiumText,
        derived[1].freeOk,
        s,
        premiumOk: derived[1].premiumOk,
      ),
      if (derived[1].note != null) _footNote(derived[1].note!, s),
      _dataRow(
        derived[2].label,
        derived[2].freeText,
        derived[2].premiumText,
        derived[2].freeOk,
        s,
        premiumOk: derived[2].premiumOk,
      ),
      _dataRow(
        derived[3].label,
        derived[3].freeText,
        derived[3].premiumText,
        derived[3].freeOk,
        s,
        premiumOk: derived[3].premiumOk,
      ),
    ];

    return Container(
      decoration: creamCardDecoration(),
      padding: EdgeInsets.all(6 * s),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double w = constraints.maxWidth;
          // 三列比例 16 : 10 : 10（合计 36）→ 免费列/买断列各占 10/36，左列 16/36。
          final double unit = w / 36;
          return Stack(
            children: <Widget>[
              // 免费列（中性米白）——**金只给买断列**，此处刻意无金。
              Positioned(
                left: unit * 16,
                right: unit * 10,
                top: 0,
                bottom: 0,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: _kFreeColBg),
                ),
              ),
              // 买断列：**整列连续**金渐变 + 金描边 1.5 + 暖金柔光（跨行连续一列）。
              Positioned(
                left: unit * 26,
                right: 0,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0xFFFFFDF7), Color(0xFFFFF0C9)],
                    ),
                    borderRadius: BorderRadius.circular(16 * s),
                    border: Border.all(color: _kGoldColBorder, width: 1.5),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x33E8A600),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: body,
              ),
            ],
          );
        },
      ),
    );
  }

  /// 表头行：左列留白 / 中列「免费版」中性胶囊 / 右列「解锁全部功能 ★」金胶囊。
  Widget _headerRow(double s) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Expanded(flex: 16, child: SizedBox.shrink()),
          Expanded(
            flex: 10,
            child: Center(
              child: _chip('免费版', _kFreePillBg, _kFreePillFg, s),
            ),
          ),
          Expanded(
            flex: 10,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _goldChip('解锁全部功能 ★', s),
                  if (isUnlocked) ...<Widget>[
                    SizedBox(height: 4 * s),
                    const Text(
                      '已拥有',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kGoldText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分组标题带（**跨三列**，整行浅金底）。
  Widget _groupBand(String text, double s) => Container(
        width: double.infinity,
        color: _kBandBg,
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: _kGoldText,
          ),
        ),
      );

  /// 数据行：项目名 / 免费值 / 买断值 三列（等高 `Row`，用 [IntrinsicHeight] 保证
  /// 三列同行等高对齐；本表行数很少，无内在高度布局的性能顾虑）。
  Widget _dataRow(
    String label,
    String freeText,
    String premiumText,
    bool freeOk,
    double s, {
    required bool premiumOk,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: 16,
            child: _textCell(
              label,
              s,
              align: Alignment.centerLeft,
              color: _kLabelFg,
              weight: FontWeight.w600,
            ),
          ),
          Expanded(
            flex: 10,
            child: _textCell(
              freeText,
              s,
              align: Alignment.center,
              color: freeOk ? _kCheckFree : _kCrossFree,
              weight: FontWeight.w700,
            ),
          ),
          Expanded(
            flex: 10,
            child: _textCell(
              premiumText,
              s,
              align: Alignment.center,
              color: premiumOk ? _kGoldCheck : _kCrossFree,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// 单元格：定尺寸内边距（随平板放大）中的单行文本（最多 2 行、超长省略）。
  ///
  /// ⚠️ S2：`fontSize` 一律**裸常量**，绝不乘 `uiScaleOf` —— 文字缩放只吃
  /// `MediaQuery.textScaler`（否则平板双重缩放，C75 ⑤ 教训）。
  Widget _textCell(
    String text,
    double s, {
    required Alignment align,
    required Color color,
    required FontWeight weight,
  }) {
    return Container(
      alignment: align,
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 10 * s),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: align == Alignment.center ? TextAlign.center : TextAlign.left,
        style: TextStyle(fontSize: 13, fontWeight: weight, color: color),
      ),
    );
  }

  /// 表下极简脚注（小字，如实说明，如「更多报告能力开发中」/「扩容仍需花阳光」）。
  Widget _footNote(String text, double s) => Padding(
        padding: EdgeInsets.fromLTRB(18 * s, 4 * s, 10 * s, 6 * s),
        child: Text(
          '└ $text',
          style: const TextStyle(fontSize: 11, color: _kCrossFree),
        ),
      );

  /// 中性胶囊（免费列顶）。
  Widget _chip(String text, Color bg, Color fg, double s) => Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12 * s),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      );

  /// 金渐变胶囊（买断列顶，白字）。
  Widget _goldChip(String text, double s) => Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[_kGoldPillLight, _kGoldPillDeep],
          ),
          borderRadius: BorderRadius.circular(12 * s),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      );
}
