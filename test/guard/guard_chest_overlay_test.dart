/// 花园守卫 · **开箱动画**（30 帧 / 5s）的帧序与接缝护栏（Guard-B13.11 / T03）。
///
/// 真源：设计 §7.5（开箱 5s / 166.7ms 每帧 / 同时起音效）与 §9.3（测试纪律）。
///
/// ## 覆盖
/// | # | 断言 | 用例 |
/// |---|---|---|
/// | ① | 帧列表 = AssetManifest 实测的 `chest_{tier}/frame001..030.webp`（30 帧、升序） | A |
/// | ② | 静态展示帧 = `frame001.webp`（点击切入动画零跳变） | A |
/// | ③ | 每 166.7ms 前进 **1 帧**（6fps 摊 5s），末帧 = frame030 并停住 | B |
/// | ④ | 5s 整点回调 `onOpened`（早 1ms 不回调） | B |
/// | ⑤ | `showGuardChestOverlay` 把 `playSfx` 接缝透传下去（音量 0.5 一字不改） | C |
///
/// ## 🔴 绝不 `pumpAndSettle()`
/// idle 期的呼吸动画是**无限**的、另有 8s `Timer` —— 全部定长 `pump(Duration)`。
library guard_chest_overlay_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/audio_service.dart' show AudioCue;
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_chest_stage.dart';

final AppLocalizations _zh = AppLocalizationsZh();

/// 一条 166.7ms 的帧间隔（字面量：30 帧摊 5000ms ⇒ 每帧 166.7ms）。
const Duration _frameStep = Duration(microseconds: 166700);

/// 读当前渲染的帧路径（播放器内部是 `Image.asset`，从 `AssetImage` 反查）。
String? _currentFrame(WidgetTester tester) {
  final Finder images = find.descendant(
    of: find.byKey(GuardChestStage.openPlayerKey),
    matching: find.byType(Image),
  );
  if (images.evaluate().isEmpty) return null;
  final Image image = tester.widget<Image>(images.first);
  final ImageProvider<Object> provider = image.image;
  return provider is AssetImage ? provider.assetName : null;
}

/// 把宝箱演出层挂起来，并在「落地静止」后点击开箱。
Future<List<String>> _openChest(
  WidgetTester tester, {
  GuardChestTier tier = GuardChestTier.normal,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GuardChestStage(
          tier: tier,
          l10n: _zh,
          // 自动开必须关掉：否则 8s 会和「逐帧推进」抢时间轴。
          autoOpen: false,
          playSfx: (AudioCue cue, {double volume = 1.0}) {},
          onOpened: () {},
        ),
      ),
    ),
  );
  await tester.pump();
  final List<String> frames = await GuardArt.chestFrames(tier);
  // 落地（600ms）+ 一帧余量让状态回调派发。
  await tester.pump(const Duration(milliseconds: kGuardChestDropMs));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(const Offset(10, 10));
  await tester.pump();
  return frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① 帧列表来源 ─────────────────────────────────────────────────────
  group('① 帧列表：AssetManifest 实测两档各 30 帧、升序、命名连续', () {
    for (final GuardChestTier tier in GuardChestTier.values) {
      test('${tier.id} ⇒ 30 张 frame001..030.webp（升序）', () async {
        final List<String> frames = await GuardArt.chestFrames(tier);
        final String dir = GuardArt.chestDirOf(tier);
        expect(frames.length, 30,
            reason: '${tier.id} 帧数必须是 30（素材契约 A-01）');
        expect(frames.first, '$dir/frame001.webp');
        expect(frames.last, '$dir/frame030.webp');
        // 升序 = 播放顺序（`resolveFxFrames` 排序后返回）。
        final List<String> sorted = List<String>.of(frames)..sort();
        expect(frames, sorted, reason: '帧列表必须升序，否则开箱会倒放');
        expect(frames.toSet().length, 30, reason: '不许有重复帧');
      });
    }

    test('两档目录不同（高级宝箱不是普通档的马甲）', () {
      expect(GuardArt.chestDirOf(GuardChestTier.normal),
          'assets/guard/chest_normal');
      expect(GuardArt.chestDirOf(GuardChestTier.premium),
          'assets/guard/chest_premium');
    });
  });

  // ── ② 静态展示帧 ─────────────────────────────────────────────────────
  group('② 静态展示帧 = frame001（点击切入动画零跳变）', () {
    test('chestStillPath 恒指向本档 frame001.webp', () {
      expect(GuardArt.chestStillPath(GuardChestTier.normal),
          'assets/guard/chest_normal/frame001.webp');
      expect(GuardArt.chestStillPath(GuardChestTier.premium),
          'assets/guard/chest_premium/frame001.webp');
    });

    test('落定期渲染的就是 frame001（静态图读它）', () async {
      final List<String> frames =
          await GuardArt.chestFrames(GuardChestTier.normal);
      expect(GuardArt.chestStillPath(GuardChestTier.normal), frames.first,
          reason: '静图必须 == 动画首帧，否则点开瞬间会「跳一下」');
    });
  });

  // ── ③ 帧序推进 + ④ 播完回调 ──────────────────────────────────────────
  group('③ 166.7ms/帧推进；④ 5000ms 整点回调', () {
    testWidgets('开箱首帧 = frame001，每 166.7ms 前进一帧，末帧停在 frame030',
        (WidgetTester tester) async {
      final List<String> frames = await _openChest(tester);

      // 起播首帧（播放器挂载后第一帧必然是 index 0）。
      expect(find.byKey(GuardChestStage.openPlayerKey), findsOneWidget,
          reason: '点开后必须挂上开箱播放器');
      expect(_currentFrame(tester), frames.first,
          reason: '开箱第一帧必须是 frame001（与静态展示帧同一张）');

      // 逐帧推进：每一步恰好前进 1 张（6fps 的铁证）。
      for (int i = 1; i <= 5; i++) {
        await tester.pump(_frameStep);
        expect(_currentFrame(tester), frames[i],
            reason: '第 $i 个 166.7ms 后应播到 ${frames[i]}（30 帧摊 5000ms）');
      }

      // 推到 30 帧尾巴（还剩 24 帧 = 24 × 166.7ms ≈ 4001ms）。
      await tester.pump(_frameStep * 24);
      expect(_currentFrame(tester), frames.last,
          reason: '5000ms 时必须是末帧 frame030');
      // `holdLastFrame: true` ⇒ 停住不渐隐、不消失（结算卡还没弹出来）。
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentFrame(tester), frames.last,
          reason: '播完必须停在末帧直到结算卡出现（不许露出一帧空花园）');
    });

    testWidgets('onOpened 在 5000ms 到点才回调（4999ms 不回调、只回调一次）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      int opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuardChestStage(
              tier: GuardChestTier.premium,
              l10n: _zh,
              autoOpen: false,
              playSfx: (AudioCue cue, {double volume = 1.0}) {},
              onOpened: () => opened++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: kGuardChestDropMs));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 4999));
      expect(opened, 0, reason: '4999ms 时 5s 还没到，不得回调');
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      expect(opened, 1, reason: '🔴 5000ms 到点必须回调一次');
      await tester.pump(const Duration(milliseconds: 2000));
      expect(opened, 1, reason: '播完不再重复回调');
    });
  });

  // ── ⑤ overlay 透传音效接缝 ───────────────────────────────────────────
  group('⑤ showGuardChestOverlay 透传 playSfx（落地 0.5 + 开箱 0.5，B13.13 音量统一）', () {
    testWidgets('经 overlay 打开时，先落地音效 0.5、点开后开箱音效 0.5', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final List<double> volumes = <double>[];
      final List<AudioCue> cues = <AudioCue>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: TextButton(
                  onPressed: () => showGuardChestOverlay(
                    context,
                    tier: GuardChestTier.normal,
                    l10n: _zh,
                    playSfx: (AudioCue cue, {double volume = 1.0}) {
                      cues.add(cue);
                      volumes.add(volume);
                    },
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: kGuardChestDropMs));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      // 2026-11-12 起宝箱有**落地音效**：fall 段结束（240ms）画面砸地那一帧播
      // guardChestLand；点击后再播开箱 guardChestOpen。B13.13 起两音效统一
      // 音量 0.5（玄参裁定落地音 1.0 真机听感偏大）。期望值写字面量（K26~K28）。
      expect(cues, <AudioCue>[AudioCue.guardChestLand, AudioCue.guardChestOpen],
          reason: 'cue 序列必须是「落地 → 开箱」按序两条');
      expect(volumes, <double>[0.5, 0.5],
          reason: '落地音效 0.5（B13.13 裁定）；开箱音效 0.5（Q-04 已裁定）');
      await tester.pump(const Duration(milliseconds: kGuardChestOpenMs));
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
