/// 守卫战 v2 · **场景卡布局几何**（B8 裁定 v4，玄参 2026-11-10 第三轮真机复验）。
///
/// ## 为什么单独一个文件
/// 卡（`guard_scene_card.dart`）与战斗层（`guard_battle_field.dart`）必须用
/// **同一套**矩形：卡的「战士位 / 通道」与战斗层的「怪/子弹落点」一旦各自算，
/// 就会出现「怪走到房子上」「子弹从按钮里飞出来」这类错位，而且改一处忘另一处。
/// 把几何抽成纯值类（零 BuildContext、零 widget）后，两边都只读它，且**可单测**。
///
/// ## v3 → v4 改了什么（玄参原话）
/// * **卡高降到房顶高度**：160 → **108**（房源 88 + 底衬 10 + 能量点顶衬 10），
///   把 v3 那半张卡的空白砍掉（§6.3 布局 v4）；
/// * **战士挪到栅栏外**：`soldierRect.left = houseRect.right + 6`（v3 是右缘压进
///   房子 6pt，看起来站在花园里）—— 脚底仍踩同一条基线，视觉上「栅栏外站岗」；
/// * **能量点回归**：两个 18pt 小圆点放回卡内，位置在**房子右侧、栅栏上方**
///   （`energyDotRect`），垂直不越出房顶一个直径；
/// * **去掉外框**：卡根不再有描边 / 圆角 / ClipRRect，草地板自己铺满整张卡
///   （今日页把卡做成**满宽贴边**，横向白赚 32pt 通道）。
///
/// ## 坐标口径
/// 全部是**卡内坐标**（相对卡片左上角，单位 pt，`+x` 向右、`+y` 向下）：
/// ```text
/// ┌──────────────────────────────────────────────────────────────┐ y=0
/// │  ○ ○  ← 能量点（花园中轴上方，14pt，锚 = house.center + AnchorDx）│
/// │  🏠 房子（contain 完整可见）  🧑‍🚀 战士（栅栏外）  ←←← 怪   (▶)  │
/// │ ▬▬▬▬▬▬▬▬▬▬▬▬ 倒计时细线（战斗态，4pt）▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬ ▬ │ y=112
/// └──────────────────────────────────────────────────────────────┘
/// ```
/// 左侧「房子 + 栅栏间隙 + 战士」与右侧「开始钮槽位」固定尺寸，中间通道宽度 =
/// `卡宽 − 两者`，是**唯一**随屏宽变化的量。
///
/// ## B10（玄参第五轮）在本文件落的几何
/// * **C1** 战士 78 → **68**（绘制框 130 → 113.33 派生，跑道 390 屏 99.83 →
///   **109.83**）；
/// * **C2** 能量点 18 → **14**、间隙 8 → **6**，锚点加横向微调旋钮
///   [kGuardEnergyDotAnchorDx]（默认 0 = 花园几何中轴）；
/// * **C3** 三怪改**等面积** 1936pt²（h = √(1936/r)，39.19 / 44.00 / 31.77）。
///
/// ## B11（玄参第六轮）在本文件落的几何
/// * **C1** 战士尺寸不动（**68 锁定**，玄参「67~68 刚好」）；
/// * **C2** 能量点锚点 `kGuardEnergyDotAnchorDx` 0 → **20**（美学位移，
///   两点圆心中点 = `houseRect.center.dx + 20` = **98.08**）；直径/间距/顶边不动；
/// * **C4** 战士三态按**身体质心**对齐（新增
///   [GuardCardLayout.soldierStateAlignShiftX]）—— 攻击帧身体不再左移 9.69pt；
/// * **C5** 小怪加**每档面积系数** [kGuardMonsterAreaFactorByKind]（m1 0.80
///   ⇒ 44.19×35.04；m2/m3 系数 1.0，与 B10 逐位相同）。
library guard_card_layout;

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:sunflower_time/core/constants/prd_params.dart'
    show
        kGuardCardHouseHeight,
        kGuardCardPadBottom,
        kGuardCardPadTop,
        kGuardEnergyDotAnchorDx,
        kGuardMonsterAreaFactorByKind,
        kGuardSceneCardHeight,
        kGuardSceneEnergyDotTop,
        kGuardSceneFireButtonSize,
        kGuardSoldierStateAspectRatios,
        kGuardSoldierStateCentroidX;
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show
        kGuardBattleFieldTravelPt,
        kGuardBattleLaneBottomPt,
        kGuardBattleLaneTopPt;

/// 房子素材宽高比（`assets/guard/house.webp` = 1984×1118）。
///
/// 🔴 与素材绑定：换图必须同步改这里（布局测试断言渲染宽高比 ≈ 本值 ±2%）。
const double kGuardHouseAspectRatio = 1984 / 1118;

/// 进入「窄卡等比缩」的卡宽阈值。单位：pt。
///
/// ## 🔴 B8.1：340 → **380**（修「逻辑倒挂」）
/// 旧阈值 340 会让 **360 屏不缩元素**（360 > 340）⇒ 通道只剩 49.84pt，
/// 而 320 屏因为缩了反而有 56.36pt —— **屏越大通道越窄**，没有任何设计理由。
/// 改成 380 后：360 ⇒ **96.36**、375 ⇒ **111.36**、390 不变 **79.83**、
/// 320 不变 **56.36**（390 > 380 仍走全尺寸，玄参要的 88/72 大图不受影响）。
const double kGuardNarrowCardWidth = 380;

/// 窄卡等比缩比例（玄参给定 0.85）。
///
/// 🔴 只缩**卡内元素**，不缩卡高：卡高跨屏宽恒定 ⇒ 今日页 ListView 的滚动
/// 预算稳定；320 屏（卡宽 320）可用通道实测 **56.4pt**（验收线 55pt）。
const double kGuardNarrowCardScale = 0.85;

/// 卡片布局几何（由**卡宽**派生；其余全部是常量 × [scale]）。
class GuardCardLayout {
  const GuardCardLayout(this.cardWidth, [this.uiScale = 1.0]);

  /// 卡宽。单位：pt。
  ///
  /// A4 之后卡是**满宽贴边**（今日页用 `OverflowBox` 撑到屏宽）：390 屏 = 390、
  /// 320 屏 = 320、iPad = 1024。卡根已无描边 ⇒ 卡内 `LayoutBuilder` 拿到的
  /// 就是本值（v3 时代要减 2pt 描边，现已不需要）。
  final double cardWidth;

  // ── 内边距 ────────────────────────────────────────────────────────────
  /// 左内边距。单位：pt（v4 = **0**：房子贴草坪左缘，横向一点都不浪费）。
  static const double padLeft = 0;

  /// 右内边距（开始钮贴右缘）。单位：pt。
  static const double padRight = 8;

  /// 卡顶留白（卡顶 → 房子屋顶）。单位：pt。
  ///
  /// 🔴 **卡高的三个来源常量之一**：`卡高 = padTop + houseHeight + padBottom`
  /// （见 [kGuardSceneCardHeight] 的派生注释）。
  /// 🔴 B8.1：本值同时是**能量点的顶边线**（`energyDotTop = padTop`）——
  /// 圆点顶边与房顶线逐位齐平，零像素飘到房子图上方；这条 10pt 空带从此只是
  /// 归一化呼吸位，不再塞任何东西。
  static const double padTop = kGuardCardPadTop;

  /// 底部内边距（房子 / 战士 / 按钮的共同基线）。单位：pt。
  static const double padBottom = kGuardCardPadBottom;

  // ── 左侧簇（固定尺寸，B7 放大后不变）──────────────────────────────────
  /// 房子渲染高度。单位：pt（B6 64 → B7 **88**，v4 不动）。
  ///
  /// 🔴 直接引用 [kGuardCardHouseHeight]：卡高由它派生，两处不许各写一个数。
  static const double houseHeight = kGuardCardHouseHeight;

  /// 房子渲染宽度（按 [kGuardHouseAspectRatio] 推导，**contain 不裁切**）。
  ///
  /// 88 × 1.7746 ≈ **156.17pt**（玄参给的「宽≈156」）。
  static const double houseWidth = houseHeight * kGuardHouseAspectRatio;

  /// 战士渲染高度（= 正方形棋子的边长）。单位：pt。
  ///
  /// ## 计数器：72（B7/B8）→ 78（B9）→ 68（B10）→ 64（B13 试值）→ 60（B13.2 试值）→ **60 定稿**（B13.3）
  /// 老数字 72 是画在 512×512 画布上的，而素材实体只占中间 26% 面积
  /// （左右各 ~24% 透明边）⇒ **肉眼只有 72 × 0.5 ≈ 36pt**（玄参「战士太小」的
  /// 全部原因，不是常量小）。B9 把素材按实体并集 bbox 裁掉透明边之后，
  /// 标称尺寸 = 视觉尺寸，78 就是肉眼 78pt。
  ///
  /// 🔴 **60 = 定稿尺寸**（玄参真机复验，B13.3 拍板「就做这么大吧」，后续不许再动）。
  /// 派生绘制框 = 60 × 5/3 = **100**，仍大于攻击帧按 60 高的 88.0 宽 ⇒ 长兵器不裁。
  ///
  /// 🔴 连带（B13.2 渲染安全钳，随 60 定稿一并保留）：60 高下「怪带最低点 + 半个怪」在宽卡恰好
  /// 压上卡底倒计时细线 ⇒ [mapMonsterY] 加了**渲染层钳制**（只钳渲染落点、
  /// sim 零改动；带顶部不动，「同一水平带」语义不变）。
  ///
  /// 🔴 布局仍按**正方形** 60×60 算跑道（不让攻击帧的长兵器拖累通道）；
  /// 绘制用 `BoxFit.fitHeight` + 允许横向溢出（见 `GuardArt.soldier`）：
  /// 待机 362×372 ⇒ 宽 58.4（落在框内）；攻击 512×349 ⇒ 宽 88.0，
  /// 左右各溢出 ~6pt，只闪 300ms，压到房子 / 跑道上是自然的重叠。
  static const double soldierHeight = 60;

  /// 战士渲染边长（**保持正方形**，= [soldierHeight]；旧名 `soldierSize` 已合并）。
  static const double soldierSize = soldierHeight;

  /// 战士**绘制**可用宽度（允许横向溢出、**不裁**）。单位：pt。
  ///
  /// ## 🔴 B9/C2：绘制框必须比布局框宽
  /// 布局按正方形 [soldierSize] 算跑道 —— 攻击帧的长兵器不许拖累通道。
  /// 但绘制用 `BoxFit.fitHeight`（三态都同高，**禁止 contain**）：
  /// * 待机帧 362×372 ⇒ 宽 `h × 0.973`（落在方框内）；
  /// * 攻击帧 512×349 ⇒ 宽 `h × 1.467`（B10 的 68 高时 = **99.76**）——
  ///   若绘制框仍只有 68 宽，左右各 15.8pt 会被裁掉（长兵器被切头）。
  ///
  /// 故绘制框给 `h × 5/3`（B10：**113.33** > 99.76，留 13.6pt 余量），由卡内的
  /// `OverflowBox`（`alignment: center`）以战士矩形中心**居中溢出**：
  /// 三态都同高、谁也不缩，攻击帧压到房子 / 跑道上正是玄参要的重叠。
  /// 🔴 比例式（不是写死的宽）：`soldierHeight` 再改，绘制框自动跟着走。
  static const double soldierOverflowWidth = soldierHeight * 5 / 3;

  /// 战士与房子之间的**栅栏间隙**。单位：pt。
  ///
  /// 🔴 B9：6 → **2**。裁边前素材左边有 23.4% 的透明边（≈17pt），
  /// 标称 6pt 的间隙肉眼成了 23pt（玄参「离房子太远」）；裁边后 2 就是真的 2pt。
  static const double soldierHouseGap = 2;

  // ── 右侧簇（固定尺寸）────────────────────────────────────────────────
  /// 右簇槽位边长 =「开始守卫」图标钮直径。
  ///
  /// 🔴 **战斗中这一格留空**（卡内开火钮已删，开火由页面右上阳光胶囊触发），
  /// 但槽位本身**照旧占位** ⇒ 通道宽度不会因为「开始钮消失」而跳变
  /// （`channelRight` 由槽位算，不由「谁在树」算）。
  static const double rightClusterSize = kGuardSceneFireButtonSize;

  /// 通道右端与右簇之间的间隙。单位：pt。
  static const double channelGap = 4;

  // ── 战斗元素（B7 放大后不变）──────────────────────────────────────────
  /// 小怪**基准高度**（= 面积口径的边长基数）。单位：pt（B3 起 24 → B7 **44**）。
  ///
  /// 🔴 B10/C3：语义进一步收窄为「**面积基线上限**」—— 见 [monsterArea]。
  static const double monsterSize = 44;

  /// 三种怪统一的**视觉面积**（pt²）：`44 × 44 = 1936`。
  ///
  /// ## 🔴 B10/C3：玄参第五轮「三种怪视觉体量要对齐」
  /// B9.1 让三怪**高度**齐平（44），但宽度按各自比例拉开（55.5 / 44.0 / 84.4）
  /// ⇒ 体积差得更多（贪婪鼬看着像食叶虫的两倍大）。B10 改「**等面积**」：
  /// 保持各素材宽高比 `r = w / h` 不变，按 `w × h = monsterArea` 反解
  /// ⇒ `h = √(1936 / r)`、`w = r · h`：
  ///
  /// | 怪 | 素材比例 r | 反解 h | 反解 w | 面积 |
  /// |---|---|---|---|---|
  /// | m1 馋光鼠 | 512/406 = 1.261 | **39.19** | **49.42** | 1936 |
  /// | m2 食叶虫 | 512/512 = 1.000 | **44.00** | **44.00** | 1936 |
  /// | m3 贪婪鼬 | 512/267 = 1.918 | **31.77** | **60.93** | 1936 |
  ///
  /// 🔴 **不许分别写死三组宽高**：写死就退化成「改素材忘改常量」的两套账；
  /// 这里只有 [monsterArea] + 素材比例两个来源（见 [monsterHeightOf] /
  /// [monsterWidthOf]），换图只需改 [monsterAspectRatios]。
  /// 断言见 `guard_scene_card_layout_v5_test` ⑦（三者面积相等 ±1%、高度全 ≤ 44、
  /// 六个数字 ±0.6）。
  ///
  /// 🔴 **B11/C5**：上表是**基线**（系数 1.0）。玄参第六轮「馋光鼠还有点大」⇒
  /// 乘一个**每档面积系数** [kGuardMonsterAreaFactorByKind]（m1 = 0.80
  /// ⇒ 面积 1548.8 ⇒ **44.19 × 35.04**；m2/m3 系数 1.0 ⇒ 与上表逐位相同）。
  /// 系数表是**唯一旋钮**，公式本身不再接受任何特例分支。
  static const double monsterArea = monsterSize * monsterSize;

  /// 各怪素材的**宽高比**（`w / h`；与 `assets/guard/monster_mX` 的裁边后画布绑定）。
  ///
  /// ## 🔴 B9.1：怪的绘制口径从「44 方框 contain」改成「高度按比例」（fitHeight）
  /// 裁边后三种怪的画布比例差一倍，`contain` 按**宽**贴边 ⇒ 贪婪鼬只有食叶虫
  /// 一半高（玄参一眼就会说「小怪大小不一」）：
  ///
  /// | 怪 | 裁边后画布 | 比例 | contain 在 44 方框里的实际高度 |
  /// |---|---|---|---|
  /// | m1 馋光鼠 | 512×406 | 1.261 | 34.9 |
  /// | m2 食叶虫 | 512×512 | 1.000 | 44.0 |
  /// | m3 贪婪鼬 | 512×267 | **1.918** | **22.9** |
  ///
  /// 🔴 与素材绑定：换图必须同步改这里（`qa/guard_asset_solid_ratio_test` ⑤ 钉
  /// 三态宽高比；v6 ③ 钉等面积反解出来的六个宽高）。
  static const Map<String, double> monsterAspectRatios = <String, double>{
    'm1': 512 / 406,
    'm2': 1.0,
    'm3': 512 / 267,
  };

  /// 「未知种类」的兜底比例（占位色块是正方形；也是素材缺失时的形状）。
  static const double monsterFallbackAspectRatio = 1.0;

  /// 子弹渲染边长。单位：pt（B6 10 → B7 **12**）。
  static const double bulletSize = 12;

  /// 「同一水平带」的半高。单位：pt。
  ///
  /// 玄参：「车道与战士**同一水平带**（2D 同平面，不要上下错层）」。
  /// 故怪的纵向中心 = 战士中心 ± 8pt（sim 的 y 抖动被压到 ±8，只当作「走位」）。
  static const double monsterBandHalfHeight = 8;

  // ── 能量点（B8 回归：房子右侧、栅栏上方；B10 缩小并微调锚点）───────────
  /// 能量点直径。单位：pt（B8 的 18 → B10 **14**，玄参第五轮「点太占地方」）。
  static const double energyDotSize = 14;

  /// 两个能量点之间的间隙。单位：pt（B8 的 8 → B10 **6**）。
  static const double energyDotGap = 6;

  /// 能量点距卡顶（**宽卡口径**）。单位：pt（= [padTop]，与房顶线齐平）。
  ///
  /// 🔴 B8.1：旧值 4 让圆点飘在房子图**上方**（玄参要修的就是这个）。
  /// 现在 `dot.top ≥ houseRect.top`（真正的判据）：宽卡上逐位齐平，
  /// 窄卡上随房顶线下移（见 [energyDotTopY]）。
  static const double energyDotTop = kGuardSceneEnergyDotTop;

  // ── 底部倒计时细线 ────────────────────────────────────────────────────
  /// 倒计时细线高。单位：pt（玄参：「卡片底部一条 3~4pt 的细线」）。
  static const double countdownHeight = 4;

  /// 倒计时细线距卡底。单位：pt。
  static const double countdownBottomInset = 6;

  // ── 派生量 ────────────────────────────────────────────────────────────

  /// **平板 UI 放大倍率**（来自 `uiScaleOf`，手机 = 1.0）。
  ///
  /// 🔴 守卫卡此前未走平板适配（B 系列全程在手机上定稿），iPad 上被拉成一条
  /// 全宽窄带、房子/战士/按钮还是手机尺寸 ⇒ 又瘦又空、按钮/旗标又小又偏。
  /// 现把全部几何与卡高乘本倍率，使其与今日页其它元素（`uiScaleOf`）等比放大、
  /// 保持手机同款比例。默认 1.0 ⇒ 手机与既有测试逐位零回归。
  final double uiScale;

  /// 窄卡等比缩比例（1.0 或 [kGuardNarrowCardScale]）。
  double get scale =>
      cardWidth <= kGuardNarrowCardWidth ? kGuardNarrowCardScale : 1.0;

  /// 有效缩放 = 窄卡缩 × 平板放大。**所有几何与卡高都乘本值**（卡高本身不随
  /// 窄卡缩、只随平板放大，见 [cardHeight]）。
  double get e => scale * uiScale;

  /// 卡高。单位：pt（**不随窄卡缩放、但随平板 [uiScale] 放大**，跨屏宽恒定）。
  ///
  /// = `padTop + houseHeight + padBottom` = 14 + 88 + 10 = **112**，
  /// 平板下 × [uiScale]（iPad 11″ 1.3 → 145.6 / 13″ 1.6 → 179.2）。
  double get cardHeight => kGuardSceneCardHeight * uiScale;

  /// 舞台基线（房子 / 战士 / 开始钮的底边 y）。
  double get baselineY => kGuardSceneCardHeight * uiScale - padBottom * e;

  /// 房子屋顶 y（= 基线上移一个房子高度）。
  ///
  /// 🔴 与 [padTop] 的关系：卡宽 > 380（scale 1.0）时**逐位相等**（10）；
  /// 窄卡只缩元素不缩卡高，故屋顶会略低于 [padTop]（24.7），多出来的空白
  /// 留在卡顶 —— 这正是「窄卡不许改卡高」的代价，也是滚动预算稳定的原因。
  double get houseTopY => baselineY - houseHeight * e;

  /// 房子矩形（`contain` 完整可见，不被裁切）。
  Rect get houseRect {
    final double s = e;
    return Rect.fromLTWH(
      padLeft * s,
      houseTopY,
      houseWidth * s,
      houseHeight * s,
    );
  }

  /// 战士矩形（**栅栏外**：左缘 = 房子右缘 + [soldierHouseGap]，脚踩同一基线）。
  Rect get soldierRect {
    final double s = e;
    final double left = houseRect.right + soldierHouseGap * s;
    return Rect.fromLTWH(
      left,
      baselineY - soldierSize * s,
      soldierSize * s,
      soldierSize * s,
    );
  }

  /// 战士中心 y（小怪水平带的锚点）。
  double get soldierCenterY => soldierRect.center.dy;

  /// 战士**绘制**框宽度（卡内实际交给素材的约束宽）。单位：pt。
  ///
  /// = [soldierOverflowWidth] × [scale]（130 宽卡 / 110.5 窄卡），比
  /// [soldierRect] 宽 ⇒ 由 `OverflowBox` 居中溢出，攻击帧不被裁。
  double get soldierDrawWidth => soldierOverflowWidth * e;

  /// 第 [index] 个能量点的矩形（0 = 左、1 = 右）。
  ///
  /// 横向：**花园建筑的视觉中心**居中 —— 锚点 =
  /// `houseRect.center.dx + [kGuardEnergyDotAnchorDx] × scale`。
  /// （B9/C4 玄参：「应该在花园的上方显示，不是向日葵战士的头顶上」——
  ///  锚点从 `soldierRect.center.dx` 改为房子中轴；B10/C2 再加一个横向微调旋钮，
  ///  默认 0 = 与 B9 逐位一致。）🔴 `OverflowBox` 撑宽卡不影响本值：`cardWidth`
  ///  是卡的**真实**宽度（390 屏 = 390，`scale` = 1.0），见 v6 ①② 的六值 dump。
  /// 纵向：顶边 = **房顶线**（[energyDotTopY]）。
  Rect energyDotRect(int index) {
    final double s = e;
    final double gap = energyDotGap * s;
    final double dot = energyDotSize * s;
    final double total = dot * 2 + gap;
    final double anchor = houseRect.center.dx + kGuardEnergyDotAnchorDx * s;
    final double left = anchor - total / 2 + index * (dot + gap);
    return Rect.fromLTWH(left, energyDotTopY, dot, dot);
  }

  /// 能量点顶边 y：**对齐房顶线**，且不低于宽卡口径的 [energyDotTop]。
  ///
  /// 宽卡（s = 1.0）：`houseTopY == padTop == energyDotTop`（B10 起 14）⇒ 点占
  /// `y ∈ [14, 28]`，顶边与房顶线逐位齐平、零像素飘到房子图上方。
  /// 窄卡（s = 0.85）：`houseTopY` 更低，取它（不是 `energyDotTop × scale`）
  /// ⇒ 同样不出房顶。
  double get energyDotTopY => math.max(houseTopY, energyDotTop * e);

  /// 小怪**基准高度上限**（= [monsterSize] × [scale]，窄卡随之缩小）。单位：pt。
  ///
  /// ## 🔴 语义沿革（每轮都在收窄，别往回「优化」）
  /// * B9.1：从「方框边长」收窄为「**高度**」（三怪高度齐平 44）；
  /// * B10/C3：进一步变成「**面积基线的高度上限**」—— 实际每只怪的高度见
  ///   [monsterHeightOf]（39.19 / 44.00 / 31.77，按等面积反解，**全部 ≤ 本值**）。
  ///
  /// 仍有两个地方把它当「定尺」用，都是**刻意保留**的：
  /// * `channelLeft` 里的 `monsterExtent × 0.5`（C 方案：怪半个身子压住战士才停）——
  ///   按上限 44 算 = 22pt；各怪实际高度更小 ⇒ 压住的量比「刚好半个」略少，
  ///   方向安全（怪不会提前停在跑道中央）；
  /// * 怪 / MISS 的**纵向**占位（`mapMonsterY` 出来的中心 ± 本值/2，取上界居中
  ///   ⇒ 最矮的 m3 也稳稳落在同一条带上，不会上下跳）。
  double get monsterExtent => monsterSize * e;

  /// 第 [kindId] 种怪的**渲染高度**（等面积反解，恒 ≤ [monsterExtent]）。单位：pt。
  ///
  /// `h = √(monsterArea × 面积系数 / r) × scale`（`r` = 素材宽高比）。
  /// 宽卡实测：m1 **35.04**（B11 系数 0.80）/ m2 **44.00** / m3 **31.77**。
  /// 未知种类（占位兜底，r = 1）⇒ `√1936 = 44`。
  ///
  /// 🔴 公式自 B11 起多了一个**每档面积系数**（[kGuardMonsterAreaFactorByKind]，
  /// 玄参按单只怪微调的唯一旋钮），**结构不变**：仍然是「面积 + 比例反解」，
  /// 绝不退化成三组写死的宽高。
  double monsterHeightOf(String kindId) {
    final double ratio =
        monsterAspectRatios[kindId] ?? monsterFallbackAspectRatio;
    final double factor = kGuardMonsterAreaFactorByKind[kindId] ?? 1.0;
    return math.sqrt(monsterArea * factor / ratio) * e;
  }

  /// 第 [kindId] 种怪**渲染宽度**（= 高度 × 素材宽高比，允许超出方框）。单位：pt。
  ///
  /// 宽卡实测：m1 **44.19**（B11）/ m2 **44.00** / m3 **60.93**。
  /// 🔴 只有 [monsterAspectRatios] 一个比例来源，没有第二处写死的宽高。
  double monsterWidthOf(String kindId) {
    final double ratio =
        monsterAspectRatios[kindId] ?? monsterFallbackAspectRatio;
    return monsterHeightOf(kindId) * ratio;
  }

  // ── 战士三态**质心配准**（B11/C4：玄参「攻击时人往左挪了」）─────────────

  /// 某状态素材在给定**绘制高度**下的绘制宽度。单位：pt。
  ///
  /// `= 绘制高 × 素材宽高比`（`BoxFit.fitHeight` 的结果，见
  /// [kGuardSoldierStateAspectRatios]）。
  static double soldierStatePaintWidth(String state, double paintHeight) {
    final double ratio = kGuardSoldierStateAspectRatios[state] ?? 1.0;
    return paintHeight * ratio;
  }

  /// 某状态为了**身体质心对齐绘制框中轴**所需的横向位移。单位：pt（负 = 左）。
  ///
  /// ## 为什么是「质心对齐」而不是「实体框居中」
  /// 三态各自裁到自己的实体框：攻击帧的框里多了挥出去的兵器（512 宽 vs 待机
  /// 362），`fitHeight` 再**居中**放进来，身体就被推离中轴 ——
  /// 实体框居中时身体坐标 = `框中心 + (fx − 0.5) × 绘制宽`，
  /// 而 `fx`（alpha 加权质心占画布宽的比例）三态各不相同（0.5559 / 0.4400 / 0.4660）。
  ///
  /// 把 `−(fx − 0.5) × 绘制宽` 这一位移加上去 ⇒ 三态**身体必然共线**，
  /// 兵器怎么挥都不影响站位。常量表见 [kGuardSoldierStateCentroidX]。
  ///
  /// 实测（390 屏，绘制高 68）：idle **−3.70** / attack **+5.99** / win **+2.76**
  /// ⇒ 修正前攻击帧身体比待机**左移 9.69pt**，修正后 0。
  static double soldierStateAlignShiftX(String state, double paintHeight) {
    final double fx = kGuardSoldierStateCentroidX[state] ?? 0.5;
    return -(fx - 0.5) * soldierStatePaintWidth(state, paintHeight);
  }

  /// 子弹**实际渲染**边长（= [bulletSize] × [scale]）。
  double get bulletExtent => bulletSize * e;

  /// 右簇槽位矩形（开始钮；战斗中留空但**照样占位**）。
  Rect get rightClusterRect {
    final double s = e;
    return Rect.fromLTWH(
      cardWidth - padRight * s - rightClusterSize * s,
      baselineY - rightClusterSize * s,
      rightClusterSize * s,
      rightClusterSize * s,
    );
  }

  /// 战斗通道的左端 —— 怪走到这里 = 「攻到门口被战士挡住」。
  ///
  /// 🔴 B9/C3（玄参选的 C 方案）：从 `soldierRect.right` 改成
  /// `soldierRect.right − monsterExtent × 0.5` ⇒ 怪物**半个身子压在战士身上**
  /// 才停下（视觉上就是被挡住），而不是隔着一个身位干瞪眼。
  /// 只在本值里改，sim 的行程 / 到门判定**一个字节不动**。
  ///
  /// 实测（390 屏，scale 1.0，B10/C1 战士 68）：`soldierRect.right =
  /// 156.17 + 2 + 68 = 226.17`，`monsterExtent / 2 = 22` ⇒ 通道左端
  /// **204.17**；通道右端 `390 − 8 − 64 − 4 = 314` ⇒ 跑道 **109.83pt**
  /// （B9 是 99.83，战士缩小 10pt 全部变成了跑道）。
  double get channelLeft => soldierRect.right - monsterExtent * 0.5;

  /// 战斗通道的右端（= 右簇左缘 − 间隙）—— 怪从这里入场。
  ///
  /// 🔴 钳到 ≥ [channelLeft]：极窄卡上若放任负数，怪会被渲染到战士**左边**
  /// （视觉上「从花园里冒出来」）。
  double get channelRight =>
      math.max(rightClusterRect.left - channelGap * e, channelLeft);

  /// 战斗通道宽度（唯一随屏宽变化的量；窄卡下钳到 0）。
  ///
  /// 实测（B10/C1）：390 卡 **109.83pt**（`314 − 204.17`）/ 320 卡（×0.85）
  /// **83.36pt** / 1024 卡 **733.84pt**（战士变小对宽卡无感，右簇贴右缘）。
  /// 与 B9 相比 390 屏 +10pt：战士 78 → 68 且间隙 2 不变。
  double get channelWidth {
    final double w = channelRight - channelLeft;
    return w > 0 ? w : 0;
  }

  /// 倒计时细线矩形（卡片底部通栏）。
  Rect get countdownRect => Rect.fromLTWH(
        padLeft * e,
        kGuardSceneCardHeight * uiScale -
            countdownBottomInset * e -
            countdownHeight * e,
        math.max(cardWidth - 2 * padLeft * e, 0),
        countdownHeight * e,
      );

  // ── sim 坐标 → 卡内渲染坐标（🔴 镜像在这里，sim 零改动）─────────────

  /// 横向映射：`simX ∈ [0, 330]` ⇒ 卡内 x，**镜像**（sim 0 在右、330 在左）。
  ///
  /// sim 的行程 / 速率 / 到门判定**一个字节都没动**
  /// （`kGuardBattleFieldTravelPt` 只是被当刻度用）。
  double mapMonsterX(double simX) {
    final double progress = (simX / kGuardBattleFieldTravelPt).clamp(0.0, 1.0);
    return channelRight - progress * channelWidth;
  }

  /// 子弹横向映射：与怪**同一把尺子**（sim 坐标同域），故方向自动镜像 ——
  /// 怪在右⇒子弹向右飞，怪越到左边⇒子弹往左飞（自瞄语义零改动）。
  double mapBulletX(double simX) => mapMonsterX(simX);

  /// 纵向映射：`simY ∈ [laneTop, laneBottom]` ⇒ 怪中心 y（卡内坐标）。
  ///
  /// 围绕**战士中心**摆一条 ±[monsterBandHalfHeight] 的窄带
  /// （玄参「车道与战士同一水平带」），不再按旧卡高做上下错层。
  /// 换道（sim 的 `lane_shift_*`）在此表现为带内平移 —— 幅度只有 ±8pt，
  /// 换道的视觉存在感由**演出层**的 300~500ms 平滑插值提供（见 sim）。
  double mapMonsterY(double simY) {
    const double span = kGuardBattleLaneBottomPt - kGuardBattleLaneTopPt;
    final double t =
        span <= 0 ? 0.5 : ((simY - kGuardBattleLaneTopPt) / span).clamp(0.0, 1.0);
    final double half = monsterBandHalfHeight * e;
    final double y = soldierCenterY + (t - 0.5) * 2 * half;
    // 🔴 B13.2 渲染安全钳（只钳**渲染落点**，sim 的车道 / 到门判定零改动）：
    // 战士 60 高下，带的最低点（t=1）+ 半个怪恰好压上卡底倒计时细线。
    // 钳到「细线上方留 1pt」；带**顶部不动**（「同一水平带」语义保留，
    // 子弹与怪共用本尺 ⇒ 一起钳，不会错位）。
    final double maxY = countdownRect.top - monsterExtent * 0.5 - 1;
    return y > maxY ? maxY : y;
  }

  /// 子弹纵向映射（与怪同尺）。
  double mapBulletY(double simY) => mapMonsterY(simY);
}
