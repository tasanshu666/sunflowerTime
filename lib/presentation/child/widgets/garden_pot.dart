/// 草地上的花盆（2026-09-23 花园显示改造）。
///
/// ## 为什么有这个文件
/// 改造前花园是「纵向卡片列表」—— 一张卡一株植物，视觉上不像花园（玄参大人原话：
/// 「现在都是卡片形式，它根本就不像个花园」）。改造后**草地上摆花盆**，一个花盆一格：
///
/// ```
///   ┌────────┐ ┌────────┐ ┌────────┐
///   │  🌻    │ │  🌵    │ │   +    │   ← 空盆（点击种植）
///   │ ╭────╮ │ │ ╭────╮ │ │ ╭────╮ │
///   │ ╰─盆─╯ │ │ ╰─盆─╯ │ │ ╰─盆─╯ │
///   │ ▓▓▓░░░ │ │ ▓░░░░░ │ │        │   ← 盆下细进度条
///   └────────┘ └────────┘ └────────┘
/// ```
///
/// ## 职责边界（重要）
/// 本文件**只负责「长什么样」+ 点击回调**，不持有任何业务逻辑：
/// 养护动作、额度校验、扣费全部由 [PlantCareSheet] / `PlantGrowthService` 承担。
/// 因此换美术、调整花盆造型都不需要碰业务代码。
///
/// 植物外观走 [PlantArtwork]（美术资源到位即自动替换）；花盆本身是 [CustomPaint]
/// 自绘的陶盆（口沿 + 盆身 + 土面），无美术依赖。
library garden_pot;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

import 'plant_artwork.dart';

/// 陶盆配色（自绘用，集中在此便于统一换色）。
class _PotColors {
  static const Color body = Color(0xFFC4704F);
  static const Color rim = Color(0xFFA8573A);
  static const Color soil = Color(0xFF6D4C41);
  static const Color bodyDead = Color(0xFF9E9E9E);
  static const Color rimDead = Color(0xFF757575);
}

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

  /// 格子宽高比：内容高度 ≈ 宽 × 0.95（植物+盆）+ 进度条 + 标签，
  /// 取 0.72 留出余量，避免格子比内容矮导致溢出。
  static const double cellAspectRatio = 0.72;

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

  bool get _isDead => plant.status == PlantStatus.dead;

  /// 状态色：与养护面板保持一致，进度条与高亮都用它。
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

  /// 花的/蔫的/死的盆换色：一眼能看出哪盆需要救。
  bool get _alerted =>
      plant.status == PlantStatus.wilting || plant.status == PlantStatus.dead;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth;
            final double potH = w * 0.42;
            final double plantSize = w * 0.86;
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                // 植物 + 花盆叠放：植物底边压在盆口上，看起来是「种在盆里」。
                SizedBox(
                  height: w * 0.95,
                  width: w,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned(
                        bottom: potH * 0.52,
                        child: PlantArtwork(
                          plant: plant,
                          species: species,
                          size: plantSize,
                          tint: _statusColor,
                          // 浇一次水看得见变化：进度 0 → 略小，进度 1 → 满格。
                          growthScale: 0.18,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        child: CustomPaint(
                          size: Size(w * 0.92, potH),
                          painter: _PotPainter(
                            dead: _isDead,
                            highlighted: _alerted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // 盆下细进度条 + 阶段（草地上不写长文案，细节留给面板）。
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: plant.growthProgress.clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: Colors.black12,
                    color: _statusColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _statusColor,
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
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth;
            final double potH = w * 0.42;
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                SizedBox(
                  height: w * 0.95,
                  width: w,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[
                      Positioned(
                        bottom: potH * 0.52,
                        child: Container(
                          width: w * 0.52,
                          height: w * 0.52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.55),
                            border: Border.all(
                              color: Colors.brown.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.add,
                            size: w * 0.30,
                            color: Colors.brown.shade400,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        child: CustomPaint(
                          size: Size(w * 0.92, potH),
                          painter: const _PotPainter(dead: false, highlighted: false),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '点击种植',
                  style: TextStyle(fontSize: 11, color: Colors.brown.shade600),
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
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth;
            final double potH = w * 0.42;
            final Color tint =
                affordable ? Colors.green.shade700 : Colors.grey;
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                SizedBox(
                  height: w * 0.95,
                  width: w,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[
                      Positioned(
                        bottom: potH * 0.52,
                        child: Container(
                          width: w * 0.54,
                          height: w * 0.54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.5),
                            border: Border.all(
                              color: tint.withOpacity(0.6),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.add_circle_outline,
                            size: w * 0.28,
                            color: tint,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        child: CustomPaint(
                          size: Size(w * 0.92, potH),
                          painter:
                              const _PotPainter(dead: false, highlighted: false),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  affordable ? '加盆 · $cost☀' : '还差 $shortfall☀',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: tint,
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

/// 陶盆绘制：盆身（上宽下窄 + 圆底）+ 口沿 + 土面。
///
/// [dead] = true 时整体转灰（死掉的植物配一个灰盆，比只改植物颜色更好辨认）；
/// [highlighted] = true 时口沿描一圈暖色（枯萎/死亡需要处理）。
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
