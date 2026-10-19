/// 孩子端「种植二次确认卡」（F134，玄参 2026-10-19 截图反馈
/// 「这个是种植确认卡片，可以帮我优化的漂亮一些吗？」）。
///
/// ## F135 变更（2026-10-19 第二轮，iPad Pro 13″ 实测）
/// 玄参反馈「太宽了，变窄一些」+ 四张确认卡样式不统一 → 本文件**降级为薄适配层**：
/// 卡壳 / 宽度收敛 / 按钮排布全部搬到共享的 [ChildConfirmCard]
/// （`child_confirm_card.dart`），本文件只负责把「种植」这件事翻译成标题 + 物种预览
/// + 明细行 + 剩余小结。由此本卡**自动获得**「平板宽度从 968 收窄到 544」的效果。
///
/// ## 改前是什么样（F134 之前）
/// 直接用 `AlertDialog` 默认样式：白底 Material 卡 + 纯文字两行
/// （`本次种植将扣除：300 ☀ / 当前阳光：1042 ☀`）+ 右下角两个系统按钮。
/// 与 App 通篇的奶油底 + 阳光金 + 圆角卡风格脱节，也看不出「种下后还剩多少」。
///
/// ## 结构
/// ```text
///        ┌─────────────┐
///        │   物种预览图   │   96 圆角浅金底 + SpeciesPreviewArt
///        └─────────────┘
///          要种下番茄吗？        标题（文案与改前逐字一致）
///   ┌──────────────────────────┐
///   │ 🌱 本次种植        −300 ☀ │  明细行（图标 + 名称 + 金额）
///   │ 🌞 当前阳光       1042 ☀ │
///   └──────────────────────────┘
///            种下后剩余 742 ☀     高亮小结（成本类支付才有）
///      [  取消  ]  [  确定种植  ]
/// ```
///
/// ## 不能动的东西（回归红线）
/// · 标题字面量 `要种下{物种名}吗？`、按钮字面量 `取消` / `确定种植` ——
///   `plant_species_pricing_test` / `qa_independent_p0_care_sfx_behavior_test`
///   用 `find.text` 钉死，改文案会直接红；
/// · 返回语义不变：确认 → `true`，取消 / 点外部关闭 → `null`/`false`，
///   调用方**一律不扣费**（领域层未被触达）。
library plant_confirm_dialog;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart'
    show
        ChildConfirmCard,
        ChildConfirmStyle,
        ConfirmCardRow,
        ConfirmCardTone,
        showChildConfirmCard;
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart'
    show GoldNoticeStyle;
import 'package:sunflower_time/presentation/child/widgets/plant_artwork.dart'
    show SpeciesPreviewArt;
import 'package:sunflower_time/shared/responsive.dart' show uiScaleOf;

/// 种植确认卡里的一条**明细行**。
///
/// F135 起统一为共享的 [ConfirmCardRow]（字段 / 语义完全相同），这里保留旧名
/// 是为了让既有调用方（`garden_page._confirmAndPlant`）与既有用例
/// （`test/m3/plant_confirm_dialog_test.dart` 的 `const PlantConfirmRow(...)`）
/// **一行都不用改**。
typedef PlantConfirmRow = ConfirmCardRow;

/// 种植确认卡的样式常量（与 [GoldNoticeStyle] / [ChildConfirmStyle] 同源）。
///
/// F135 起真正的尺寸口径全部搬进 [ChildConfirmStyle]（四张卡共用），本类只保留
/// 「种植卡特有」的物种预览尺寸与两个回归红线文案，供既有引用继续编译。
abstract final class PlantConfirmStyle {
  /// 物种预览图的底块边长（**独立于**共享卡壳：只有种植卡有物种预览）。
  static const double heroSize = 96;

  /// 物种预览图底块圆角。
  static const double heroRadius = 24;

  /// 取消按钮字面量（回归红线，勿改）。
  static const String cancelLabel = ChildConfirmStyle.cancelLabel;

  /// 确认按钮字面量（回归红线，勿改）。
  static const String confirmLabel = '确定种植';
}

/// 弹出种植确认卡。返回 `true` = 确认种植；`null` / `false` = 取消（不扣任何资源）。
Future<bool?> showPlantConfirmDialog({
  required BuildContext context,
  required PlantSpecies species,
  required List<PlantConfirmRow> rows,
  String? remainingText,
}) {
  return showChildConfirmCard(
    context: context,
    title: '要种下${species.name}吗？',
    hero: _SpeciesHero(species: species),
    rows: rows,
    note: remainingText,
    confirmLabel: PlantConfirmStyle.confirmLabel,
    cancelLabel: PlantConfirmStyle.cancelLabel,
    confirmTone: ConfirmCardTone.gold,
  );
}

/// 种植确认卡本体（纯展示；无 Provider、无异步）。
///
/// ⚠️ 仅用于「直接在 widget 树里挂一张卡」的场景（测试 / 预览）；
/// 生产代码统一走 [showPlantConfirmDialog] 以复用同一个弹窗入口。
class PlantConfirmDialog extends StatelessWidget {
  /// 目标物种（用于标题与预览图）。
  final PlantSpecies species;

  /// 明细行（1..N）。
  final List<PlantConfirmRow> rows;

  /// 底部高亮小结（如 `种下后剩余 742 ☀`）；为 null 不显示。
  final String? remainingText;

  const PlantConfirmDialog({
    super.key,
    required this.species,
    required this.rows,
    this.remainingText,
  });

  @override
  Widget build(BuildContext context) {
    return ChildConfirmCard(
      title: '要种下${species.name}吗？',
      hero: _SpeciesHero(species: species),
      rows: rows,
      note: remainingText,
      confirmLabel: PlantConfirmStyle.confirmLabel,
      cancelLabel: PlantConfirmStyle.cancelLabel,
      confirmTone: ConfirmCardTone.gold,
    );
  }
}

/// 物种预览：浅金圆角底 + 物种美术图（缺失时 [SpeciesPreviewArt] 自带兜底图标）。
class _SpeciesHero extends StatelessWidget {
  final PlantSpecies species;

  const _SpeciesHero({required this.species});

  @override
  Widget build(BuildContext context) {
    // 素材尺寸随平板倍率放大（C96/C97：文字走 textScaler，图形各自乘倍率）。
    final double s = uiScaleOf(context);
    final double side = PlantConfirmStyle.heroSize * s;
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: GoldNoticeStyle.itemTileBg,
        borderRadius: BorderRadius.circular(PlantConfirmStyle.heroRadius * s),
      ),
      padding: EdgeInsets.all(10 * s),
      child: SpeciesPreviewArt(species: species, size: side - 20 * s),
    );
  }
}
