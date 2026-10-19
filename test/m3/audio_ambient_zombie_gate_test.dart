/// F133 氛围音「加载卡死 → 起播闸门永久关死」单测（玄参 2026-10-19 iPad 13 真机）。
///
/// 真机症状：iPad 13 上花园页**所有声音全哑**（背景音 + 浇水/施肥/除草/收集），
/// iPad 11 / iPhone 17 正常，杀 App 重开短暂恢复。
///
/// 真机日志锁定的机制（`simctl log` 按时序）：
/// ```
/// 19:06:58.333 [ambientStart] attempt #1: stop→setAsset→seek→setVolume→play
/// 19:06:58.344 [ambientState] playing=false processingState=loading      ← 一直停在这
/// 19:06:59.320 [stopGardenAmbient] reason=leave | gen 0→1 playing(before)=true
/// 19:07:00.505 [_playGardenAmbient] skip: _ambientStarting（已有起播流程在跑，勿并发）
///             ……此后每 30s 一条，直到杀 App
/// ```
/// 即：`setAsset` 的 Future 在「加载途中被 `stop()` 打断」时**既不完成也不抛错**，
/// `await` 永不返回 → 起播协程卡在 `try` 内 → `finally` 不执行 → 闸门永久 `true`。
///
/// 本文件覆盖两条兜底：
///  ① [AudioService.loadAssetBounded]：把「永不返回」变成「有界失败」（超时 → 丢弃播放器重建）；
///  ② 僵尸闸门：闸门持有超过 [kAmbientStartGateStuckMs] → 强制复位并作废在途流程。
///
/// ⚠️ headless 无音频后端（`playerFactory: () => null`），真机独有的「平台永不返回」
/// 用**永不完成的 Future** 等价复现——这正是本缺陷的本质，不依赖真机。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart' as ft;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/platform/audio_service.dart';

void main() {
  ft.TestWidgetsFlutterBinding.ensureInitialized();

  ft.group('F133 ① · loadAssetBounded 把「永不返回」变成有界失败', () {
    ft.test('加载永不完成 → 超时返回 false（闸门不再永久卡死）', () async {
      final Completer<void> never = Completer<void>(); // 模拟「被打断的 setAsset」
      final Stopwatch sw = Stopwatch()..start();
      final bool ok = await AudioService.loadAssetBounded(
        () => never.future,
        timeoutMs: 50,
      );
      sw.stop();
      ft.expect(ok, ft.isFalse, reason: '超时 = 本次失败，调用方须丢弃播放器');
      ft.expect(sw.elapsedMilliseconds, ft.lessThan(5000),
          reason: '必须**有界**返回——这正是原缺陷「永不返回」的反面');
    });

    ft.test('加载正常完成 → 返回 true（不引入任何延迟）', () async {
      final bool ok = await AudioService.loadAssetBounded(
        () async {},
        timeoutMs: 2000,
      );
      ft.expect(ok, ft.isTrue);
    });

    ft.test('加载抛错 → 异常照旧向上抛（交给 startAmbientWithRetries 重试）', () async {
      // 语义区分：**超时**→ 返回 false（丢弃播放器）；**抛错**→ 原样上抛（走既有重试）。
      await ft.expectLater(
        () => AudioService.loadAssetBounded(
          () async => throw StateError('AudioFileStream -11849'),
          timeoutMs: 2000,
        ),
        ft.throwsA(ft.isA<StateError>()),
      );
    });
  });

  ft.group('F133 ② · 起播闸门僵尸兜底', () {
    ft.test('闸门被持有超过上限 → 强制复位并继续起播（代际 +1 作废在途流程）', () async {
      final AudioService svc = AudioService(playerFactory: () => null);
      svc.applySettings(soundOn: true, bgmOn: true);

      // 伪造「上一个起播流程卡死、闸门已持有 30s」的真机终态。
      svc.debugSetAmbientGateStuck(ago: const Duration(seconds: 30));
      final int genBefore = svc.ambientGeneration;

      await svc.playGardenAmbientAndWait();

      ft.expect(svc.ambientGeneration, genBefore + 1,
          reason: '僵尸复位必须递增代际（否则僵死的在途流程会与新流程抢同一个播放器）');
      ft.expect(svc.ambientShouldPlay, ft.isTrue,
          reason: '僵尸体复位不得清「应播」意图——用户仍要听背景音');
    });

    ft.test('闸门未超过上限 → 仍然 skip，绝不并发起播', () async {
      final AudioService svc = AudioService(playerFactory: () => null);
      svc.applySettings(soundOn: true, bgmOn: true);

      // 仅持有 1s = 正常起播窗口（真机正常加载 30~80ms），必须挡住而不是抢占。
      svc.debugSetAmbientGateStuck(ago: const Duration(seconds: 1));
      final int genBefore = svc.ambientGeneration;

      await svc.playGardenAmbientAndWait();

      ft.expect(svc.ambientGeneration, genBefore,
          reason: '未越界 → 走 skip 分支，不得复位、不得递增代际');
    });
  });

  ft.group('F133 ③ · 常量余量守卫', () {
    ft.test('单次起播最坏耗时 < 僵尸门上限（调参不得让兜底误伤正常重试）', () {
      // 最坏情况 = 全部尝试都耗尽 setAsset 超时 + 各次重试间隔。
      const int worstMs = kAmbientStartAttempts * kAmbientSetAssetTimeoutMs +
          (kAmbientStartAttempts - 1) * kAmbientRetryDelayMs;
      ft.expect(worstMs, ft.lessThan(kAmbientStartGateStuckMs),
          reason: '若调大超时/尝试次数到越界，僵尸门会在正常重试途中误判并强制复位；'
              '调参时必须同步调大 kAmbientStartGateStuckMs（当前余量 '
              '${kAmbientStartGateStuckMs - worstMs}ms）');
    });
  });
}
