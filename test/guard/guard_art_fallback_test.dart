/// 守卫战 v2 · **guard_art 占位兜底回归**（B5a · 设计验收判据①方向）。
///
/// ## 钉什么
/// `GuardArt` 的**每个素材位入口**在「素材缺失」分支必须返回 §3.4 约定的
/// 占位色块、且渲染零异常。本批（B5a）占位分支是**常驻分支**（零素材依赖，
/// B2~B4 的既有事实），本测试把「占位长什么样」逐位钉死。
///
/// ## B5b 换图后本测试自动升级为「删任一素材不 crash」护栏
/// 本文件在 `setUp` 里**拦截 `flutter/assets` 通道**（一律回 null = 资产不存在）：
///  · 现在：GuardArt 根本不加载资产 ⇒ 拦截零效果（纯占位分支断言）；
///  · B5b 换图后：每个素材位先走 `Image.asset` / `FrameSequencePlayer` ⇒
///    拦截命中 ⇒ **强制走进缺失分支** ⇒ 断言「返回占位色块、不 crash」。
///    等价于「删掉任一素材文件」的最坏情况，且不依赖文件系统动手脚。
///
/// ## 色约定真源
/// `guard_art.dart` 文件头 + 设计文档 §3.4（战士金 / m1 棕 / m2 绿 / m3 灰紫 /
/// 子弹亮黄圆点 / 底图奶油绿渐变 / 能量点两态）。🔴 B5b 换图删除占位分支时，
/// 若色约定调整，须同步改本文件 —— 它就是那条「低保真可玩」的红线。
library guard_art_fallback_test;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';

/// 素材宿主 key：占位断言的查找范围**只圈素材本体**。
/// 🔴 不能裸用 `find.byType(ColoredBox)` —— 测试宿主（MaterialApp+Scaffold）
/// 的 Material 背景自己就是一个 ColoredBox，会撞出「Too many elements」。
const Key _kArtHost = Key('guard_art_fallback_host');

/// 裸宿主 + **资产通道全拦截**（理由见文件头「B5b 换图后」段）。
Future<void> _pumpArt(WidgetTester tester, Widget art) async {
  tester.view.physicalSize = const Size(100, 100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // 拦截资产加载：回调返回 null = 「找不到该资产」⇒ 走 errorBuilder / 缺失分支。
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (ByteData? message) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 40,
            height: 40,
            key: _kArtHost,
            child: art,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  // 🔴 兜底第一判据：素材缺失分支绝不 crash（B5b 换图后的核心护栏）。
  expect(tester.takeException(), isNull, reason: '素材缺失兜底分支不得抛异常');
}

/// 读素材宿主后代里第一个 [ColoredBox] 的颜色（范围见 [_kArtHost] 注释）。
Color _coloredBoxColorOf(WidgetTester tester) {
  return tester.widget<ColoredBox>(
    find.descendant(of: find.byKey(_kArtHost), matching: find.byType(ColoredBox)),
  ).color;
}

/// 读素材宿主后代里第一个 [DecoratedBox] 的 BoxDecoration。
BoxDecoration _decorationOf(WidgetTester tester) {
  return tester.widget<DecoratedBox>(
    find.descendant(of: find.byKey(_kArtHost), matching: find.byType(DecoratedBox)),
  ).decoration as BoxDecoration;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('① 底图 sceneBackground：奶油绿渐变（上浅下深）', () {
    testWidgets('占位 = LinearGradient 两段奶油绿', (WidgetTester tester) async {
      await _pumpArt(tester, GuardArt.sceneBackground());
      final BoxDecoration d = _decorationOf(tester);
      final LinearGradient g = d.gradient! as LinearGradient;
      expect(g.begin, Alignment.topCenter);
      expect(g.end, Alignment.bottomCenter);
      expect(g.colors, const <Color>[Color(0xFFEAF4DF), Color(0xFFD7E8C8)],
          reason: '🔴 底图占位色必须与设计 §3.4 逐位一致');
    });
  });

  group('② 战士 soldier：金色块', () {
    testWidgets('占位 = ColoredBox 金色', (WidgetTester tester) async {
      await _pumpArt(tester, GuardArt.soldier());
      expect(_coloredBoxColorOf(tester), const Color(0xFFE8A600),
          reason: '🔴 战士 = 金色（§3.4）');
    });
  });

  group('③ 怪物 monsterWalk：m1 棕 / m2 绿 / m3 灰紫，帧号不影响占位色', () {
    testWidgets('三色逐位一致且互异；frameIndex 0/1 同色', (WidgetTester tester) async {
      final Map<String, Color> rendered = <String, Color>{};
      for (final GuardBattleMonsterKind kind in GuardBattleMonsterKind.values) {
        for (final int frame in <int>[0, 1]) {
          await _pumpArt(tester, GuardArt.monsterWalk(kind, frame));
          final Color c = _coloredBoxColorOf(tester);
          if (frame == 0) rendered[kind.id] = c;
          // 占位不区分离帧：序列帧参数在占位分支必须被忽略（B5b 才消费它）。
          expect(c, rendered[kind.id],
              reason: '${kind.id} 第 $frame 帧的占位色不得随帧漂移');
        }
      }
      expect(rendered['m1'], const Color(0xFF8D6E63), reason: 'm1 = 棕');
      expect(rendered['m2'], const Color(0xFF66BB6A), reason: 'm2 = 绿');
      expect(rendered['m3'], const Color(0xFF7E57C2), reason: 'm3 = 灰紫');
      expect(rendered.values.toSet().length, 3,
          reason: '🔴 三色必须两两可区分（B3 ⑦ 同口径）');
    });
  });

  group('④ 子弹 bullet：亮黄圆点', () {
    testWidgets('占位 = 圆形 DecoratedBox 亮黄', (WidgetTester tester) async {
      await _pumpArt(tester, GuardArt.bullet());
      final BoxDecoration d = _decorationOf(tester);
      expect(d.color, const Color(0xFFFFD54F), reason: '子弹 = 亮黄（§3.4）');
      expect(d.shape, BoxShape.circle);
    });
  });

  group('⑤ 开火钮 fireButton：金色圆形（常态单色；按下态属按钮体系不在此）', () {
    testWidgets('占位 = 圆形 DecoratedBox 金色', (WidgetTester tester) async {
      await _pumpArt(tester, GuardArt.fireButton());
      final BoxDecoration d = _decorationOf(tester);
      expect(d.color, const Color(0xFFE8A600), reason: '开火钮 = 战士金');
      expect(d.shape, BoxShape.circle);
    });
  });

  group('⑥ 能量点 energyDot：点亮金色实心金描边 / 未点亮透明灰描边', () {
    testWidgets('lit = 金色实心 + 0xFFB37400 描边', (WidgetTester tester) async {
      await _pumpArt(tester, GuardArt.energyDot(lit: true));
      final BoxDecoration d = _decorationOf(tester);
      expect(d.color, const Color(0xFFE8A600), reason: '点亮 = 金色实心');
      expect(d.shape, BoxShape.circle);
      expect(d.border, isNotNull);
      expect(d.border!.top.color, const Color(0xFFB37400));
      expect(d.border!.top.width, 1.5);
    });

    testWidgets('未点亮 = 透明 + 0xFFB9AE96 描边', (WidgetTester tester) async {
      await _pumpArt(tester, GuardArt.energyDot(lit: false));
      final BoxDecoration d = _decorationOf(tester);
      expect(d.color, const Color(0x00000000), reason: '未点亮 = 透明填充');
      expect(d.border!.top.color, const Color(0xFFB9AE96));
      expect(d.border!.top.width, 1.5);
    });
  });
}
