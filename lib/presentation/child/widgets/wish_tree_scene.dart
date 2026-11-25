/// 孩子端「美好愿望」场景视图（美术接入 2026-11-19 / 布局返工 2026-11-20 /
/// iPad 13 实机验收返工 2026-11-20 / 循环树美术换批 2026-11-20）。
///
/// 纯展示组件：不读 provider、不写状态机、不含任何业务逻辑。数据（每个蛋的
/// 资源 / 点击回调）、三个入口按钮回调均由页面组装后传入，便于 widget 测试
/// 直接构造宿主。所有素材经 `Image.asset` + `errorBuilder` 兜底 —— 素材缺失
/// 也不空白（回退彩色占位），符合仓库其它美术组件惯例。
///
/// ## 布局（返工口径：一个占满 body 的全屏沉浸场景）
///  · 底层：背景湖景 `BoxFit.cover` + `Alignment.topCenter` 铺满**整个场景**。
///    用 [LayoutBuilder] 取真实场景约束，而非 MediaQuery 整屏高度 —— 本组件
///    被放进有 AppBar 的 Expanded 里，整屏高度与场景高度并不相等。
///  · 中层：循环树帧 `tree_frames/frame001.webp`~`frame051.webp`（720×960，
///    **3:4 竖图**）10 秒一轮无限循环；树高仍约为场景高 72%，树框宽 =
///    高 × 0.75。**真实树根像素**（图纵向 93.23%，PIL alpha>128 扫描
///    x∈[40%,60%] 主轴，最低不透明行 y=895/960 实测）锚定在背景土坡小岛
///    （原图纵向 79.0%，沙洲核心质心实测）。小岛在**场景**里的位置按 cover
///    缩放动态计算，而非写死 0.78 —— 这是 iPad 上树根浮空的根因。
///    🔴 旧静态树 `tree.webp` 是 2048² 方图、树根 0.852，换批后绝不能沿用
///    那套方图几何，否则树根陷进土坡、整棵树视觉下坠。
///  · 蛋按 [eggSpots] 挂在**树冠下方**（新帧纵向 63%~73%，横向 20%~80%
///    仍落在新树身上），横向铺开避开主干；蛋下不再挂任何文字角标。
///  · 顶层：愿望蛋可点击（进详情）；底部三按钮 —— 左收藏箱 / 中许愿 / 右愿望池。
///
/// ## 三态蛋（玄参 2026-11-19 口径）
///  · 许愿蛋 `egg_wish.webp`    —— 刚许愿（S1 未回应 / S2 已回应未布置办法）。
///  · 正在实现蛋 `egg_growing.webp` —— 父母已布置达成任务（S3 hasWays）。
///  · 达成蛋 `egg_done.webp`    —— 愿望已完成（达成池）。
/// 选图在页面层完成（复用领域三态判据），本组件只认传入的 asset 字符串。
/// S3 的办法数量证据下沉到详情浮层列表，树上蛋只呈现蛋图，不渲染角标。
library wish_tree_scene;

import 'package:flutter/material.dart';

/// 许愿树场景素材路径（扁平目录 `assets/wish_tree/`，pubspec 已声明）。
///
/// ⚠️ 2026-11-25 装包瘦身批：本目录 8 张 PNG → WebP q95（17.1 MB → 2.8 MB，
/// PSNR 40~44 dB，画布/alpha 零变化，管线 `tools/convert_assets_webp.py`）。
/// 树上 51 帧同批转 WebP（`tree_frames/*.webp`），帧数不变。
class WishTreeArt {
  const WishTreeArt._();

  static const String background = 'assets/wish_tree/background.webp';

  /// 🔴 旧静态树（2048² 方图）**保留文件不删**（别处可能引用），但本场景
  /// 自 2026-11-20 起改用下方 51 帧循环树，不再渲染它。
  static const String tree = 'assets/wish_tree/tree.webp';

  /// 循环树帧目录（51 张，文件名 frame001…frame051，目录声明不递归）。
  static const String treeFrameDir = 'assets/wish_tree/tree_frames';

  /// 第 [index] 帧（0-based）的资源路径；越界由调用方 [wishTreeFrameIndex] 保证。
  static String treeFrameAsset(int index) =>
      '$treeFrameDir/frame${(index + 1).toString().padLeft(3, '0')}.webp';

  static const String eggWish = 'assets/wish_tree/egg_wish.webp';
  static const String eggGrowing = 'assets/wish_tree/egg_growing.webp';
  static const String eggDone = 'assets/wish_tree/egg_done.webp';
  static const String box = 'assets/wish_tree/keepsake_box.webp';
  static const String pool = 'assets/wish_tree/wish_pool.webp';
}

/// 循环树帧索引**纯函数**（QA 可直接变异测试，不依赖 Flutter 宿主）。
///
/// [progress] 为动画进度，正常取值 ∈ [0,1)；返回 [0, frameCount-1] 内的帧号。
/// 1.0 与正越界值按最后一帧处理（clamp），负值与 NaN 按第 0 帧处理；
/// [frameCount] <= 0 时无有效帧，返回 0（防御性，不抛异常）。
int wishTreeFrameIndex(double progress, int frameCount) {
  if (frameCount <= 0) return 0;
  if (progress.isNaN) return 0;
  // +∞ 走 >1 分支 clamp 到最后一帧；-∞ 走 <0 分支 clamp 到首帧。
  final double safe = progress < 0 ? 0 : progress > 1 ? 1 : progress;
  final int index = (safe * frameCount).floor();
  return index >= frameCount ? frameCount - 1 : index;
}

/// 场景布局常量（全部相对真实场景尺寸，禁止再用整屏高度错位）。
class WishTreeSceneLayout {
  const WishTreeSceneLayout._();

  /// 循环树帧数（`frame001.webp` ~ `frame051.webp`）。
  static const int treeFrameCount = 51;

  /// 一轮循环时长（`AnimationController..repeat()`，页面不可见随与 vsync 停）。
  static const Duration treeFrameCycle = Duration(seconds: 10);

  /// 树**框高度**占场景高度的比例。
  static const double treeHeightRatio = 0.72;

  /// 新帧是 720×960 竖图：框宽 = 框高 × 0.75（不是旧树的正方形）。
  ///
  /// 新帧 alpha>128 的可见树身 bbox x∈[0.079,0.917]、y∈[0.118,0.932]，
  /// 几乎铺满整帧；旧方图可见树冠只有图宽的 ~71%，故旧 1.48 倍的宽度口径
  /// 现在只当作**极窄屏保护上限**：`treeWidth <= sceneWidth × 1.48`，
  /// 超限时反推树高（`treeHeight = treeWidth / 0.75`）。
  static const double treeWidthHeightRatio = 0.75;
  static const double treeMaxWidthRatio = 1.48;

  /// 树帧中**真实树根**所在的纵向比例。
  ///
  /// 实测方法：PIL 读 `frame001.png`(720×960) alpha 通道（现已转 WebP，
  /// 画布与 alpha 逐像素不变，比例口径继续有效），取 x∈[40%,60%]
  /// 树干主轴，6 帧抽样（001/011/021/026/041/051）alpha>128 的最低不透明行
  /// 均为 y=895 ⇒ 895/960 = 0.93229；整图可见 bbox 最低行同样是 895。
  /// 🔴 旧值 0.852 属于旧方图 2048² 的树根（1745/2048），换批后若沿用会让
  /// 新树整体下坠、树根陷进背景土坡。
  static const double treeRootFraction = 0.9323;

  /// 背景图尺寸（`background.webp` 实测 1728×2304）。
  static const double backgroundWidth = 1728;
  static const double backgroundHeight = 2304;

  /// 背景图里**土坡沙洲小岛中心**的纵向比例（相对原图高 2304）。
  ///
  /// 实测方法：PIL 取 y∈[70%,86%]、x∈[28%,72%] 内暖色浅沙像素，
  /// 以 (R−B) 为权重求质心 y=1820 ⇒ 1820/2304 = 0.7901；
  /// 不加权质心 0.7944，沙洲纵向跨度 0.728~0.859。取 0.790。
  static const double islandImageFraction = 0.790;

  /// 蛋尺寸相对场景宽度（新蛋 alpha 边界与旧蛋几乎一致，不改）。
  static const double eggSizeRatio = 0.13;

  /// 收藏箱 / 愿望池 / 许愿三按钮圆形容器直径。
  ///
  /// 玄参 iPad 13 反馈「图标有点小」：从原 68dp 放大。
  /// 按场景宽度 22% 自适应（手机 390dp ⇒ 86dp），上下限 84~92dp
  /// 防止 iPad 1032dp 宽时按 22% 算出 227dp 的荒谬尺寸。
  static const double actionButtonMin = 84;
  static const double actionButtonMax = 92;
  static const double actionButtonWidthRatio = 0.22;

  /// 背景用 `BoxFit.cover` + `Alignment.topCenter` 时，原图纵向比例
  /// [imageFraction] 处的像素落在**场景**里的 y 坐标。
  ///
  /// cover 缩放：`scale = max(sceneW/bgW, sceneH/bgH)`；缩放后图高
  /// `scaledH = bgH * scale >= sceneH`。`topCenter` 把图顶钉在场景顶，
  /// 垂直偏移恒为 0，故原图 fraction 处 → 场景 y = fraction * scaledH。
  /// 极端横屏下小岛可能被裁到场景之外，夹到场景内保证树不整体消失。
  static double sceneYOfBackgroundFraction(Size scene, double imageFraction) {
    final double scale = scene.width / backgroundWidth > scene.height / backgroundHeight
        ? scene.width / backgroundWidth
        : scene.height / backgroundHeight;
    final double scaledHeight = backgroundHeight * scale;
    final double y = imageFraction * scaledHeight;
    if (y < 0) return 0;
    if (y > scene.height) return scene.height;
    return y;
  }
}

/// 树上单颗蛋的展示数据。
class WishEgg {
  const WishEgg({
    required this.asset,
    required this.label,
    required this.onTap,
    this.key,
  });

  /// 蛋图路径（三态之一，页面层按 wishTreeFaceOf 选好）。
  final String asset;

  /// 无障碍 / tooltip 文案（愿望原文，供语义树读取）。
  final String label;

  /// 点击进愿望详情。
  final VoidCallback onTap;

  /// 稳定 key（页面层传 `Key('wish_card_${wish.id}')` 接过原卡片的点击标识）。
  final Key? key;
}

/// 循环树帧播放器：10 秒一轮、无限循环、帧变化时才 rebuild。
///
/// 用 [SingleTickerProviderStateMixin] 让**页面不可见时 vsync 自动停摆**
/// （比 `Timer.periodic` 稳，后台不空转）；[AnimationController] 在
/// [dispose] 中释放，杜绝路由 pop 后泄漏 Ticker。
class _AnimatedWishTree extends StatefulWidget {
  const _AnimatedWishTree({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  State<_AnimatedWishTree> createState() => _AnimatedWishTreeState();
}

class _AnimatedWishTreeState extends State<_AnimatedWishTree>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: WishTreeSceneLayout.treeFrameCycle,
    );
    _controller.addListener(_onTick);
    _controller.repeat();
  }

  /// 只在帧号真的变化时 setState：60fps 的 tick 不会触发 60 次整树 rebuild
  /// （51 帧 / 10 秒 ≈ 5 次/秒）。
  void _onTick() {
    final int next = wishTreeFrameIndex(
      _controller.value,
      WishTreeSceneLayout.treeFrameCount,
    );
    if (next != _frameIndex) {
      setState(() => _frameIndex = next);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    // 51 张 720×960 全解码约 140MB，超过 imageCache 默认上限会反复解码卡顿。
    // 按**实际显示像素 × dpr** 解码，并用源图像素封顶（不无意义放大）：
    // 手机 390 宽场景约 324×432 逻辑像素 ⇒ dpr=1 时解码量降到 ~1/4。
    final int cacheWidth = (widget.width * dpr).ceil().clamp(1, 720);
    final int cacheHeight = (widget.height * dpr).ceil().clamp(1, 960);
    return Image.asset(
      WishTreeArt.treeFrameAsset(_frameIndex),
      key: const Key('wish_scene_tree'),
      width: widget.width,
      height: widget.height,
      fit: BoxFit.fill,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      // 新帧尚未解码完时继续显示上一帧，避免帧间白闪。
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.park,
        size: 120,
        color: Color(0xFF6B8E23),
      ),
    );
  }
}

/// 「美好愿望」沉浸场景。
class WishTreeScene extends StatelessWidget {
  const WishTreeScene({
    super.key,
    required this.eggs,
    required this.onStartWish,
    required this.onOpenBox,
    required this.onOpenPool,
    required this.boxLabel,
    required this.poolLabel,
    required this.startLabel,
    this.boxCount = 0,
    this.poolCount = 0,
    this.actionScale = 1.0,
  });

  /// 树上愿望蛋（按 treeSlot 升序传入）。
  final List<WishEgg> eggs;

  final VoidCallback onStartWish;
  final VoidCallback onOpenBox;
  final VoidCallback onOpenPool;

  final String boxLabel;
  final String poolLabel;
  final String startLabel;

  /// 收藏箱 / 愿望池条数（角标，0 不显示）。
  final int boxCount;
  final int poolCount;

  /// R7-P0-03：底部三圆形按钮的单侧缩放系数（由页面传 `compactScaleOf`）。
  ///
  /// 默认 1.0（iPad / 其它宿主逐字节不变）；手机 0.8 在 actionSize 计算末尾乘入，
  /// 三按钮共用一处覆盖。85.8 × 0.8 ≈ 68.6dp ≥ 48dp 热区底线。
  final double actionScale;

  /// 蛋在**树冠下方**的相对锚点（x, y ∈ 0~1，相对树图框）。
  ///
  /// 新帧（720×960，3:4）纵向 0.118~0.932 几乎全是树身；蛋仍放在
  /// 0.63~0.73 的枝条两侧、横向 0.20~0.80 避开主干，与玄参「蛋要在树冠
  /// 的下面」口径一致。**坐标系不变**，只是框由方图换成 3:4。
  static const List<Offset> eggSpots = <Offset>[
    Offset(0.28, 0.63),
    Offset(0.72, 0.63),
    Offset(0.20, 0.67),
    Offset(0.80, 0.67),
    Offset(0.34, 0.70),
    Offset(0.66, 0.70),
    Offset(0.26, 0.73),
    Offset(0.74, 0.73),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 🔴 用真实场景约束（本组件在 AppBar 下的 Expanded 内），
        // 不再用 MediaQuery 整屏高度算树的位置 —— 那是上一轮树被裁掉的根因。
        final Size size = Size(
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width,
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );

        // 3:4 树框：高度按场景 72%，极窄屏按「宽度 ≤ 场景宽 ×1.48」反推高度。
        // 🔴 真实树根（帧纵向 0.9323）锚定背景小岛在 cover 后的场景位置。
        final double treeHeightByHeight =
            size.height * WishTreeSceneLayout.treeHeightRatio;
        final double treeHeightByWidth = size.width *
                WishTreeSceneLayout.treeMaxWidthRatio /
            WishTreeSceneLayout.treeWidthHeightRatio;
        final double treeHeight = treeHeightByHeight < treeHeightByWidth
            ? treeHeightByHeight
            : treeHeightByWidth;
        final double treeWidth =
            treeHeight * WishTreeSceneLayout.treeWidthHeightRatio;
        final double treeLeft = (size.width - treeWidth) / 2;
        final double islandSceneY = WishTreeSceneLayout.sceneYOfBackgroundFraction(
          size,
          WishTreeSceneLayout.islandImageFraction,
        );
        final double treeTop = islandSceneY -
            WishTreeSceneLayout.treeRootFraction * treeHeight;
        final double eggSize = size.width * WishTreeSceneLayout.eggSizeRatio;
        // R7-P0-03：先 clamp 再乘系数 —— iPad 恒 ×1.0 逐位不变；
        // 手机 85.8×0.8≈68.6dp（≥48 热区）。三按钮共用本值，一处覆盖。
        final double actionSize =
            (size.width * WishTreeSceneLayout.actionButtonWidthRatio).clamp(
          WishTreeSceneLayout.actionButtonMin,
          WishTreeSceneLayout.actionButtonMax,
        ) * actionScale;

        return Stack(
          children: <Widget>[
            // ── 背景湖景（自带土坡小岛，BoxFit.cover + topCenter 铺满场景）──
            Positioned.fill(
              child: Image.asset(
                WishTreeArt.background,
                key: const Key('wish_scene_background'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, __, ___) =>
                    Container(color: const Color(0xFFDFF3D0)),
              ),
            ),

            // ── 循环树（水平居中，真实树根压在土坡小岛上）────────────────
            Positioned(
              left: treeLeft,
              top: treeTop,
              width: treeWidth,
              height: treeHeight,
              child: _AnimatedWishTree(width: treeWidth, height: treeHeight),
            ),

            // ── 树上的愿望蛋（一愿望一蛋，挂在树冠下方）───────────────
            for (int i = 0; i < eggs.length; i++)
              _EggSlot(
                spot: eggSpots[i % eggSpots.length],
                layer: i ~/ eggSpots.length,
                treeLeft: treeLeft,
                treeTop: treeTop,
                treeWidth: treeWidth,
                treeHeight: treeHeight,
                eggSize: eggSize,
                egg: eggs[i],
              ),

            // ── 底部三按钮：左收藏箱 / 中许愿 / 右愿望池 ────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildActionBar(context, actionSize),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionBar(BuildContext context, double actionSize) {
    // 🔴 渐变遮罩只绘制、不吃点击（IgnorePointer）：小屏上树冠下沿的蛋可能
    // 视觉上落在底栏区域，若让 Container 参与命中测试会挡住蛋的点击进详情。
    // 按钮行本身照常接收点击，二者叠在同一个 Stack 里。
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00FFFFFF), Color(0xB3FFFFFF)],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _sceneImageButton(
                key: const Key('wish_scene_box_button'),
                asset: WishTreeArt.box,
                label: boxLabel,
                count: boxCount,
                size: actionSize,
                onTap: onOpenBox,
              ),
              _wishButton(context, actionSize),
              _sceneImageButton(
                key: const Key('wish_scene_pool_button'),
                asset: WishTreeArt.pool,
                label: poolLabel,
                count: poolCount,
                size: actionSize,
                onTap: onOpenPool,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 中间许愿按钮：页面通过 startLabel 传入文案，onStartWish 驱动点击。
  /// key 用 wish_scene_start_button；页面层的 wish_tree_start 按钮仍在源码守卫里。
  Widget _wishButton(BuildContext context, double size) => Builder(builder: (_) {
        return Semantics(
          button: true,
          label: startLabel,
          child: GestureDetector(
            key: const Key('wish_scene_start_button'),
            onTap: onStartWish,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFB74D),
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(Icons.add, size: size * 0.59, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  startLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B4E12),
                  ),
                ),
              ],
            ),
          ),
        );
      });

  Widget _sceneImageButton({
    required Key key,
    required String asset,
    required String label,
    required VoidCallback onTap,
    required double size,
    int count = 0,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              children: <Widget>[
                Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF3E0),
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        key == const Key('wish_scene_box_button')
                            ? Icons.inventory_2
                            : Icons.pool,
                        size: size * 0.53,
                        color: const Color(0xFF8D6E00),
                      ),
                    ),
                  ),
                ),
                if (count > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE65100),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B4E12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单颗蛋的定位壳层：[spot] 为树冠下方相对树框的坐标，
/// [layer] 用于多圈时轻微缩放错位。
class _EggSlot extends StatelessWidget {
  const _EggSlot({
    required this.spot,
    required this.layer,
    required this.treeLeft,
    required this.treeTop,
    required this.treeWidth,
    required this.treeHeight,
    required this.eggSize,
    required this.egg,
  });

  final Offset spot;
  final int layer;
  final double treeLeft;
  final double treeTop;
  final double treeWidth;
  final double treeHeight;
  final double eggSize;
  final WishEgg egg;

  @override
  Widget build(BuildContext context) {
    final double scale = 1.0 - (layer % 3) * 0.12;
    final double w = eggSize * scale;
    final double jitter = (layer % 2 == 0 ? -1 : 1) * eggSize * 0.22;
    return Positioned(
      // 横向用**树框宽**、纵向用**树框高**（3:4 后两者不再相等）。
      left: treeLeft + spot.dx * treeWidth - w / 2 + jitter,
      top: treeTop + spot.dy * treeHeight - w / 2,
      width: w,
      height: w,
      child: Semantics(
        button: true,
        label: egg.label,
        child: GestureDetector(
          // 🔴 接过原树卡的点击标识：真实页面测试按 wish_card_<id> 点进详情。
          key: egg.key,
          onTap: egg.onTap,
          child: Image.asset(
            egg.asset,
            width: w,
            height: w,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3C4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.egg, size: 28, color: Color(0xFFC58A00)),
            ),
          ),
        ),
      ),
    );
  }
}
