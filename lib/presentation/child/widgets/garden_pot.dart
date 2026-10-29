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
/// 美术资源已统一重排为 **1440×2000 画布**（重排脚本 `tools/normalize_plant_art.py`，
/// 2026-10-09 由 1200×2000 等高加宽到 1720：全局等盆宽 800；2026-10-11 玄参拍板
/// 收窄到 1440——「不常用素材不能影响整个画面」，超宽垂叶真裁 6 张、其余无损收框，
/// 裁切脚本 `tools/trim_canvas_1440.py`），且**植物图本身自带花盆**（像素边界证实：
/// 盆宽 800 / 盆底贴画布底边 y=2000 / 盆心居中 x=720；旧 sunflower/pot.png 为
/// 1200×2000、盆心 x=600，contain 按高度绑定缩放，盆显示大小与新图完全一致）。
/// 因此一格内**只渲染
/// [PlantArtwork] 一张图**，不再叠 `assets/pots/pot.png` —— 否则一格会出现两个盆、
/// 边缘错位叠加（用户原话「第一个花盆有一个圆圈显示得不干净」就是这么来的）。
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
/// ## 🔴 测试禁令：本组件含**无限动画**（F135 `_PestIdleWobble`）
/// 害虫浮标带待机微动（`AnimationController(1400ms)..repeat(reverse: true)`），
/// 加上花园页木牌的呼吸动画，本子树**永不 settle**。
///  · 任何挂载「含害虫花盆」的用例**禁用 `pumpAndSettle`** —— 它会一直等到超时挂死；
///  · 改用 `pump(Duration)` 定量推进（或 `pumpUntil` 条件推进），见
///    `test/m3/garden_pest_idle_animation_test.dart` 头注释与
///    `one_click_batch_hint_center_test` 的同款纪律；
///  · 注：隐藏 tab 已被外壳 `TickerMode(enabled: false)` 包住，`SingleTickerProviderStateMixin`
///    会自动 mute —— 那只保证「切走的 tab 不耗电」，**不改变**上面那条禁令
///    （只要害虫在可见帧里，`pumpAndSettle` 就等不到 settle）。
///
/// ## 职责边界（重要）
/// 本文件**只负责「长什么样」+ 点击回调**，不持有任何业务逻辑：
/// 养护动作、额度校验、扣费全部由 [PlantCareCard] / `PlantGrowthService` 承担。
/// 因此换美术、调整花盆造型都不需要碰业务代码。
///
/// 植物外观走 [PlantArtwork]（美术资源到位即自动替换）；空盆仍优先使用
/// `assets/pots/pot.png`，缺失或加载失败时回退到 [CustomPaint] 自绘陶盆。
library garden_pot;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/shared/plant_rarity_style.dart';
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

import 'plant_artwork.dart';
import 'package:sunflower_time/core/i18n/species_l10n.dart';

/// 陶盆配色（自绘用，集中在此便于统一换色；仅在 `pot.png` 缺失时走这条兜底）。
class _PotColors {
  static const Color body = Color(0xFFC4704F);
  static const Color rim = Color(0xFFA8573A);
  static const Color soil = Color(0xFF6D4C41);
  static const Color bodyDead = Color(0xFF9E9E9E);
  static const Color rimDead = Color(0xFF757575);
}

/// 美术图统一画布宽高比（宽 : 高 = **1440 : 2000**）。
///
/// 依据：美术图已被统一重排为 1440×2000 透明底画布（2026-10-11 由 1720 收窄），
/// 且植物图自带花盆（盆宽 800 / 盆底贴画布底边 y=2000 / 盆心居中 x=720）。
/// 代码只按此比例等比缩放，即可保证各阶段各物种的盆自动等大（2026-10-09 全局
/// 等盆口径）。重排脚本见 `tools/normalize_plant_art.py`。
// 2026-09-29：收口到 `prd_params.dart`（养护效果帧要按同一套参数算「盆口 / 根部」
// 落点，两份参数必然漂移）。值未变，仅改指向。
const double _artAspectRatio = kGardenArtAspect; // = 2000/1440 ≈ 1.3889

/// 美术图宽占格宽比例（留出格子边距，避免相邻格视觉粘连）。
const double _artWidthRatio = kGardenArtWidthRatio;

/// 加号格里的加号圆**圆心 y 在美术画布高度上的比例**（盆的视觉中心）。
///
/// 依据：`assets/pots/pot.png` 画布 1200×2000，其内容 alpha bbox = (200, 1318, 1001, 2000)，
/// 即盆内容只占画布 y 65.9%~100%，**盆的视觉中心在画布高度 82.95% 处**。
/// 加号圆必须对齐这条中心线，才与左右花盆「一样高」（玄参大人原话）。
const double kPotBodyCenterYFraction = 0.8295;

/// 加号格里的加号圆**外径占美术画布宽度的比例**（盆宽占画布宽比例）。
///
/// 依据：`assets/pots/pot.png`（1200×2000）内容 bbox 宽 = 1001 − 200 = 801 ≈ 盆身。
/// 2026-10-09 画布加宽到 1720×2000、2026-10-11 收窄到 1440×2000 后，pot.png 在
/// 图片框内始终按**高度绑定** contain 缩放（缩放系数 = artW/1440，与 1440 画布的
/// 植物图一致），故盆身显示宽占比 = 801 / 1440 —— 与植物图盆宽 800/1440 差
/// 0.1%，加号圆与两侧花盆等大。
const double kPotBodyWidthFraction = 801 / 1440;

/// 加号圆外径相对于「盆宽」的系数（≈ 盆宽的 92%，视觉上略小于盆口）。
const double kExpandIconDiameterRatio = 0.92;

/// 花盆图下方「进度条 + 标签」区高度（三类格子共用）。
///
/// 三类格子共用同一底部高度，才能保证**同一行内所有花盆底边横向对齐**：
/// 有植物盆的底边被进度条 + 标签顶起，空盆 / 加盆格若不留等高空位，就会比邻居低
/// 约 30px（一眼看去「空盆没对齐」）。
///
/// v3 改造：标签外包了一层半透明白胶囊（上下各 1px 内边距），故由 30 上调到 **32**，
/// 容纳 `4(间距) + 5(进度条) + 3(间距) + 胶囊(文字行高 + 上下各 1)`；同时保证最紧的
/// 320 屏仍不溢出：格内高 ≈ (94.67-4)×0.86×5/3 + 32 ≈ 162 ≤ 167（见 v3 布局测试实测）。
///
/// ⚠️ C65：标签是**文字**，平板会被放大 1.3× → 底栏必须同步长高，故此处不再用常量，
/// 一律走 [gardenPotFooterHeightOf]（三类格子 + 养护动效同源；手机返回 32 = 零回归）。

/// 三类格子统一的横向内边距：让「空盆 / 有植物 / 加盆」可用宽一致 → 盆等大。
const double _horizontalPad = kGardenCellHorizontalPad;

/// 三类格子统一的纵向内边距（仅上下各 4，用于和相邻行留白）。
const double _verticalPad = kGardenCellVerticalPad;

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
  /// 每格内容高 = 图高 + 底部标签区 [gardenPotFooterHeightOf]，再叠加上下内边距 8：
  ///   = (格宽-4) × [_artWidthRatio] × [_artAspectRatio] + 底栏高 + 8
  ///   = 1.3889 × (格宽-4) + 40（2026-10-11 画布 1440×2000 + 宽比 1.0）。
  /// 取 **0.55**（2026-10-11 随画布 1720→1440 收窄由 0.62 重算）：图片框变高
  /// （aspect 1.1628→1.3889），行高相应加高。最紧的 320 屏（测试宿主格宽 ≈ 96）
  /// 内容高 ≈ 167.8，格高 96/0.55 ≈ 174.5，余量 ≈ 6.8px，不溢出。
  static const double cellAspectRatio = 0.55;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: columns,
        // C48：行间距 6 → 4（玄参反馈两排间隔偏大，配合行高收紧）。
        mainAxisSpacing: 4,
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

  /// 点击杂草浮标 → 拔草（口径 C26）。
  ///
  /// ⚠️ 该回调必须**自带手势消费**（[_PestChip] 用 `GestureDetector.behavior:
  /// opaque`）：否则同一次点击会穿透到外层整格 [onTap]，出现「除完草又弹养护卡」。
  final VoidCallback onClearWeed;

  /// 点击害虫浮标 → 除虫（口径 C26）。约束同 [onClearWeed]。
  final VoidCallback onClearPest;

  /// 杂草浮标是否正在「渐变消失」（2026-10-03 玄参口径：播完除草动画后先淡出
  /// 浮标、再刷新草地）。true 时浮标透明度动画到 0，数据刷新后整支被移除。
  final bool weedFading;

  /// 害虫浮标是否正在渐变消失（同 [weedFading]）。
  final bool pestFading;

  /// C77 · 当前称号专属属性（缺省 [PlantPerk.none] → 奖励文案基础值 = 旧口径，零回归）。
  final PlantPerk perk;

  const GardenPot({
    super.key,
    required this.plant,
    required this.species,
    required this.onTap,
    required this.onClearWeed,
    required this.onClearPest,
    this.weedFading = false,
    this.pestFading = false,
    this.perk = PlantPerk.none,
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
    final AppLocalizations l10n = l10nOf(context);
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
                    // ⚠️ 用 Stack 而非 Row/Column：浮标是**叠加**在植物图上的，
                    // 不占布局高度 —— 草地网格高度由矮屏测试钉死，不能因加图标而变高。
                    // StackFit.loose：浮标走 Positioned（脱离流），植物图自己定尺寸。
                    child: Stack(
                      fit: StackFit.loose,
                      children: <Widget>[
                        // ⚠️ 植物图必须 Positioned.fill 钉满紧约束框（artW×artH）：
                        // 若让它走 loose 约束自定尺寸，占位/加载分支会按自身逻辑尺寸
                        // 布局，「空盆与有植物盆图片框等大」契约被破坏（测试实证）。
                        Positioned.fill(
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
                        // 花园干扰物（杂草 / 害虫，口径 C26；2026-10-11 随画布 1720 重标定）：
                        //  · 尺寸与横向锚点一律**相对盆身**表达（常量在 prd_params.dart
                        //    「花园格几何」段）——修「盆缩小后杂草跑到盆外、比盆还大」；
                        //  · 杂草：左缘贴盆左缘、长在盆口内略偏左，宽 = 盆宽 × 0.83；
                        //  · 害虫：右缘越出盆右缘 0.205 盆宽、趴在盆沿上，宽 = 盆宽 × 0.72；
                        //  · 纵向锚点（0.47 / 0.53）沿用 2026-10-03 定稿——两代画布都是
                        //    2000 高、盆口比例不变（0.659），纵向关系天然成立；
                        //  · 均**裸图直贴**（素材透明背景，无白圆底衬）。点一下即清除 + 奖励阳光。
                        if (plant.hasWeed)
                          Positioned(
                            left: artW * kWeedLeftFraction,
                            top: artH * 0.47,
                            // 「播放完杂草渐变消失」（2026-10-03 玄参口径）：
                            // 动画播完先透明度淡出，数据刷新后整支移除。
                            child: AnimatedOpacity(
                              opacity: weedFading ? 0.0 : 1.0,
                              duration: const Duration(
                                milliseconds: kPestFadeOutMs,
                              ),
                              child: _PestChip(
                                assetPath: kGardenWeedAsset,
                                emoji: kGardenWeedEmoji,
                                glyphWidth:
                                    artW * kPlantPotWidthFraction * kWeedSizeToPotRatio,
                                glyphHeight:
                                    artW * kPlantPotWidthFraction * kWeedSizeToPotRatio,
                                tooltip:
                                    l10n.pot_tooltip_weed(weedRewardOf(perk).toInt()),
                                onTap: onClearWeed,
                              ),
                            ),
                          ),
                        if (plant.hasPest)
                          Positioned(
                            right: artW * kPestRightFraction,
                            top: artH * 0.53,
                            child: AnimatedOpacity(
                              opacity: pestFading ? 0.0 : 1.0,
                              duration: const Duration(
                                milliseconds: kPestFadeOutMs,
                              ),
                              // 蝗虫**待机微动**（玄参 2026-10-19：「你说的给蝗虫做一个
                              // 动画，你做一下，我看看效果」）：只加在害虫上，杂草保持静止
                              // —— 草丛本来就该是不动的，动了反而像 bug。
                              child: _PestIdleWobble(
                                // 浮动行程按浮标**外接高**（= max(命中区 48, 视觉图高)）算，
                                // 与 `_PestChip.build` 的 `SizedBox` 高同源。
                                span: math.max(
                                  _PestChip.hitSize,
                                  artW *
                                      kPlantPotWidthFraction *
                                      kPestSizeToPotRatio *
                                      (30 / 52),
                                ),
                                child: _PestChip(
                                  assetPath: kGardenPestAsset,
                                  emoji: kGardenPestEmoji,
                                  glyphWidth: artW *
                                      kPlantPotWidthFraction *
                                      kPestSizeToPotRatio,
                                  glyphHeight: artW *
                                      kPlantPotWidthFraction *
                                      kPestSizeToPotRatio *
                                      (30 / 52),
                                  tooltip:
                                      l10n.pot_tooltip_pest(pestRewardOf(perk).toInt()),
                                  onTap: onClearPest,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // 固定高度的底部区（进度条 + 标签）：供空盆 / 加盆格留等高空位对齐。
                // MainAxisAlignment.end：让胶囊贴底 → 三类格子的文案底边严格齐平。
                SizedBox(
                  height: gardenPotFooterHeightOf(context),
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
                      // 标签：胶囊底 + 加深字色（压在草地上也看得清）。
                      // C63（2026-10-13 玄参）：精英植物做档位区分。
                      // C64 修订（同日 iPad 实测）：「只增加紫色描边就行了，底还用半透明白底
                      // 就行」—— 淡紫底在满屏绿色草地上反而显脏，描边已足够区分档位；
                      // 故**两档共用半透明白底 [_labelPillColor]**，仅精英多一圈紫描边。
                      // 描边色与属性卡 / 选种卡同源（`kRarity*`，「防孪生」）。
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
                            border: species.isPremium
                                ? Border.all(
                                    color:
                                        kRarityEliteAccent.withValues(alpha: 0.55),
                                  )
                                : null,
                          ),
                          // F164：花盆标签是「植物名 + 状态」（英文
                          // `Coral Orchid · save me` 比中文「珊瑚岭兰 · 救救我」长近
                          // 一倍），原本 `maxLines:1 + ellipsis` 在手机格宽
                          // （96~118pt）必然截断 —— 被吃掉的是**状态词**。
                          // 改「单行 + 等比缩小」：放不下就整词缩，不折行不省略；
                          // 中文文案短，缩放比 = 1.0，视觉零回归。
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _label(l10n),
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _labelColor,
                              ),
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
  ///
  /// i18n B3（T04）：物种名经 `speciesNameOr` 取当前语言；未知 id 回退
  /// `species.name`（其 name 已被 `_unknownSpecies` 兜成 `garden_unknown_plant`）。
  String _label(AppLocalizations l10n) {
    final String name = speciesNameOr(species.id, species.name, l10n);
    switch (plant.status) {
      case PlantStatus.bloomed:
        return l10n.pot_label_bloomed(name);
      case PlantStatus.wilting:
        return l10n.pot_label_wilting(name);
      case PlantStatus.dead:
        return l10n.pot_label_dead(name);
      case PlantStatus.growing:
        return name;
    }
  }
}

/// 害虫待机动画根 [Transform] 的 Key（供测试直接取 `Transform.transform` 矩阵）。
///
/// 用 Key 而不是 `find.byType(Transform)`：花盆树里 `PlantArtwork` 等组件也可能
/// 内含 `Transform`（膨胀/缩放），按类型找会拿到不相关的那个。
const Key kPestIdleAnimKey = Key('garden_pest_idle_anim');

/// 花园干扰物浮标「杂草 / 害虫」（口径 C26；2026-10-03 图片化 + 去白圆底）。
///
/// **直接显示美术图**（[assetPath]，`assets/garden/weed.png` / `pest.png`）——
/// 素材自带透明背景，**裸图贴合花盆**（玄参 2026-10-03：白色圆底「太丑了，去掉」，
/// 杂草直接长在盆里、蝗虫直接趴在盆上）；加载失败（资源缺失 / 测试环境）回退
/// [emoji]，两条路径的点击行为与命中区完全一致。
///
/// ⚠️ 两处刻意为之：
///  · **命中区 [hitSize] 保留 48×48**（视觉图可以比命中区大/小）：儿童可点尺寸下限，
///    视觉再花哨也不能把可点面积做小（点不中比点错更挫败）；
///  · 图片用 `BoxFit.contain`（蝗虫图是 1518×853 横构图趴姿，contain 不裁剪；
///    显式宽高避免 loose 约束布局异常）。
class _PestChip extends StatelessWidget {
  final String? assetPath;
  final String emoji;
  final String tooltip;
  final VoidCallback onTap;

  /// 视觉图尺寸（透明底 PNG 裸贴）；杂草方形、蝗虫横构图按素材比例给。
  final double glyphWidth;
  final double glyphHeight;

  const _PestChip({
    required this.assetPath,
    required this.emoji,
    required this.tooltip,
    required this.onTap,
    required this.glyphWidth,
    required this.glyphHeight,
  });

  /// 命中区边长（视觉图外接方，≥48 满足儿童触控目标下限）。
  static const double hitSize = 48;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        // ⚠️ 必须 opaque：让本浮标**吃掉**这次点击，不穿透到外层整格 onTap
        // （否则会出现「点杂草 → 草除掉了、养护卡也弹出来」双反馈）。
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          // 命中区 = max(视觉图, 48 下限)：视觉图放大（如杂草 60）时命中区跟着扩，
          // 视觉图小于 48（如蝗虫 52×30 高）时仍保住儿童触控目标下限。
          width: hitSize > glyphWidth ? hitSize : glyphWidth,
          height: hitSize > glyphHeight ? hitSize : glyphHeight,
          child: Center(child: _glyph()),
        ),
      ),
    );
  }

  /// 图标本体：有美术图用 `Image.asset`（**显式宽高** + contain 裸贴），失败回退 emoji。
  Widget _glyph() {
    final String? path = assetPath;
    if (path != null) {
      return Image.asset(
        path,
        width: glyphWidth,
        height: glyphHeight,
        fit: BoxFit.contain,
        errorBuilder: (BuildContext _, Object __, StackTrace? ___) => Text(
          emoji,
          style: const TextStyle(fontSize: 26),
        ),
      );
    }
    return Text(emoji, style: const TextStyle(fontSize: 26));
  }
}

/// 害虫「待机微动」（玄参 2026-10-19：「你说的给蝗虫做一个动画，你做一下，我看看效果」）。
///
/// ## 效果口径
/// 蝗虫是**趴在盆沿上**的活物，完全静止看起来像贴纸。故给一条**若隐若现**的待机动作：
///  · 上下浮动：总行程 = 浮标外接高的 **5%**（±2.5%），慢到像呼吸，不像弹跳；
///  · 左右微摆：**±4°**，与浮动同一个 1400ms 周期、同一条 [Curves.easeInOut]；
///  · 两者叠加（[Transform.translate] 外套 [Transform.rotate]），一次往返 2.8s。
///
/// ## 为什么只有害虫有、杂草没有
/// 杂草是「植物的一部分」，动起来像渲染抖动；害虫是独立活物，「动 = 还活着、还能点掉」
/// 是可读的正向信号。故 [GardenPot] 只在 `plant.hasPest` 分支包本组件。
///
/// ## 三条硬约束
///  1. **必须 dispose**（无限 `repeat` 的 controller 不 dispose 会漏 ticker，测试
///     结束时 `flutter_test` 会直接报 "A Ticker was active when its widget was disposed"）；
///  2. **必须尊重 `TickerMode`**：外壳用 `IndexedStack` 保活 tab，隐藏 tab 被
///     `TickerMode(enabled: false)` 包住 —— `SingleTickerProviderStateMixin` 创建的
///     Ticker 会自动 mute，隐藏页因此**零帧回调、不耗电**（本类无需手写判断）。
///  3. **不能改变布局**：[Transform] 只作用于绘制与命中变换，`Positioned` 的
///     right/top 与 `_PestChip` 的命中区尺寸**逐像素不变**，故
///     `garden_interference_anchor_test` 的锚点断言不受影响。
class _PestIdleWobble extends StatefulWidget {
  /// 被包裹的浮标（`_PestChip`）。
  final Widget child;

  /// 幅度基准 = 浮标外接高（浮动行程 = 本值 × [floatRatio]）。
  final double span;

  /// 单程时长（`repeat(reverse: true)` → 一次完整往返 = 2 个周期）。
  static const Duration period = Duration(milliseconds: 1400);

  /// 上下浮动的**总行程**占比（5%：再大就像「跳」，玄参口径要「若隐若现」）。
  static const double floatRatio = 0.05;

  /// 左右摆动的**峰值角度**（±4°，弧度）。
  static const double tiltRadians = 4 * math.pi / 180;

  const _PestIdleWobble({required this.child, required this.span});

  @override
  State<_PestIdleWobble> createState() => _PestIdleWobbleState();
}

class _PestIdleWobbleState extends State<_PestIdleWobble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _PestIdleWobble.period,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        // t 在 0..1 之间往复（repeat reverse），easeInOut 让两端「停一下」更自然。
        final double t = Curves.easeInOut.transform(_controller.value);
        final double dy =
            -(t - 0.5) * widget.span * _PestIdleWobble.floatRatio;
        final double angle = (t - 0.5) * 2 * _PestIdleWobble.tiltRadians;
        return Transform.translate(
          key: kPestIdleAnimKey,
          offset: Offset(0, dy),
          child: Transform.rotate(angle: angle, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// 空花盆 —— 点击进入种植选择。
///
/// 玄参大人要求：空格只显示陶盆（去掉「+」圆圈与「点击种植」标签），并放大显示
/// 比例，让空盆在草地上更醒目、更易点。点击行为不变（[onTap] 透传给页面弹种植选择）。
///
/// 与 [GardenPot] 共用 [_artWidthRatio] / [_artAspectRatio] / [gardenPotFooterHeightOf]：
/// 空盆与有植物盆**等大、同底**（否则空盆会比邻居低，看起来「没对齐」）。
///
/// ## F155-B（玄参 2026-10-27 拍板）：空花盆也会长杂草 / 害虫
///  · 浮标**复用** [GardenPot] 那支 [_PestChip]（同一份样式、同一套尺寸公式与锚点，
///    见 `prd_params.dart`「花园格几何」段）—— 不复制第二份样式；
///  · **不阻挡种植**：浮标只是叠在盆上的一个 48×48 热区，其余区域照常走 [onTap]
///    弹种植选择；点浮标则清除（与有植物盆的交互一致）；
///  · 浮标叠在图片框的 [Stack] 里（`Positioned`，**不占布局高度**）→ 空盆与有植物盆
///    「等大、同底」的既有布局契约逐像素不变（有守卫测试钉死）。
///  · 害虫浮标**不加** [GardenPot] 那支 `_PestIdleWobble` 待机微动：空盆没有植物美术
///    作参照，静止浮标已足够可读；同时避免把「永不 settle 的无限动画」引入空盆子树
///    （测试禁令范围最小化，见本文件头）。
class EmptyPot extends StatelessWidget {
  final int potIndex;
  final VoidCallback onTap;

  /// 该空盆当日的杂草状态（F155-B；由 [EmptyPotService] 的每日 roll 给出）。
  final bool hasWeed;

  /// 该空盆当日的害虫状态（同 [hasWeed]）。
  final bool hasPest;

  /// 点浮标 → 拔草（null = 不可清除，浮标照常展示；页面正常传回调）。
  final VoidCallback? onClearWeed;

  /// 点浮标 → 除虫（约束同 [onClearWeed]）。
  final VoidCallback? onClearPest;

  /// 杂草浮标是否正在「渐变消失」（与 [GardenPot.weedFading] 同口径同动画）。
  final bool weedFading;

  /// 害虫浮标是否正在渐变消失（同 [weedFading]）。
  final bool pestFading;

  /// 当前称号属性 —— 只用于浮标 tooltip 的奖励数字（`weedRewardOf` / `pestRewardOf`），
  /// 与有植物盆、与域层入账**同源**，不在 UI 侧另算。
  final PlantPerk perk;

  const EmptyPot({
    super.key,
    required this.potIndex,
    required this.onTap,
    this.hasWeed = false,
    this.hasPest = false,
    this.onClearWeed,
    this.onClearPest,
    this.weedFading = false,
    this.pestFading = false,
    this.perk = PlantPerk.none,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = l10nOf(context);
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
                // pot.png（1200×2000）在本框内按高度绑定 contain 缩放（系数 =
                // artW/1440），盆身显示宽与植物图盆 800px 等大（差 0.1%）。
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: artW,
                    height: artH,
                    // ⚠️ 用 Stack 叠加浮标（`Positioned`，脱离流）→ 不占布局高度，
                    // 空盆图片框尺寸与高度契约逐像素不变。
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _PotImage(
                          width: artW,
                          height: artH,
                          dead: false,
                          highlighted: false,
                        ),
                        // 杂草 / 害虫浮标：尺寸、锚点、命中区与有植物盆**完全同源**
                        // （常量在 prd_params.dart「花园格几何」段，改一处两处同时变）。
                        if (hasWeed)
                          Positioned(
                            left: artW * kWeedLeftFraction,
                            top: artH * 0.47,
                            child: AnimatedOpacity(
                              opacity: weedFading ? 0.0 : 1.0,
                              duration: const Duration(
                                milliseconds: kPestFadeOutMs,
                              ),
                              child: _PestChip(
                                assetPath: kGardenWeedAsset,
                                emoji: kGardenWeedEmoji,
                                glyphWidth: artW *
                                    kPlantPotWidthFraction *
                                    kWeedSizeToPotRatio,
                                glyphHeight: artW *
                                    kPlantPotWidthFraction *
                                    kWeedSizeToPotRatio,
                                tooltip: l10n.pot_tooltip_weed(
                                    weedRewardOf(perk).toInt()),
                                onTap: onClearWeed ?? () {},
                              ),
                            ),
                          ),
                        if (hasPest)
                          Positioned(
                            right: artW * kPestRightFraction,
                            top: artH * 0.53,
                            child: AnimatedOpacity(
                              opacity: pestFading ? 0.0 : 1.0,
                              duration: const Duration(
                                milliseconds: kPestFadeOutMs,
                              ),
                              child: _PestChip(
                                assetPath: kGardenPestAsset,
                                emoji: kGardenPestEmoji,
                                glyphWidth: artW *
                                    kPlantPotWidthFraction *
                                    kPestSizeToPotRatio,
                                glyphHeight: artW *
                                    kPlantPotWidthFraction *
                                    kPestSizeToPotRatio *
                                    (30 / 52),
                                tooltip: l10n.pot_tooltip_pest(
                                    pestRewardOf(perk).toInt()),
                                onTap: onClearPest ?? () {},
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // 等高空位（空盆无进度条 / 标签）：保证空盆底边与有植物盆底边齐平。
                // 带 Key：供 v3 布局测试度量「底部区底边」是否与两类文字胶囊齐平。
                SizedBox(
                  key: const Key('empty_pot_footer'),
                  height: gardenPotFooterHeightOf(context),
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
/// 可点性口径（**2026-09-24 修订**，玄参真机反馈「点了没反应」）：
///  · [busy] = true → 不可点（防连点绕过扣费，保持拦截）；
///  · **阳光不足 → 仍可点**：由页面层兜底弹分因提示（「阳光不足，还差 N ☀」）。
///    旧口径「阳光不足 → `onTap: null`」被玄参判定为缺陷 —— 格子虽写了「还差 N☀」，
///    但孩子点下去毫无反馈，等于静默失败（UX 纪律：不可点状态必须分因提示）；
///  · 否则 → 可点，点击先弹确认卡。
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

  /// 是否可扩容（阶段 4）。
  ///
  /// - `true`（默认）：常规可点加号格，**旧行为逐像素不变**；
  /// - `false`：**锁定态**——渲染中性灰「需解锁」样式 + 锁图标，点击仍走 [onTap]
  ///   给分因提示（对齐 C62：不可点 ≠ `onTap:null`）。
  ///
  /// 用途（F166，玄参 2026-10-29 改判 D4）：孩子端 free 档**满 4 盆后仍然渲染**
  /// 一格锁定态，作为「花园还能再大」的视觉提示（孩子据此去找父母扩容）；
  /// 买断档满 12 真到顶则**不渲染**。故本参数从「留给未来」变成真在用。
  final bool unlockable;

  const ExpandPotSlot({
    super.key,
    required this.cost,
    required this.shortfall,
    required this.busy,
    required this.onTap,
    this.unlockable = true,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = l10nOf(context);
    final bool affordable = shortfall <= 0;
    final bool active = affordable && unlockable;
    return InkWell(
      // ⚠️ 只有 busy 拦点击；阳光不足 / 锁定态**不再拦**（分因提示由页面层兜底给）。
      onTap: busy ? null : onTap,
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
            final Color ring = active ? Colors.green.shade700 : Colors.grey;
            final Color label =
                active ? Colors.green.shade800 : Colors.grey.shade700;

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
                            // F166：锁定态用**锁**而不是加号 —— 加号会让孩子以为
                            // 「点了就能加」，锁一眼说明「要大人帮忙」，减少无谓点击。
                            unlockable
                                ? Icons.add_circle_outline
                                : Icons.lock_outline,
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
                  height: gardenPotFooterHeightOf(context),
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
                          // F164：这三条文案都**带数字/价格**（`Add pot · 300☀`
                          // `Need 120☀ more`），原本 `maxLines:1 + ellipsis` 在手机
                          // 格宽下被省略号吃掉的是价格本身（实测格宽 96 与 118 均
                          // `didExceedMaxLines = true`）。
                          // 改「单行 + 等比缩小」：宁可整词缩小，绝不吃掉金额。
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              !unlockable
                                  ? l10n.pot_label_locked
                                  : affordable
                                      ? l10n.pot_label_expand(cost)
                                      : l10n.pot_label_shortfall(shortfall),
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: label,
                              ),
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
/// 美术画布比例（1440×2000）—— pot.png（1200×2000）在框内按高度绑定 contain 缩放，
/// 否则盆会被画小，空盆又变小。
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
