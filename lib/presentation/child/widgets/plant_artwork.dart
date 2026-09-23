/// 植物外观组件（渲染层抽象，2026-09-22 玄参大人拍板）。
///
/// ## 目的
/// 植物当前只是「卡片 + Material 图标」，美术资源到位后需要**不改动任何调用方代码**
/// 就能替换成正式插画。本组件把「植物长什么样」从 [PlantCard] 里彻底抽离。
///
/// ## 美术资源命名规范（三级回退，美术只需按规范丢图，代码零改动）
/// 资源根目录 `assets/plants/`，按「物种_阶段_状态」命名，从最精确往回找：
/// ```
/// ① assets/plants/{speciesId}_{stage}_{status}.png   最精确，用于特殊状态
/// ② assets/plants/{speciesId}_{stage}.png            常用
/// ③ assets/plants/{speciesId}.png                    该物种通用
/// ④ 以上都没有 → 回退到内置自绘简笔（[PlantPlaceholderArt]）
/// ```
/// 其中：
/// - `{speciesId}` = `PlantSpecies.id`，当前为 `species_sunflower` / `species_daisy` / `species_cactus`
/// - `{stage}` = `seed` / `sprout` / `adult`
/// - `{status}` = `growing` / `bloomed` / `wilting` / `dead`
///
/// 例：`assets/plants/species_sunflower_adult_bloomed.png`
/// 只要文件名对上就会自动生效，新增植物/阶段都不需要改本文件。
///
/// 资源是否存在的判定走 [AssetManifest.loadFromAssetBundle]（读的是编译期生成的
/// `AssetManifest.bin`），结果按「物种_阶段_状态」缓存，整个进程只解析一次清单。
///
/// ⚠️ **不要用 `rootBundle.loadString('AssetManifest.json')`**：Flutter 3.7 起打包只产
/// `AssetManifest.bin`，`.json` 已不再生成 —— 2026-09-23 在 Flutter 3.44.7 实测：装到手机的
/// APK 里只有 `assets/flutter_assets/AssetManifest.bin`，flutter_tools 源码里也搜不到任何
/// `.json` 生成逻辑。读 `.json` 会抛异常 → 静默回退到自绘占位，表现为「美术图放进去了界面
/// 却没变化」，而且**不崩、不报错**，排查方向会完全跑偏（会误以为图错了/命名错了）。
library plant_artwork;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

/// 美术资源命名契约（**公开、纯函数、可单测**）。
///
/// 这是美术与代码之间**唯一的接口**：美术按 [forPlant] 生成的路径命名丢图，
/// 代码按同一份规则查找。此处是契约的唯一真源，改这里即改契约。
///
/// 为什么单独提成公开类：它此前埋在私有类里、没有任何测试保护，于是「读不到清单 →
/// 静默回退占位」这个缺陷能一直潜伏到美术真正出图才可能被发现。
class PlantArtCandidates {
  /// 纯静态命名空间，禁止实例化。
  PlantArtCandidates._();

  /// 候选路径（顺序即回退优先级）：
  /// `{物种}_{阶段}_{状态}` → `{物种}_{阶段}` → `{物种}`，全不中则走自绘占位。
  static List<String> forPlant({
    required String speciesId,
    required String stage,
    required String status,
  }) =>
      <String>[
        'assets/plants/${speciesId}_${stage}_$status.png',
        'assets/plants/${speciesId}_$stage.png',
        'assets/plants/$speciesId.png',
      ];

  /// 在 [assets]（资产清单里的全部资源路径）中按优先级找命中项；无命中返回 null。
  static String? resolve(
    Set<String> assets, {
    required String speciesId,
    required String stage,
    required String status,
  }) {
    for (final String path in forPlant(
      speciesId: speciesId,
      stage: stage,
      status: status,
    )) {
      if (assets.contains(path)) return path;
    }
    return null;
  }
}

/// 资源清单缓存（懒加载，进程内只解析一次）。
class _PlantArtAssets {
  /// 资产清单里的全部资源路径（懒加载，进程内只解析一次）。
  static Set<String>? _allAssets;

  /// 已解析结果缓存：key = 「物种_阶段_状态」→ 命中的资源路径（null = 无资源，走占位）。
  static final Map<String, String?> _resolved = <String, String?>{};

  static Future<Set<String>> _loadManifest() async {
    final Set<String>? cached = _allAssets;
    if (cached != null) return cached;
    try {
      final AssetManifest manifest =
          await AssetManifest.loadFromAssetBundle(rootBundle);
      return _allAssets = manifest.listAssets().toSet();
    } catch (error) {
      // 清单读不到时不能崩，但**绝不能静默** —— 否则「美术资源不生效」会被
      // 误判成「图错了 / 命名错了」，白白浪费美术工时。
      debugPrint('[PlantArtwork] 资产清单读取失败，本次会话内美术资源不生效：$error');
      return _allAssets = const <String>{};
    }
  }

  /// 按三级回退规则解析资源路径；无资源返回 null（调用方改用自绘占位）。
  static Future<String?> resolve({
    required Plant plant,
    required PlantSpecies species,
  }) async {
    final String stage = plant.stage.name;
    final String status = plant.status.name;
    final String key = '${species.id}_${stage}_$status';

    final String? cached = _resolved[key];
    if (cached != null || _resolved.containsKey(key)) return cached;

    final Set<String> assets = await _loadManifest();
    return _resolved[key] = PlantArtCandidates.resolve(
      assets,
      speciesId: species.id,
      stage: stage,
      status: status,
    );
  }
}

/// 植物外观（美术资源优先，缺失自动回退内置自绘简笔）。
///
/// 调用方只需传 [plant] / [species] / [size]，无需关心当前有没有美术资源：
/// 资源到位后自动切换，UI 代码不用动。
class PlantArtwork extends StatelessWidget {
  final Plant plant;
  final PlantSpecies species;

  /// 正方形边长。
  final double size;

  /// 状态色（用于占位底色；与卡片状态色保持一致）。
  final Color? tint;

  /// **随本阶段进度放大的幅度**（0 = 不放大）。
  ///
  /// 草地上用来让「浇一次水」看得见变化；实现方式是**从略小开始长到满格**
  /// （而非放大到超出画框），因此永远不会被圆形裁掉顶部花瓣：
  /// 进度 0 → 内边距最大，进度 1 → 内边距 0。
  final double growthScale;

  const PlantArtwork({
    super.key,
    required this.plant,
    required this.species,
    this.size = 44,
    this.tint,
    this.growthScale = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = plant.growthProgress.clamp(0.0, 1.0);
    // 进度越低，四周留白越多 → 视觉上「慢慢长大」。
    final double pad = size * growthScale * (1.0 - progress) / 2;
    return FutureBuilder<String?>(
      future: _PlantArtAssets.resolve(plant: plant, species: species),
      builder: (BuildContext context, AsyncSnapshot<String?> snap) {
        final String? path = snap.data;
        return Padding(
          padding: EdgeInsets.all(pad),
          child: path == null
              ? PlantPlaceholderArt(
                  plant: plant,
                  species: species,
                  size: size,
                )
              : Image.asset(
                  path,
                  fit: BoxFit.contain,
                  // 资源存在但解码失败时（坏图）不至于整页崩掉。
                  errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                      PlantPlaceholderArt(
                    plant: plant,
                    species: species,
                    size: size,
                  ),
                ),
        );
      },
    );
  }
}

/// 内置自绘简笔植物（美术资源缺失时的占位）。
///
/// 刻意画得可辨识：按物种区分形态（向日葵 / 小雏菊 / 仙人掌），
/// 按阶段区分高矮（种子 / 幼苗 / 成株），按状态调色（枯萎转褐、死亡转灰）。
class PlantPlaceholderArt extends StatelessWidget {
  final Plant plant;
  final PlantSpecies species;
  final double size;

  const PlantPlaceholderArt({
    super.key,
    required this.plant,
    required this.species,
    required this.size,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _PlantPlaceholderPainter(
          speciesId: species.id,
          stage: plant.stage,
          status: plant.status,
        ),
      );
}

/// 简笔植物绘制器。
class _PlantPlaceholderPainter extends CustomPainter {
  final String speciesId;
  final PlantStage stage;
  final PlantStatus status;

  const _PlantPlaceholderPainter({
    required this.speciesId,
    required this.stage,
    required this.status,
  });

  static const Color _soil = Color(0xFF8D6E63);

  bool get _isDead => status == PlantStatus.dead;
  bool get _isWilting => status == PlantStatus.wilting;

  Color get _stem =>
      _isDead ? Colors.grey.shade600 : (_isWilting ? Colors.brown.shade400 : Colors.green.shade700);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double groundY = h * 0.80;

    _drawSoil(canvas, w, groundY);

    switch (stage) {
      case PlantStage.seed:
        _drawSeed(canvas, w, groundY);
        break;
      case PlantStage.sprout:
        _drawStem(canvas, w, groundY, h * 0.42);
        _drawLeaves(canvas, w, groundY, h * 0.42, big: false);
        break;
      case PlantStage.adult:
        _drawStem(canvas, w, groundY, h * 0.58);
        _drawLeaves(canvas, w, groundY, h * 0.58, big: true);
        _drawFlower(canvas, w, groundY - h * 0.58);
        break;
    }
  }

  void _drawSoil(Canvas canvas, double w, double groundY) {
    final Paint paint = Paint()
      ..color = _isDead ? Colors.grey.shade400 : _soil
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromLTWH(w * 0.20, groundY, w * 0.60, w * 0.34),
      0,
      3.14159,
      true,
      paint,
    );
  }

  void _drawSeed(Canvas canvas, double w, double groundY) {
    final Paint paint = Paint()
      ..color = _isDead ? Colors.grey.shade500 : const Color(0xFFC9A227)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, groundY - w * 0.06),
          width: w * 0.16,
          height: w * 0.11),
      paint,
    );
  }

  void _drawStem(Canvas canvas, double w, double groundY, double height) {
    final Paint paint = Paint()
      ..color = _stem
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // 枯萎时茎向右弯，视觉上「蔫了」。
    final double bend = _isWilting ? w * 0.10 : (_isDead ? -w * 0.06 : 0);
    final Offset top = Offset(w * 0.5 + bend, groundY - height);
    canvas.drawLine(Offset(w * 0.5, groundY), top, paint);
  }

  void _drawLeaves(
    Canvas canvas,
    double w,
    double groundY,
    double height, {
    required bool big,
  }) {
    if (_isCactus) return; // 仙人掌无叶片，用刺代替（见 _drawFlower）
    final Paint paint = Paint()
      ..color = _stem.withOpacity(0.85)
      ..style = PaintingStyle.fill;
    final double leafW = big ? w * 0.26 : w * 0.19;
    final double leafH = big ? w * 0.13 : w * 0.09;
    final double midY = groundY - height * 0.55;
    // 左叶
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5 - leafW * 0.5, midY),
          width: leafW,
          height: leafH),
      paint,
    );
    // 右叶
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5 + leafW * 0.5, midY + leafH * 0.35),
          width: leafW,
          height: leafH),
      paint,
    );
  }

  bool get _isCactus => speciesId == 'species_cactus';
  bool get _isDaisy => speciesId == 'species_daisy';

  void _drawFlower(Canvas canvas, double w, double centerY) {
    if (_isCactus) {
      _drawCactusBody(canvas, w, centerY);
      return;
    }
    final bool dead = _isDead || _isWilting;
    final Color petal = dead ? Colors.grey.shade500 : const Color(0xFFF6C445);
    final Color core = dead ? Colors.grey.shade700 : const Color(0xFF6D4C41);
    final double cx = w * 0.5;
    final double cy = centerY + w * 0.02;
    final double r = _isDaisy ? w * 0.13 : w * 0.17;

    // 花瓣（8 片，绕中心）
    final Paint petalPaint = Paint()
      ..color = petal
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 8; i++) {
      final double angle = i * 3.14159 / 4;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + r * 0.95 * _cos(angle), cy + r * 0.95 * _sin(angle)),
          width: r * 0.72,
          height: r * 0.46,
        ),
        petalPaint,
      );
    }
    // 花心
    canvas.drawCircle(Offset(cx, cy), r * 0.62, Paint()..color = core);
  }

  void _drawCactusBody(Canvas canvas, double w, double centerY) {
    // 仙人掌：柱体 + 两侧小臂 + 顶部小花（死亡/枯萎转灰褐）
    final bool dead = _isDead || _isWilting;
    final Color body = dead ? Colors.grey.shade500 : Colors.green.shade600;
    final Paint paint = Paint()
      ..color = body
      ..style = PaintingStyle.fill;
    final double cx = w * 0.5;
    final double topY = centerY;
    final double bottomY = w * 0.80;

    // 主干
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w * 0.09, topY, w * 0.18, bottomY - topY),
        Radius.circular(w * 0.09),
      ),
      paint,
    );
    // 左右小臂
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w * 0.20, topY + w * 0.16, w * 0.09, w * 0.20),
        Radius.circular(w * 0.045),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + w * 0.11, topY + w * 0.24, w * 0.09, w * 0.20),
        Radius.circular(w * 0.045),
      ),
      paint,
    );
    // 顶部小花
    if (!dead) {
      canvas.drawCircle(
        Offset(cx, topY - w * 0.02),
        w * 0.055,
        Paint()..color = const Color(0xFFEC7BA0),
      );
    }
  }

  // 轻量三角函数（避免引入 dart:math 仅为两次调用）。
  static double _cos(double a) => _taylorCos(a);
  static double _sin(double a) => _taylorCos(a - 1.5707963267948966);

  static double _taylorCos(double x) {
    double v = x % 6.283185307179586;
    if (v > 3.141592653589793) v -= 6.283185307179586;
    if (v < -3.141592653589793) v += 6.283185307179586;
    final double x2 = v * v;
    return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
  }

  @override
  bool shouldRepaint(covariant _PlantPlaceholderPainter old) =>
      old.speciesId != speciesId || old.stage != stage || old.status != status;
}
