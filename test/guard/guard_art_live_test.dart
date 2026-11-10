/// 守卫战 v2 · **B5b 素材在位分支**（正分支护栏，与 guard_art_fallback_test 成对）。
///
/// ## 为什么独立成文件
/// `frame_sequence_player.loadFxManifest()` 的资产清单是**进程级缓存**——
/// 同 isolate 里若先跑「缺失分支」（拦截 `flutter/assets` 通道），空清单会被
/// 缓存、本文件的正分支永远拿不到帧。flutter test 每个文件独立 isolate ⇒
/// 本文件天然从干净缓存起跑（不能与 fallback 同文件混跑）。
///
/// ## 钉什么
/// 素材**在位**时：底图 / 战士待机 / m1 行走 / 攻击·胜利静态渲染**真 asset**，
/// asset 路径逐位钉死（= `guard_art.dart` 的 `_GuardAssetPaths` 契约）。
/// 占位回退与「删任一素材不 crash」护栏在 `guard_art_fallback_test.dart`。
library guard_art_live_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';

/// 素材宿主 key：断言范围只圈素材本体（宿主 Scaffold 自带 ColoredBox 会撞车）。
const Key _kArtHost = Key('guard_art_live_host');

/// 裸宿主 + 不拦截资产通道；推到 Image / FrameSequencePlayer 就绪为止。
Future<void> _pumpArtLive(WidgetTester tester, Widget art) async {
  tester.view.physicalSize = const Size(100, 100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
  // FutureBuilder 解析 AssetManifest + 帧解码：有界推进（循环帧常驻，禁止
  // pumpAndSettle）。🔴 就绪判据只认 Image / FrameSequencePlayer —— 等待期
  // 的占位 ColoredBox 不算（否则第一帧就「就绪」，帧序列永远测不到）。
  for (int i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    final bool ready = find
        .descendant(
          of: find.byKey(_kArtHost),
          matching: find.byWidgetPredicate(
              (Widget w) => w is Image || w is FrameSequencePlayer),
        )
        .evaluate()
        .isNotEmpty;
    if (ready) break;
  }
  expect(tester.takeException(), isNull, reason: '素材在位分支不得抛异常');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════
  // ⑦ B5b 素材在位分支（_pumpArtLive 不拦截）：真图 / 帧序列被渲染
  // ══════════════════════════════════════════════════════════════════════
  group('⑦ B5b 素材在位：底图/战士/m1 渲染真 asset（路径逐位钉死）', () {
    testWidgets('底图 = house.webp（Image.asset）', (WidgetTester tester) async {
      await _pumpArtLive(tester, GuardArt.sceneBackground());
      final Image img = tester.widget<Image>(
        find.descendant(of: find.byKey(_kArtHost), matching: find.byType(Image)),
      );
      final AssetImage asset = img.image as AssetImage;
      expect(asset.assetName, 'assets/guard/house.webp',
          reason: '🔴 L1 底图资产路径（浇水变体不接，见 guard_art 文件头）');
      expect(img.errorBuilder, isNotNull, reason: '缺失回退必须经 errorBuilder');
    });

    testWidgets('战士待机 = soldier_idle 帧序列循环（frame001 起始）',
        (WidgetTester tester) async {
      await _pumpArtLive(tester, GuardArt.soldier());
      final FrameSequencePlayer player = tester.widget<FrameSequencePlayer>(
        find.descendant(
            of: find.byKey(_kArtHost),
            matching: find.byType(FrameSequencePlayer)),
      );
      expect(player.loop, isTrue, reason: '待机 = 无限循环');
      expect(player.frames.first, 'assets/guard/soldier_idle/frame001.webp');
      expect(player.frames.last, 'assets/guard/soldier_idle/frame019.webp',
          reason: '19 帧待机动画（AssetManifest 实测，本断言钉当前交付）');
    });

    testWidgets('三种怪行走 = monster_m1/m2/m3 各自的 7 帧序列循环（B9/D2）',
        (WidgetTester tester) async {
      await _pumpArtLive(
          tester, GuardArt.monsterWalk(GuardBattleMonsterKind.m1, 0));
      final FrameSequencePlayer player = tester.widget<FrameSequencePlayer>(
        find.descendant(
            of: find.byKey(_kArtHost),
            matching: find.byType(FrameSequencePlayer)),
      );
      expect(player.loop, isTrue);
      expect(player.frames.first, 'assets/guard/monster_m1/frame001.webp');
      expect(player.frames.last, 'assets/guard/monster_m1/frame007.webp',
          reason: '7 帧进攻动画');

      // 🔴 B9/D2：m2（食叶虫）/ m3（贪婪鼬）已交付 ⇒ 三种怪都是**真实帧序列**，
      // 占位色块只留给「素材缺失」兜底（guard_art_fallback_test 覆盖）。
      await _pumpArtLive(
          tester, GuardArt.monsterWalk(GuardBattleMonsterKind.m2, 0));
      final FrameSequencePlayer m2 = tester.widget<FrameSequencePlayer>(
        find.descendant(
            of: find.byKey(_kArtHost),
            matching: find.byType(FrameSequencePlayer)),
      );
      expect(m2.frames.first, 'assets/guard/monster_m2/frame001.webp');
      expect(m2.frames.last, 'assets/guard/monster_m2/frame007.webp',
          reason: '食叶虫 7 帧进攻动画');
      expect(m2.frames, hasLength(7));

      await _pumpArtLive(
          tester, GuardArt.monsterWalk(GuardBattleMonsterKind.m3, 0));
      final FrameSequencePlayer m3 = tester.widget<FrameSequencePlayer>(
        find.descendant(
            of: find.byKey(_kArtHost),
            matching: find.byType(FrameSequencePlayer)),
      );
      expect(m3.frames.first, 'assets/guard/monster_m3/frame001.webp');
      expect(m3.frames.last, 'assets/guard/monster_m3/frame007.webp',
          reason: '贪婪鼬 7 帧进攻动画');
      expect(m3.frames, hasLength(7));
      // 四种素材互不串线（m1/m2/m3 各挂各的目录）。
      expect(player.frames.first.contains('monster_m1'), isTrue);
      expect(m2.frames.first.contains('monster_m2'), isTrue);
      expect(m3.frames.first.contains('monster_m3'), isTrue);
    });

    testWidgets('战士攻击 / 胜利静态 = 对应 asset（Image.asset）',
        (WidgetTester tester) async {
      await _pumpArtLive(tester, GuardArt.soldierAttack());
      expect(
        tester
            .widget<Image>(find.descendant(
              of: find.byKey(_kArtHost),
              matching: find.byType(Image),
            ))
            .image,
        const AssetImage('assets/guard/soldier_attack.webp'),
      );
      await _pumpArtLive(tester, GuardArt.soldierWin());
      expect(
        tester
            .widget<Image>(find.descendant(
              of: find.byKey(_kArtHost),
              matching: find.byType(Image),
            ))
            .image,
        const AssetImage('assets/guard/soldier_win.webp'),
      );
    });
  });
}