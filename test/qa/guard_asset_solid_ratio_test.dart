/// 守卫战 v2 · **素材实体比护栏**（B9/C1；玄参 2026-11-10 第四轮）。
///
/// ## 🔴 为什么要有这个测试
/// 玄参「战士太小 / 离房子太远」的**根因不是常量小，而是透明边**：
/// 裁边前 `soldier_idle` 的实体只占画布 **26%** 面积（左右各 ~24% 透明边）
/// ⇒ 标称 72pt 的战士肉眼只有 ~36pt；标称 6pt 的门房间隙肉眼成了 ~23pt。
/// B9 把素材按**实体并集 bbox** 裁掉透明边（`tools/convert_guard_b5b.py`，
/// 阈值 alpha > 128），从此 **标称尺寸 = 视觉尺寸**。
///
/// ## 判据（本文件钉的就是「裁边真的生效了」）
/// 对每组素材取「alpha > 128 的**并集** bbox」（同组共用一个裁切窗口 ⇒ 动画不抖），
/// 断言 bbox 的四条边**都贴着画布边**：单边留白 ≤ **3%**。
/// * 裁边前（量化记录）：`soldier_idle` 并集 bbox `(169,157,531,529)/720²`
///   ⇒ 左边 23.5% / 上边 21.8% / 右边 26.3% / 下边 26.5% —— 全面违规；
/// * 裁边后：全部 **0.0%**（见各用例的 reason 实测值）。
///
/// ## 例外（已上报）
/// `monster_m2`（食叶虫）源素材**出框**（7 帧并集 = 整张 720×720，frame002 铺满、
/// frame001 顶到左/上边）⇒ 无可裁，保留原画布。它的并集 bbox 仍等于画布
/// （边距 0%），故本判据同样通过；只是实体面积占比偏低（82.4% bbox 填充率），
/// 里里外外都不影响布局（怪是 44pt 方框 contain 绘制）。
library guard_asset_solid_ratio_test;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// 裁边阈值（与 `tools/convert_guard_b5b.py` 的 `ALPHA_THRESHOLD` 同源）。
const int kSolidAlphaThreshold = 128;

/// 单边留白上限（占画布边长的比例）。
const double kMaxMarginRatio = 0.03;

/// 一张素材的实体 bbox 量测结果。
class _SolidBBox {
  const _SolidBBox({
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int width;
  final int height;
  final int left;
  final int top;
  final int right;
  final int bottom;

  /// 四边留白占边长的**最大**比例（0 = 实体贴满画布）。
  double get worstMarginRatio {
    final double l = left / width;
    final double t = top / height;
    final double r = (width - right) / width;
    final double b = (height - bottom) / height;
    double worst = l;
    for (final double v in <double>[t, r, b]) {
      if (v > worst) worst = v;
    }
    return worst;
  }

  String get describe => '$width×$height，实体 bbox '
      '($left,$top,$right,$bottom)，最大边距 '
      '${(worstMarginRatio * 100).toStringAsFixed(2)}%';
}

/// 解码一张素材并按 alpha > [kSolidAlphaThreshold] 求实体 bbox。
///
/// `rawRgba` 是**预乘 alpha** 的，但 alpha 通道本身不被预乘 ⇒ 直接读第 4 字节。
Future<_SolidBBox> _measure(String asset) async {
  final ByteData data = await rootBundle.load(asset);
  final ui.Codec codec =
      await ui.instantiateImageCodec(data.buffer.asUint8List());
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final int w = image.width;
  final int h = image.height;
  final ByteData? raw =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(raw, isNotNull, reason: '素材解码失败：$asset');
  final Uint8List px = raw!.buffer.asUint8List();

  int left = w;
  int top = h;
  int right = 0;
  int bottom = 0;
  for (int y = 0; y < h; y++) {
    final int row = y * w * 4;
    for (int x = 0; x < w; x++) {
      if (px[row + x * 4 + 3] <= kSolidAlphaThreshold) continue;
      if (x < left) left = x;
      if (x + 1 > right) right = x + 1;
      if (y < top) top = y;
      if (y + 1 > bottom) bottom = y + 1;
    }
  }
  image.dispose();
  codec.dispose();
  expect(right, greaterThan(left), reason: '素材全透明（无实体）：$asset');
  expect(bottom, greaterThan(top), reason: '素材全透明（无实体）：$asset');
  return _SolidBBox(
    width: w,
    height: h,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
}

/// 一组帧的**并集** bbox（同一裁切窗口 ⇒ 播放时实体不跳）。
Future<_SolidBBox> _unionOf(List<String> assets) async {
  _SolidBBox? acc;
  for (final String a in assets) {
    final _SolidBBox b = await _measure(a);
    if (acc == null) {
      acc = b;
      continue;
    }
    expect(b.width, acc.width, reason: '同组帧画布宽必须一致：$a');
    expect(b.height, acc.height, reason: '同组帧画布高必须一致：$a');
    acc = _SolidBBox(
      width: acc.width,
      height: acc.height,
      left: b.left < acc.left ? b.left : acc.left,
      top: b.top < acc.top ? b.top : acc.top,
      right: b.right > acc.right ? b.right : acc.right,
      bottom: b.bottom > acc.bottom ? b.bottom : acc.bottom,
    );
  }
  expect(acc, isNotNull, reason: '空素材组');
  return acc!;
}

List<String> _frames(String dir, int count) => <String>[
      for (int i = 1; i <= count; i++)
        '$dir/frame${i.toString().padLeft(3, '0')}.webp',
    ];

void main() {
  // 🔴 本文件的用例是纯 `test()`（不起 widget 树）：解码素材与读 AssetManifest
  // 都要经 `ServicesBinding.instance` ⇒ 必须先初始化 binding，否则报
  // 「Binding has not yet been initialized」。
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① 战士待机 19 帧：并集 bbox 必须贴满画布 ───────────────────────────
  test('① soldier_idle 19 帧并集实体贴满画布（裁边前左右各 ~24% 透明边）', () async {
    final _SolidBBox box = await _unionOf(_frames('assets/guard/soldier_idle', 19));
    expect(box.worstMarginRatio, lessThanOrEqualTo(kMaxMarginRatio),
        reason: '🔴 裁边后标称 = 视觉：${box.describe}'
            '（裁边前 bbox (169,157,531,529)/720² ⇒ 最大边距 26.5%）');
  });

  // ── ② 三只怪各 7 帧：并集 bbox 贴满画布 ────────────────────────────────
  test('② monster_m1 / m2 / m3 各 7 帧并集实体贴满画布', () async {
    for (final String dir in <String>[
      'assets/guard/monster_m1',
      'assets/guard/monster_m2',
      'assets/guard/monster_m3',
    ]) {
      final _SolidBBox box = await _unionOf(_frames(dir, 7));
      expect(box.worstMarginRatio, lessThanOrEqualTo(kMaxMarginRatio),
          reason: '🔴 $dir 裁边生效：${box.describe}');
    }
  });

  // ── ③ 战士攻击 / 胜利静态：单张 bbox 贴满画布 ──────────────────────────
  test('③ soldier_attack / soldier_win 单张实体贴满画布', () async {
    for (final String asset in <String>[
      'assets/guard/soldier_attack.webp',
      'assets/guard/soldier_win.webp',
    ]) {
      final _SolidBBox box = await _measure(asset);
      expect(box.worstMarginRatio, lessThanOrEqualTo(kMaxMarginRatio),
          reason: '🔴 $asset 是「各裁各的窗口」的静态图：${box.describe}');
    }
  });

  // ── ④ 房子：**故意不裁**，但本来就 94.6% 实体（留白 ≤3%）──────────────
  test('④ house.webp 不裁边（整张场景图），实体占比本来就在 3% 以内', () async {
    final _SolidBBox box = await _measure('assets/guard/house.webp');
    expect(box.worstMarginRatio, lessThanOrEqualTo(kMaxMarginRatio),
        reason: '🔴 房子是完整场景图（不许按实体裁，否则草坡会被切）：'
            '${box.describe}');
    expect(box.width, 1984, reason: '素材原尺寸（宽高比 1.7746 的布局真源）');
    expect(box.height, 1118);
  });

  // ── ⑤ 战士三态宽高比：fitHeight 绘制的前提（各裁各的窗口）──────────────
  test('⑤ 三态宽高比各异（所以必须 fitHeight，不能用 contain）', () async {
    final _SolidBBox idle =
        await _unionOf(_frames('assets/guard/soldier_idle', 19));
    final _SolidBBox attack = await _measure('assets/guard/soldier_attack.webp');
    final _SolidBBox win = await _measure('assets/guard/soldier_win.webp');

    final double idleAspect = idle.width / idle.height;
    final double attackAspect = attack.width / attack.height;
    final double winAspect = win.width / win.height;

    expect(idleAspect, closeTo(0.973, 0.02), reason: '待机 362×372 ≈ 0.97');
    expect(attackAspect, closeTo(1.467, 0.02), reason: '攻击 512×349 ≈ 1.47');
    expect(winAspect, closeTo(1.194, 0.02), reason: '胜利 512×429 ≈ 1.19');
    // contain 会按**宽**缩到 78 / 1.47 ≈ 53pt（一开火就变小）⇒ 必须 fitHeight。
    expect(78 / attackAspect, lessThan(70),
        reason: '🔴 contain 下攻击帧只有 ${(78 / attackAspect).toStringAsFixed(1)}pt 高');
  });

  // ── ⑥ 素材命名守卫：两个新目录真的进了包（pubspec 目录声明不递归）───────
  test('⑥ m2 / m3 各 7 帧都在 AssetManifest 里（漏 pubspec 行 = 静默不进包）',
      () async {
    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    final Set<String> assets = manifest.listAssets().toSet();

    for (final String dir in <String>[
      'assets/guard/monster_m1',
      'assets/guard/monster_m2',
      'assets/guard/monster_m3',
      'assets/guard/soldier_idle',
    ]) {
      final Iterable<String> hit =
          assets.where((String p) => p.startsWith('$dir/frame'));
      expect(hit.length, dir.endsWith('soldier_idle') ? 19 : 7,
          reason: '🔴 $dir 必须在 AssetManifest 里（pubspec 目录声明漏一行'
              '就静默不进包）：实测 ${hit.length} 帧');
    }
    // 三位补零命名契约 + 单帧静态图（战士攻击 / 胜利 / 房子）。
    expect(assets, contains('assets/guard/monster_m2/frame001.webp'));
    expect(assets, contains('assets/guard/monster_m2/frame007.webp'));
    expect(assets, contains('assets/guard/monster_m3/frame001.webp'));
    expect(assets, contains('assets/guard/monster_m3/frame007.webp'));
    expect(assets, contains('assets/guard/soldier_attack.webp'));
    expect(assets, contains('assets/guard/soldier_win.webp'));
    expect(assets, contains('assets/guard/house.webp'));
  });
}
