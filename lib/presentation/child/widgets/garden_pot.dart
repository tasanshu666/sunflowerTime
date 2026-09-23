/// 草地上的花盆（2026-09-23 花园显示改造；同日二次改造：不再叠花盆图）。
///
/// ## 为什么有这个文件
/// 改造前花园是「纵向卡片列表」—— 一张卡一株植物，视觉上不像花园（玄参大人原话：
/// 「现在都是卡片形式，它根本就不像个花园」）。改造后**草地上摆花盆**，一个花盆一格：
///
/// ```
///   ┌────────┐ ┌────────┐ ┌────────┐
///   │  🌻    │ │  🌵    │ │ ⊕      │   ← 加盆格（只显示加号圆圈）
///   │ (自带盆)│ │ (自带盆)│ │        │
///   │ ▓▓▓░░░ │ │ ▓░░░░░ │ │        │   ← 空盆无进度条/标签
///   └────────┘ └────────┘ └────────┘
/// ```
///
/// ## 二次改造（2026-09-23）：只渲染一张图，不再叠花盆
/// 美术资源已统一重排为 **1200×2000 画布**（重排脚本 `tools/normalize_plant_art.py`），
/// 且**植物图本身自带花盆**（像素边界证实：盆宽 800 / 盆底贴画布底边 y=2000 /
/// 盆心居中 x=600，与 `pot.png` 完全一致）。因此一格内**只渲染 [PlantArtwork] 一张图**，
/// 不再叠 `assets/pots/pot.png` —— 否则一格会出现两个盆、边缘错位叠加
/// （用户原话「第一个花盆有一个圆圈显示得不干净」就是这么来的）。
///
/// 口径（玄参大人已拍板）：「代码不要自动叠花盆了，只要植物自带的花盆就行了。
/// 因为植物自带的花盆大小是可控的、是一样的。」
///
/// 统一口径后，代码只需「**按格宽等比缩放 + 底部对齐**」，所有阶段、所有格子的盆就自动
/// 等大且对齐；先前那套「植物底边压在盆口」的偏移计算（为「盆与植物分离」设计）已删除。
/// 枯萎 / 死亡等特殊状态**不做任何视觉叠加**（不加灰度、不加描边），改由用户产出的
/// `*_wilting.png` / `*_dead.png` 新美术图表达。
///
/// ## v3 改造（2026-09-24）
///  · 加号格的加号**对齐花盆视觉中心**（原先居中在整张画布高度正中，视觉上比花盆高一截）；
///  · 三类格子底部文案统一加半透明白胶囊底 + 加深字色（原先 11px 彩字直接压在草地上，
///    不可点态的浅灰几乎看不清）。
///
/// ## 职责边界（重要）
/// 本文件**只负责「长什么样」+ 点击回调**，不持有任何业务逻辑：
/// 养护动作、额度校验、扣费全部由 [PlantCareSheet] / `PlantGrowthService` 承担。
/// 因此换美术、调整花盆造型都不需要碰业务代码。
///
/// 植物外观走 [PlantArtwork]（美术资源到位即自动替换）；空盆仍优先使用
/// `assets/pots/pot.png`，缺失或加载失败时回退到 [CustomPaint] 自绘陶盆。
library garden_pot;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

import 'plant_artwork.dart';

/// 陶盆配色（自绘用，集中在此便于统一换色；仅在 `pot.png` 缺失时走这条兜底）。
class _PotColors {
  static const Color body = Color(0xFFC4704F);
  static const Color rim = Color(0xFFA8573A);
  static const Color soil = Color(0xFF6D4C41);
  static const Color bodyDead = Color(0xFF9E9E9E);
  static const Color rimDead = Color(0xFF757575);
}

/// 美术图统一画布宽高比（宽 : 高 = **1200 : 2000**）。
///
/// 依据：美术图已被统一重排为 1200×2000 透明底画布，且植物图自带花盆
/// （盆宽 800 / 盆底贴画布底边 y=2000 / 盆心居中 x=600）。代码只按此比例等比缩放，
/// 即可保证各阶段各格子的盆自动等大。重排脚本见 `tools/normalize_plant_art.py`。
const double _artAspectRatio = 2000 / 1200; // = 5/3 ≈ 1.6667

/// 美术图宽占格宽比例（留出格子边距，避免相邻格视觉粘连）。
const double _artWidthRatio = 0.86;

/// 加号格里的加号圆**圆心 y 在美术画布高度上的比例**（盆的视觉中心）。
///
/// 依据：`assets/pots/pot.png` 画布 1200×2000，其内容 alpha bbox = (200, 1318, 1001, 2000)，
/// 即盆内容只占画布 y 65.9%~100%，**盆的视觉中心在画布高度 82.95% 处**。
/// 加号圆必须对齐这条中心线，才与左右花盆「一样高」（玄参大人原话）。
const double kPotBodyCenterYFraction = 0.8295;

/// 加号格里的加号圆**外径占美术画布宽度的比例**（盆宽占画布宽比例）。
///
/// 依据：pot.png 内容 bbox 宽度 = 1001 - 200 = 801 ≈ 画布宽 1200 的 66.75%。
const double kPotBodyWidthFraction = 0.6675;

/// 加号圆外径相对于「盆宽」的系数（≈ 盆宽的 92%，视觉上略小于盆口）。
const double kExpandIconDiameterRatio = 0.92;

/// 花盆图下方「进度条 + 标签」区的固定高度（三类格子共用）。
///
/// 三类格子共用同一底部高度，才能保证**同一行内所有花盆底边横向对齐**：
/// 有植物盆的底边被进度条 + 标签顶起，空盆 / 加盆格若不留等高空位，就会比邻居低
/// 约 30px（一眼看去「空盆没对齐」）。
///
/// v3 改造：标签外包了一层半透明白胶囊（上下各 1px 内边距），故由 30 上调到 **32**，
/// 容纳 `4(间距) + 5(进度条) + 3(间距) + 胶囊(文字行高 + 上下各 1)`；同时保证最紧的
/// 320 屏仍不溢出：格内高 ≈ (94.67-4)×0.86×5/3 + 32 ≈ 162 ≤ 167（见 v3 布局测试实测）。
const double _footerHeight = 32;

/// 三类格子统一的横向内边距：让「空盆 / 有植物 / 加盆」可用宽一致 → 盆等大。
const double _horizontalPad = 2;

/// 三类格子统一的纵向内边距（仅上下各 4，用于和相邻行留白）。
const double _verticalPad = 4;

/// 三类格子底部文案统一的**胶囊底**（半透明白，压深草地上的字）。
///
/// ## 字色对比度（WCAG 2.x，QA 缺陷 3）
/// 胶囊底 `0xE6FFFFFF`（α≈0.902）压在草地上，composite ≈ `rgb(246,247,235)`
/// （`Color(0xFFF6F7EB)`）。各状态字色相对「composite」与「纯白（最坏情况）」的对比度：
///
/// | 状态 / 文案        | 颜色                | hex      | vs composite | vs 纯白 |
/// |--------------------|---------------------|----------|--------------|---------|
/// | growing（成长中）  | `teal.shade800`     | #00695C  | 6.12 ✅      | 6.62 ✅ |
/// | bloomed（开花）    | `green.shade800`    | #2E7D32  | 4.74 ✅      | 5.13 ✅ |
/// | wilting（枯萎）    | `deepOrange.shade900`| #BF360C | 5.18 ✅      | 5.60 ✅ |
/// | dead（已枯萎）     | `grey.shade700`     | #616161  | 5.73 ✅      | 6.19 ✅ |
/// | 加盆·可点          | `green.shade800`    | #2E7D32  | 4.74 ✅      | 5.13 ✅ |
/// | 加盆·还差（不可点）| `grey.shade700`     | #616161  | 5.73 ✅      | 6.19 ✅ |
///
/// ⚠️ 全部 ≥ 4.5:1。**换色前务必重算**：此前的 `orange.shade900`（#E65100）仅 3.50:1，
/// 已替换为 `deepOrange.shade900`。`*_scaled` 一律不用于文字。
const Color _labelPillColor = Color(0xE6FFFFFF);

/// 草地上的花盆网格（3 列）。
///
/// 抽成独立组件的原因之一是**可被测试度量**：布局参数（列数、间距、宽高比）
/// 只此一处，测试直接渲染本组件而不是在测试里复刻一份参数，
/// 「测试过 = 真机布局过」（见 `test/m3/garden_pot_layout_test.dart`）。
class GardenGrid extends StatelessWidget {
  /// 每格内容：花盆 / 空盆 / 加盆位。由调用方按 potIndex 顺序给。
  final List<Widget> cells;

  /// 列数（手机上 3 列；窄屏或平板可调）。
  final int columns;

  const GardenGrid({super.key, required this.cells, this.columns = 3});

  /// 格子宽高比 = 宽 / 高。
  ///
  /// 每格内容高 = 图高 + 底部标签区 [`_footerHeight`]，再叠加上下内边距 8：
  ///   = (格宽-4) × [_artWidthRatio] × [_artAspectRatio] + [_footerHeight] + 8
  ///   = 1.4333 × (格宽-4) + 40（取 320 屏：≈ 129.9 + 32 + 8 = 169.9）。
  /// 取 **0.54** 使最紧的 320 屏（测试宿主格宽 ≈ 88）也不溢出：
  ///   88 / 0.54 - 8 = 154.96 ≥ 150.4（见布局测试实测）。
  static const double cellAspectRatio = 0.54;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: columns,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: cellAspectRatio,
        children: cells,
      );
}

/// 花盆（含植物）—— 草地网格里的一格。
///
/// 只渲染**一张**植物美术图（其自带花盆）；底部对齐 + 按格宽等比缩放。
class GardenPot extends StatelessWidget {
  final Plant plant;
  final PlantSpecies species;

  /// 点击整格（弹养护面板）。
  final VoidCallback onTap;

  const GardenPot({
    super.key,
    required this.plant,
    required this.species,
    required this.onTap,
  });

  /// 状态色：与养护面板保持一致，进度条与图标用它。
  Color get _statusColor {
    switch (plant.status) {
      case PlantStatus.bloomed:
        return Colors.green.shade700;
      case PlantStatus.wilting:
        return Colors.orange.shade800;
      case PlantStatus.dead:
        return Colors.grey;
      case PlantStatus.growing:
        return Colors.teal.shade700;
    }
  }

  /// 标签字色：在 [_statusColor] 基础上**加深**，保证白色胶囊底上的对比度 ≥ 4.5:1
  /// （逐色对比度见 [_labelPillColor] 的 WCAG 表）。
  ///
  /// ⚠️ 枯萎态必须用 `deepOrange.shade900`（5.18:1）：原 `orange.shade900` 仅 **3.50:1**，
  /// 不达 WCAG AA（QA 缺陷 3）。
  Color get _labelColor {
    switch (plant.status) {
      case PlantStatus.bloomed:
        return Colors.green.shade800;
      case PlantStatus.wilting:
        return Colors.deepOrange.shade900;
      case PlantStatus.dead:
        return Colors.grey.shade700;
      case PlantStatus.growing:
        return Colors.teal.shade800;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _horizontalPad,
          vertical: _verticalPad,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth;
            final double artW = w * _artWidthRatio;
            final double artH = artW * _artAspectRatio;
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                // 只渲染植物图（其自带花盆）：底部对齐 + 按格宽等比缩放。
                // 各阶段美图统一 1200×2000、盆底贴画布底 → 各盆自动等大且对齐。
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: artW,
                    height: artH,
                    child: PlantArtwork(
                      plant: plant,
                      species: species,
                      size: artW,
                      tint: _statusColor,
                      // 盆必须恒定大小（用户口径「自带的花盆是可控的、是一样的」），
                      // 故**不做**随进度的整图缩放 —— 否则同一排花盆会大小不一。
                      // 生长反馈交给盆下的进度条（value: plant.growthProgress）。
                      growthScale: 0,
                    ),
                  ),
                ),
                // 固定高度的底部区（进度条 + 标签）：供空盆 / 加盆格留等高空位对齐。
                // MainAxisAlignment.end：让胶囊贴底 → 三类格子的文案底边严格齐平。
                SizedBox(
                  height: _footerHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      const SizedBox(height: 4),
                      // 盆下细进度条 + 阶段（草地上不写长文案，细节留给面板）。
                      SizedBox(
                        width: w * 0.72,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: plant.growthProgress.clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: Colors.black12,
                            color: _statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      // 标签：半透明白胶囊底 + 加深字色（压在草地上也看得清）。
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: w),
                        child: Container(
                          key: const Key('garden_pot_label'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _labelPillColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _labelColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 一格只写最短信息：特殊状态优先（孩子一眼看哪盆要救），否则写物种名。
  String get _label {
    switch (plant.status) {
      case PlantStatus.bloomed:
        return '${species.name} · 开花';
      case PlantStatus.wilting:
        return '${species.name} · 快救回';
      case PlantStatus.dead:
        return '${species.name} · 已枯萎';
      case PlantStatus.growing:
        return species.name;
    }
  }
}

/// 空花盆 —— 点击进入种植选择。
///
/// 玄参大人要求：空格只显示陶盆（去掉「+」圆圈与「点击种植」标签），并放大显示
/// 比例，让空盆在草地上更醒目、更易点。点击行为不变（[onTap] 透传给页面弹种植选择）。
///
/// 与 [GardenPot] 共用 [_artWidthRatio] / [_artAspectRatio] / [_footerHeight]：
/// 空盆与有植物盆**等大、同底**（否则空盆会比邻居低，看起来「没对齐」）。
class EmptyPot extends StatelessWidget {
  final int potIndex;
  final VoidCallback onTap;

  const EmptyPot({super.key, required this.potIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _horizontalPad,
          vertical: _verticalPad,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth;
            final double artW = w * _artWidthRatio;
            final double artH = artW * _artAspectRatio;
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                // 与有植物盆**同尺寸、同底**：同比例算出的图片框，底部对齐。
                // 图片框宽高与 pot.png 画布（1200×2000）同比例 → BoxFit.contain 不缩小。
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: artW,
                    height: artH,
                    child: _PotImage(
                      width: artW,
                      height: artH,
                      dead: false,
                      highlighted: false,
                    ),
                  ),
                ),
                // 等高空位（空盆无进度条 / 标签）：保证空盆底边与有植物盆底边齐平。
                // 带 Key：供 v3 布局测试度量「底部区底边」是否与两类文字胶囊齐平。
                const SizedBox(
                  key: Key('empty_pot_footer'),
                  height: _footerHeight,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 扩容花盆位 —— 草地上的第 N+1 个格子，点击走「确认卡 → 扣费」。
///
/// 三态互斥（沿用 M3 修订的三态口径，避免「看着能点却扣不了」）：
///  · [affordable] = false → 灰字「还差 N ☀」，**不可点**；
///  · [busy] = true → 不可点（养护动作进行中）；
///  · 否则 → 可点，格子上写明价格。
///
/// 只显示加号圆圈 + 价格 / 还差文案，**不叠花盆图**；占位高度与花盆图一致，
/// 保证与两类花盆格同底、行内标签对齐。加号圆心**对齐花盆视觉中心**
/// （见 [kPotBodyCenterYFraction]），而不是整张画布高度正中。
class ExpandPotSlot extends StatelessWidget {
  final int cost;

  /// 还差多少阳光（< 0 表示够）。
  final int shortfall;
  final bool busy;
  final VoidCallback onTap;

  const ExpandPotSlot({
    super.key,
    required this.cost,
    required this.shortfall,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool affordable = shortfall <= 0;
    return InkWell(
      onTap: (affordable && !busy) ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _horizontalPad,
          vertical: _verticalPad,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth;
            final double artW = w * _artWidthRatio;
            final double artH = artW * _artAspectRatio;
            // 环 / 图标用 [ring]；文案用加深的 [label]（白胶囊底上对比度够）。
            final Color ring = affordable ? Colors.green.shade700 : Colors.grey;
            final Color label =
                affordable ? Colors.green.shade800 : Colors.grey.shade700;

            // 加号圆：圆心落在盆心线（artH × kPotBodyCenterYFraction），
            // 外径 = 盆宽 × kExpandIconDiameterRatio。用 Positioned 精确定位，
            // 保证「严格可度量」（v3 测试用 getRect 断言误差 ≤ 3px）。
            final double diameter =
                artW * kPotBodyWidthFraction * kExpandIconDiameterRatio;
            final double centerY = artH * kPotBodyCenterYFraction;

            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                // 加盆格**只显示加号**（不叠花盆图）：占位高度 = 花盆图高，
                // 保证与两类花盆格同底、行内对齐。
                SizedBox(
                  key: const Key('expand_pot_artbox'),
                  width: artW,
                  height: artH,
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: (artW - diameter) / 2,
                        top: centerY - diameter / 2,
                        width: diameter,
                        height: diameter,
                        child: Container(
                          key: const Key('expand_pot_icon'),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.5),
                            border: Border.all(
                              color: ring.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.add_circle_outline,
                            size: diameter * 0.58,
                            color: ring,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 底部区等高位 + 文案（与有植物盆的「进度条 + 标签」同区）。
                // MainAxisAlignment.end：让胶囊贴底 → 三类格子的文案底边严格齐平。
                SizedBox(
                  height: _footerHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      const SizedBox(height: 4),
                      // 进度条槽位占位（加盆格无进度条），保证文案位置与邻居一致。
                      const SizedBox(height: 5),
                      const SizedBox(height: 3),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: w),
                        child: Container(
                          key: const Key('expand_pot_label'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _labelPillColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            affordable ? '加盆 · $cost☀' : '还差 $shortfall☀',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: label,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 陶盆绘制：盆身（上宽下窄 + 圆底）+ 口沿 + 土面（`pot.png` 缺失时的兜底）。
///
/// [dead] = true 时整体转灰；[highlighted] = true 时口沿描一圈暖色。
class _PotPainter extends CustomPainter {
  final bool dead;
  final bool highlighted;

  const _PotPainter({required this.dead, required this.highlighted});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double topY = h * 0.20;

    final Color body = dead ? _PotColors.bodyDead : _PotColors.body;
    final Color rim = dead ? _PotColors.rimDead : _PotColors.rim;

    // 盆身：上宽下窄，底部两角圆滑
    final Path pot = Path()
      ..moveTo(w * 0.12, topY)
      ..lineTo(w * 0.88, topY)
      ..lineTo(w * 0.76, h * 0.92)
      ..quadraticBezierTo(w * 0.73, h, w * 0.64, h)
      ..lineTo(w * 0.36, h)
      ..quadraticBezierTo(w * 0.27, h, w * 0.24, h * 0.92)
      ..close();
    canvas.drawPath(pot, Paint()..color = body);

    // 口沿（椭圆，比盆身略宽，做出「厚边」感）
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, topY),
        width: w * 0.80,
        height: h * 0.26,
      ),
      Paint()..color = rim,
    );

    // 土面
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, topY + h * 0.02),
        width: w * 0.64,
        height: h * 0.16,
      ),
      Paint()..color = dead ? Colors.grey.shade500 : _PotColors.soil,
    );

    // 需要处理的盆：口沿描暖色圈
    if (highlighted) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.5, topY),
          width: w * 0.80,
          height: h * 0.26,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.orange.shade700,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PotPainter old) =>
      old.dead != dead || old.highlighted != highlighted;
}

/// 花盆口沿高亮圈：使用图片花盆时，枯萎/死亡态需要额外描一圈橙色提示。
class _PotRimPainter extends CustomPainter {
  const _PotRimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double topY = h * 0.20;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, topY),
        width: w * 0.80,
        height: h * 0.26,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.orange.shade700,
    );
  }

  @override
  bool shouldRepaint(covariant _PotRimPainter oldDelegate) => false;
}

/// 花盆渲染：优先加载 `assets/pots/pot.png`；缺失/失败时回退 [_PotPainter]。
///
/// [dead] = true 时给图片加灰度滤镜；[highlighted] = true 时在盆沿上叠加
/// 橙色提示圈（与 [_PotPainter] 高亮效果一致）。
///
/// ⚠️ 传入的 [width] / [height] 必须与外部图片框（SizedBox）一致，且二者比例应等于
/// `pot.png` 画布比例（1200×2000）—— 否则 `BoxFit.contain` 会把图画小，空盆又变小。
class _PotImage extends StatelessWidget {
  final bool dead;
  final bool highlighted;
  final double width;
  final double height;

  const _PotImage({
    required this.dead,
    required this.highlighted,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      'assets/pots/pot.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) =>
          CustomPaint(
        size: Size(width, height),
        painter: _PotPainter(dead: dead, highlighted: highlighted),
      ),
    );

    if (dead) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: image,
      );
    }

    if (!highlighted) return image;

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        image,
        CustomPaint(
          size: Size(width, height),
          painter: const _PotRimPainter(),
        ),
      ],
    );
  }
}
