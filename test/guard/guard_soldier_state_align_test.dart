/// 守卫战 v2 · **B11/C4 战士三态「身体质心对齐」**（玄参第六轮）。
///
/// ## 玄参原话
/// 「攻击的时候人往左挪了一点」—— 一开火角色整个人向左跳一小步，300ms 后再跳回来。
///
/// ## 根因（不是定位公式算错，是**素材配准差**）
/// 战士三态（待机 19 帧 / 攻击 / 胜利）是**各自裁到自己的实体框**的：
///
/// | 状态 | 裁边后画布 | 宽高比 | 实体框里多了什么 |
/// |---|---|---|---|
/// | idle | 362×372 | 0.973 | — |
/// | attack | 512×349 | 1.467 | **挥出去的兵器**（比待机宽 41%） |
/// | win | 512×429 | 1.193 | 举手庆祝的手臂 |
///
/// `BoxFit.fitHeight` 再把这张图**居中**放进绘制框（113.33 宽）时，
/// 身体坐标 = `框中心 + (fx − 0.5) × 绘制宽`，而 `fx`（alpha 加权质心占画布宽的
/// 比例）三态各不相同 —— 实测量得 **0.5559 / 0.4400 / 0.4660**：
///
/// * idle 身体偏右 **+3.70pt**
/// * attack 身体偏左 **−5.99pt**
/// * win 身体偏左 **−2.76pt**
/// ⇒ 攻击帧相对待机 **左移 9.69pt**（= 玄参看到的「往左挪了一点」）。
///
/// 居中永远对不齐：**身体在两幅画布里的位置本来就不同**。治法 = 按**质心**对齐
/// （`GuardCardLayout.soldierStateAlignShiftX`，常量表 `kGuardSoldierStateCentroidX`）。
///
/// ## 本文件钉什么（🔴 旧实现「实体框居中」下 ② 必红）
/// | # | 断言 |
/// |---|---|
/// | ① | 常量表 == 本文件**独立重算**的质心（Dart 侧再实现一遍 alpha 加权，±0.005） |
/// | ② | 🔴 三态**渲染后**的质心 x 互相差 ≤ **1.0pt**，且都落在绘制框中轴 ±1.0 |
/// | ③ | 待机**渲染高度仍是 68.0**（玄参「68 刚好」⇒ 改定位不许把身体改小） |
/// | ④ | 三态位移量写死（−3.70 / +5.99 / +2.76，±0.05） |
/// | ⑤ | 素材画布尺寸与常量表绑定（**换图必红**，见文件尾的换素材流程） |
///
/// ## 🔴 换素材流程（改名 / 重导 / 重裁都要走一遍）
/// 1. 重跑 `python3 tools/measure_soldier_centroid.py`；
/// 2. 更新 `kGuardSoldierStateCentroidX`（`prd_params.dart`）与
///    `kGuardSoldierStateAspectRatios`；
/// 3. 重跑本文件 —— ①⑤ 会告诉你常量有没有过期。
library guard_soldier_state_align_test;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show kGuardSoldierStateAspectRatios, kGuardSoldierStateCentroidX;
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';

/// 素材宿主（断言范围只圈战士本体）。
const Key _kHost = Key('soldier_align_host');

/// 390 卡的几何（scale 1.0）。
const GuardCardLayout _layout = GuardCardLayout(390);

/// alpha 判定阈值（与 `tools/measure_soldier_centroid.py` /
/// `tools/convert_guard_b5b.py` 同口径）。
const int _alphaThreshold = 128;

/// 三态各自的**素材路径**（idle 用帧序列，见 [idleFramesAssetPaths]）。
const Map<String, String> _assetOf = <String, String>{
  'attack': 'assets/guard/soldier_attack.webp',
  'win': 'assets/guard/soldier_win.webp',
};

/// 一次「alpha 加权质心」的测量结果（像素版 + 归一化版）。
class _Centroid {
  const _Centroid({required this.imageWidth, required this.imageHeight, required this.cxPx});

  final int imageWidth;
  final int imageHeight;
  final double cxPx;

  /// 归一化质心（0 = 画布左缘、1 = 右缘）。
  double get fx => cxPx / imageWidth;
}

/// 读一张素材的 alpha 加权质心 x（`Σ(x·α)/Σα`，x 取像素中心）。
///
/// 🔴 与 `tools/measure_soldier_centroid.py` **各自独立实现**：两处算出的数一致，
/// 才说明常量表既不是手写的、也没有随素材漂移。
Future<_Centroid> _measureAsset(String asset) async {
  final ByteData data = await rootBundle.load(asset);
  final ui.Codec codec =
      await ui.instantiateImageCodec(data.buffer.asUint8List());
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final ByteData? raw =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(raw, isNotNull, reason: '素材必须能读像素：$asset');
  final Uint8List bytes = raw!.buffer.asUint8List();
  final int w = image.width;
  final int h = image.height;

  double weighted = 0;
  double mass = 0;
  for (int y = 0; y < h; y++) {
    final int rowStart = y * w * 4;
    for (int x = 0; x < w; x++) {
      final int a = bytes[rowStart + x * 4 + 3];
      if (a <= _alphaThreshold) continue;
      mass += a;
      weighted += (x + 0.5) * a;
    }
  }
  expect(mass, greaterThan(0), reason: '空图（alpha 全 ≤ $_alphaThreshold）：$asset');
  image.dispose();
  return _Centroid(imageWidth: w, imageHeight: h, cxPx: weighted / mass);
}

/// 待机帧的 asset 路径（由播放器实测给出，帧数不写死）。
List<String> _idleFrames(WidgetTester tester) {
  final FrameSequencePlayer player = tester.widget<FrameSequencePlayer>(
    find.descendant(of: find.byKey(_kHost), matching: find.byType(FrameSequencePlayer)),
  );
  return player.frames;
}

/// 挂一只战士（[attack] / [win] 二选一切静态帧；都不传 = 待机帧序列）。
Future<void> _pumpSoldier(
  WidgetTester tester, {
  bool attack = false,
  bool win = false,
}) async {
  tester.view.physicalSize = const Size(390, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _layout.soldierDrawWidth,
            height: GuardCardLayout.soldierHeight,
            key: _kHost,
            // 待机必须 `animate: true`（帧序列的 frames 列表才完整 —— 19 帧；
            // `animate: false` 只把首帧交给播放器，量不到「19 帧平均」）。
            child: GuardArt.soldier(attack: attack, win: win),
          ),
        ),
      ),
    ),
  );
  // AssetManifest 解析 + 首帧解码：有界推进（循环帧常驻，禁止 pumpAndSettle）。
  for (int i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    final bool ready = find
        .descendant(
          of: find.byKey(_kHost),
          matching: find.byWidgetPredicate(
              (Widget w) => w is Image || w is FrameSequencePlayer),
        )
        .evaluate()
        .isNotEmpty;
    if (ready) break;
  }
  expect(tester.takeException(), isNull);
}

/// 某一状态层的**真实位移**（读树里那个 `Transform`，不是按公式重算）。
double _shiftOf(WidgetTester tester, String state) {
  final Transform tf =
      tester.widget<Transform>(find.byKey(GuardArt.centroidAlignKey(state)));
  return tf.transform.getTranslation().x;
}

/// 三态「渲染后的实际质心 x」（卡内坐标系）。
///
/// 推导链（每一步都可用测试里量到的量复核）：
/// `BoxFit.fitHeight` ⇒ 绘制高 = 框高、绘制宽 = 框高 × 素材宽高比；
/// 默认 `alignment: center` ⇒ 绘制左缘 = `框左 + (框宽 − 绘制宽) / 2`；
/// 再叠加该状态层的配准位移（从树上读）；身体质心 = 绘制左缘 + `fx × 绘制宽`。
double _renderedCx({
  required Rect box,
  required _Centroid asset,
  required double shiftPx,
  required double fx,
}) {
  final double paintHeight = box.height;
  final double paintWidth = paintHeight * asset.imageWidth / asset.imageHeight;
  final double paintLeft = box.left + (box.width - paintWidth) / 2 + shiftPx;
  return paintLeft + fx * paintWidth;
}

String _f(double v) => v.toStringAsFixed(2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('① 常量表 == 独立重算的 alpha 加权质心（换图必红）', () {
    testWidgets('idle（19 帧平均）/ attack / win 三态', (WidgetTester tester) async {
      await _pumpSoldier(tester);

      await tester.runAsync(() async {
        final List<String> frames = _idleFrames(tester);
        expect(frames.length, greaterThan(1), reason: '待机必须是多帧序列');

        double sumFx = 0;
        for (final String frame in frames) {
          final _Centroid c = await _measureAsset(frame);
          expect(c.imageWidth, 362, reason: '待机帧画布宽（换图必红）');
          expect(c.imageHeight, 372, reason: '待机帧画布高（换图必红）');
          sumFx += c.fx;
        }
        final double idleFx = sumFx / frames.length;

        final _Centroid attack = await _measureAsset(_assetOf['attack']!);
        final _Centroid win = await _measureAsset(_assetOf['win']!);

        // 🔴 常量表必须与实测一致（±0.005 = 画布宽的 0.5%，肉眼不可辨）。
        expect(idleFx, closeTo(kGuardSoldierStateCentroidX['idle']!, 0.005),
            reason: '🔴 idle 常量过期？实测 ${idleFx.toStringAsFixed(4)} vs 常量 '
                '${kGuardSoldierStateCentroidX['idle']}（重跑 measure_soldier_centroid.py）');
        expect(attack.fx, closeTo(kGuardSoldierStateCentroidX['attack']!, 0.005),
            reason: '🔴 attack 常量过期？实测 ${attack.fx.toStringAsFixed(4)}');
        expect(win.fx, closeTo(kGuardSoldierStateCentroidX['win']!, 0.005),
            reason: '🔴 win 常量过期？实测 ${win.fx.toStringAsFixed(4)}');

        // 三态质心**在各自画布里的位置确实不同**（居中必然错位的根因，钉住它）。
        expect((attack.fx - idleFx).abs(), greaterThan(0.05),
            reason: '🔴 三态质心差异必须 > 5% 画布宽（否则「居中」就够了，说明素材被重导）');
      });
    });
  });

  group('② 三态渲染质心对齐（🔴 旧实现「实体框居中」必红）', () {
    testWidgets('|cx_idle − cx_attack| ≤ 1.0pt、|cx_idle − cx_win| ≤ 1.0pt',
        (WidgetTester tester) async {
      await _pumpSoldier(tester);
      await tester.runAsync(() async {
        final List<String> frames = _idleFrames(tester);

        // ── 待机（在树里量位移 + 独立重算质心）────────────────────────
        final Rect idleBox = tester.getRect(find.byKey(_kHost));
        final double idleShift = _shiftOf(tester, 'idle');
        double sumFx = 0;
        _Centroid? firstFrame;
        for (final String frame in frames) {
          final _Centroid c = await _measureAsset(frame);
          firstFrame ??= c;
          sumFx += c.fx;
        }
        final double idleFx = sumFx / frames.length;
        final double cxIdle = _renderedCx(
          box: idleBox,
          asset: firstFrame!,
          shiftPx: idleShift,
          fx: idleFx,
        );

        // ── 攻击 ──────────────────────────────────────────────────────
        await _pumpSoldier(tester, attack: true);
        final Rect attackBox = tester.getRect(find.byKey(_kHost));
        final double attackShift = _shiftOf(tester, 'attack');
        final _Centroid attack = await _measureAsset(_assetOf['attack']!);
        final double cxAttack = _renderedCx(
          box: attackBox,
          asset: attack,
          shiftPx: attackShift,
          fx: attack.fx,
        );

        // ── 胜利 ──────────────────────────────────────────────────────
        await _pumpSoldier(tester, win: true);
        final Rect winBox = tester.getRect(find.byKey(_kHost));
        final double winShift = _shiftOf(tester, 'win');
        final _Centroid win = await _measureAsset(_assetOf['win']!);
        final double cxWin = _renderedCx(
          box: winBox,
          asset: win,
          shiftPx: winShift,
          fx: win.fx,
        );

        // 交付报告要的三个质心实测值（原始画布 px + 渲染后 pt）。
        // ignore: avoid_print
        print('── B11/C4 战士三态质心 ────────────────────────────────');
        // ignore: avoid_print
        print('idle   : fx=${idleFx.toStringAsFixed(4)}  cx_px=${_f(idleFx * firstFrame.imageWidth)}'
            '  shift=${_f(idleShift)}  cx_rendered=${_f(cxIdle)}');
        // ignore: avoid_print
        print('attack : fx=${attack.fx.toStringAsFixed(4)}  cx_px=${_f(attack.cxPx)}'
            '  shift=${_f(attackShift)}  cx_rendered=${_f(cxAttack)}');
        // ignore: avoid_print
        print('win    : fx=${win.fx.toStringAsFixed(4)}  cx_px=${_f(win.cxPx)}'
            '  shift=${_f(winShift)}  cx_rendered=${_f(cxWin)}');
        // ignore: avoid_print
        print('框中心 = ${_f(idleBox.center.dx)}（= soldierRect.center.dx）');
        // ignore: avoid_print
        print('──────────────────────────────────────────────────────');

        // 🔴 核心：三态身体必须共线（±1.0pt）。
        expect((cxIdle - cxAttack).abs(), lessThanOrEqualTo(1.0),
            reason: '🔴 攻击帧身体比待机偏 ${_f(cxAttack - cxIdle)}pt（玄参看到的「往左挪」）');
        expect((cxIdle - cxWin).abs(), lessThanOrEqualTo(1.0),
            reason: '🔴 胜利帧身体比待机偏 ${_f(cxWin - cxIdle)}pt');

        // 且三者都落在绘制框中轴（= 战士布局框中心）±1.0。
        for (final MapEntry<String, double> e
            in <String, double>{'idle': cxIdle, 'attack': cxAttack, 'win': cxWin}
                .entries) {
          expect(e.value, closeTo(idleBox.center.dx, 1.0),
              reason: '🔴 ${e.key} 的身体质心必须落在战士中轴上');
        }
      });
    });
  });

  group('③ 待机渲染高度仍是 68（改定位不许把身体改小）', () {
    testWidgets('绘制高 68、绘制宽 66.17（fitHeight 保持素材比例）',
        (WidgetTester tester) async {
      await _pumpSoldier(tester);
      final Rect host = tester.getRect(find.byKey(_kHost));
      expect(host.height, closeTo(68, 0.5),
          reason: '🔴 B10/C1 的 68 是玄参认可的尺寸，本轮不许动');
      expect(host.width, closeTo(113.33, 0.5), reason: '绘制框宽 = 68 × 5/3');

      final Size player = tester.getSize(find.descendant(
        of: find.byKey(_kHost),
        matching: find.byType(FrameSequencePlayer),
      ));
      // 🔴 播放器铺满绘制框（113.33 × 68）；`BoxFit.fitHeight` 决定**画面**高度
      // 就是框高（绘制宽由素材比例派生，见下一个纯值类用例）。
      expect(player.height, closeTo(68, 0.5),
          reason: '🔴 fitHeight ⇒ 画面高度 == 框高 == 68（待机身体视觉高不变）');
      expect(player.width, closeTo(113.33, 0.5),
          reason: '播放器铺满绘制框（画面宽 66.17 居中落在框内）');
    });

    test('纯值类：三态绘制宽 = 68 × 素材比例', () {
      expect(GuardCardLayout.soldierStatePaintWidth('idle', 68),
          closeTo(66.17, 0.01));
      expect(GuardCardLayout.soldierStatePaintWidth('attack', 68),
          closeTo(99.76, 0.01));
      expect(GuardCardLayout.soldierStatePaintWidth('win', 68),
          closeTo(81.16, 0.01));
      // 攻击帧 99.76 必须仍落在绘制框 113.33 内（含 +5.99 的配准位移）。
      expect(GuardCardLayout.soldierStatePaintWidth('attack', 68) + 5.99,
          lessThan(GuardCardLayout.soldierOverflowWidth));
    });
  });

  group('④ 三态位移量写死（负 = 向左）', () {
    testWidgets('idle −3.70 / attack +5.99 / win +2.76（±0.05）',
        (WidgetTester tester) async {
      await _pumpSoldier(tester);
      expect(_shiftOf(tester, 'idle'), closeTo(-3.70, 0.05),
          reason: '🔴 idle 质心在 0.5559 ⇒ 身体偏右 3.70，往左拉回');

      await _pumpSoldier(tester, attack: true);
      expect(_shiftOf(tester, 'attack'), closeTo(5.99, 0.05),
          reason: '🔴 attack 质心 0.4400 ⇒ 身体偏左 5.99，往右推');

      await _pumpSoldier(tester, win: true);
      expect(_shiftOf(tester, 'win'), closeTo(2.76, 0.05),
          reason: '🔴 win 质心 0.4660 ⇒ 身体偏左 2.76');
    });

    test('纯值类：位移 = −(fx − 0.5) × 绘制宽', () {
      for (final String state in <String>['idle', 'attack', 'win']) {
        final double paintW = GuardCardLayout.soldierStatePaintWidth(state, 68);
        final double expected =
            -(kGuardSoldierStateCentroidX[state]! - 0.5) * paintW;
        expect(GuardCardLayout.soldierStateAlignShiftX(state, 68),
            closeTo(expected, 1e-9));
        // 修正前（实体框居中）身体偏移量 = +(fx − 0.5) × 绘制宽 ⇒ 与本值反号。
        expect(GuardCardLayout.soldierStateAlignShiftX(state, 68),
            closeTo(-(kGuardSoldierStateCentroidX[state]! - 0.5) * paintW, 1e-9));
      }
      // 修正前（实体框居中）三态身体相对框中轴的位置 = +(fx − 0.5) × 绘制宽；
      // 攻击帧相对待机的错位量 = 两者之差 = **−9.68pt**（玄参看到的「往左挪」）。
      final double beforeIdle =
          (kGuardSoldierStateCentroidX['idle']! - 0.5) *
              GuardCardLayout.soldierStatePaintWidth('idle', 68);
      final double beforeAttack =
          (kGuardSoldierStateCentroidX['attack']! - 0.5) *
              GuardCardLayout.soldierStatePaintWidth('attack', 68);
      expect(beforeIdle, closeTo(3.70, 0.05),
          reason: '修正前 idle 身体偏右 3.70pt');
      expect(beforeAttack, closeTo(-5.99, 0.05),
          reason: '修正前 attack 身体偏左 5.99pt');
      expect((beforeAttack - beforeIdle).abs(), closeTo(9.68, 0.05),
          reason: '🔴 修正前 attack 相对 idle 的错位量 = 9.68pt（B10 实现的偏差）');
    });
  });

  group('⑤ 素材画布尺寸 ↔ 常量表绑定（换图必红）', () {
    testWidgets('三态画布 362×372 / 512×349 / 512×429，宽高比与常量表一致',
        (WidgetTester tester) async {
      await _pumpSoldier(tester);
      await tester.runAsync(() async {
        final _Centroid idle = await _measureAsset(_idleFrames(tester).first);
        expect(idle.imageWidth, 362);
        expect(idle.imageHeight, 372);
        expect(kGuardSoldierStateAspectRatios['idle'],
            closeTo(idle.imageWidth / idle.imageHeight, 1e-3));

        final _Centroid attack = await _measureAsset(_assetOf['attack']!);
        expect(attack.imageWidth, 512, reason: '攻击帧画布宽');
        expect(attack.imageHeight, 349, reason: '攻击帧画布高');
        expect(kGuardSoldierStateAspectRatios['attack'],
            closeTo(attack.imageWidth / attack.imageHeight, 1e-3));

        final _Centroid win = await _measureAsset(_assetOf['win']!);
        expect(win.imageWidth, 512);
        expect(win.imageHeight, 429);
        expect(kGuardSoldierStateAspectRatios['win'],
            closeTo(win.imageWidth / win.imageHeight, 1e-3));
      });
    });
  });
}
