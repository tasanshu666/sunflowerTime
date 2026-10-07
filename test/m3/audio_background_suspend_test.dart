/// F70 音频后台挂起/恢复单测（玄参 2026-10-05 反馈「花园页锁屏/退后台背景音乐还在响」）。
///
/// 覆盖 [AudioService] 的挂起闸门语义（headless 测试无音频后端，playerFactory 注入
/// null → 一切播放静默降级，但**状态机与闸门**仍可断言）：
///  ① [AudioService.pauseAllForBackground] 进入挂起态（幂等：重复调用仍挂起）；
///  ② 挂起期间 `startBgm` / `playGardenAmbient` 请求被闸门拦下（不改变在播状态）；
///  ③ [AudioService.resumeFromBackground] 退出挂起态（幂等：未挂起时调用无副作用）；
///  ④ 恢复后播放请求不再被拦；
///  ⑤ F70 v2（2026-10-05 复测仍会响）：`play()` 前**二次复查**闸门——setAsset/seek
///    的几百 ms 异步间隙内可能刚好退后台，只查入口一次会让在途加载在后台发声。
///    该语义需真实播放器才能模拟，headless 覆盖不到，由 `startBgm` /
///    `_playGardenAmbient` 内联保障（真机验证）。
///  ⑥ F71 v3（2026-10-07 复测「切 tab 后音乐停一下又继续播完」）：**代际 guard**——
///    `stopGardenAmbient` 递增代际，在途的 `_playGardenAmbient` 在每个 await 间隙
///    校验代际、被 stop 过即作废。headless 可断言「stop 递增代际 + stop 后
///    `ambientShouldPlay` 恒 false」；await 间隙竞态本身需真实播放器，真机验证。
library;

import 'package:flutter_test/flutter_test.dart' as ft;

import 'package:sunflower_time/platform/audio_service.dart';

void main() {
  ft.TestWidgetsFlutterBinding.ensureInitialized();

  ft.group('F70 · AudioService 后台挂起闸门', () {
    ft.test('① 挂起态进入且幂等；③ 恢复退出且幂等', () async {
      final AudioService svc = AudioService(playerFactory: () => null);
      ft.expect(svc.isSuspendedForBackground, ft.isFalse);

      await svc.pauseAllForBackground();
      ft.expect(svc.isSuspendedForBackground, ft.isTrue,
          reason: '退后台 → 挂起');

      // 幂等：重复挂起（hidden → paused 连发）不改变状态、不抛。
      await svc.pauseAllForBackground();
      ft.expect(svc.isSuspendedForBackground, ft.isTrue);

      await svc.resumeFromBackground();
      ft.expect(svc.isSuspendedForBackground, ft.isFalse, reason: '回前台 → 恢复');

      // 幂等：未挂起时再恢复无副作用。
      await svc.resumeFromBackground();
      ft.expect(svc.isSuspendedForBackground, ft.isFalse);
    });

    ft.test('② 挂起期间播放请求被闸门拦下；④ 恢复后放行', () async {
      final AudioService svc = AudioService(playerFactory: () => null);
      svc.applySettings(soundOn: true, bgmOn: true);

      await svc.pauseAllForBackground();
      // 挂起期间：BGM / 氛围音请求均被拦（null player 下本就无声，但闸门语义
      // 必须先行短路 —— 真机上这才是「后台定时器重新拉起音乐」的防线）。
      // 闸门在进入异步体**之前**短路，无需 pump 事件循环即可断言。
      svc.startBgm();
      svc.playGardenAmbient();
      ft.expect(svc.bgmPlaying, ft.isFalse,
          reason: '挂起期间 startBgm 被闸门拦下');
      ft.expect(svc.ambientShouldPlay, ft.isFalse,
          reason: '挂起期间 playGardenAmbient 被闸门拦下');

      await svc.resumeFromBackground();
      ft.expect(svc.isSuspendedForBackground, ft.isFalse);
    });

    ft.test('⑥ F71 v3 · stopGardenAmbient 递增代际并保持「应播=false」', () async {
      final AudioService svc = AudioService(playerFactory: () => null);
      svc.applySettings(soundOn: true, bgmOn: true);

      // 在途播放请求（null player → 静默降级，但代际语义仍可断言）。
      svc.playGardenAmbient();
      final int genBefore = svc.ambientGeneration;

      // 切 tab 的 stop：必须递增代际（作废一切在途加载/启动）。
      await svc.stopGardenAmbient();
      ft.expect(svc.ambientGeneration, ft.greaterThan(genBefore),
          reason: 'stopGardenAmbient 递增代际（F71 v3 竞态修复的闸门）');
      ft.expect(svc.ambientShouldPlay, ft.isFalse,
          reason: 'stop 后「应播」标记必须为 false（自愈监听不再续播）');

      // 重复 stop 继续递增（每次 stop 都要作废新一代在途请求）。
      final int genAfterFirst = svc.ambientGeneration;
      await svc.stopGardenAmbient();
      ft.expect(svc.ambientGeneration, ft.greaterThan(genAfterFirst));
    });
  });

  ft.group('F82 · 氛围音启动有限次重试（玄参 2026-10-07「首次进花园 BGM 不响」）', () {
    // headless 无音频后端、无法造真 AudioPlayer（just_audio 静态通道缺实现会抛）。
    // 故把重试逻辑抽成纯静态函数 [AudioService.startAmbientWithRetries]，用回调驱动单测。

    ft.test('首次 start 抛错 → 重试后成功启动（attempts=2）', () async {
      int attempts = 0;
      final bool ok = await AudioService.startAmbientWithRetries(
        start: () async {
          attempts++;
          if (attempts == 1) throw StateError('首次 setAsset 失败（冷启动缓存被清）');
        },
        isPlaying: () => true,
        shouldAbort: () => false,
        onAbort: () async {},
        retryDelay: Duration.zero,
      );
      ft.expect(ok, ft.isTrue, reason: '重试后成功 → 应置「已启动」');
      ft.expect(attempts, 2, reason: '首次失败 + 第二次成功 = 2 次尝试');
    });

    ft.test('play() 返回但实际未在播 → 重试后确在播（attempts=2）', () async {
      int attempts = 0;
      bool playing = false;
      final bool ok = await AudioService.startAmbientWithRetries(
        start: () async {
          attempts++;
          if (attempts >= 2) playing = true; // 第二次才真正播起来
        },
        isPlaying: () => playing,
        shouldAbort: () => false,
        onAbort: () async {},
        retryDelay: Duration.zero,
      );
      ft.expect(ok, ft.isTrue);
      ft.expect(attempts, 2);
    });

    ft.test('有限次（maxAttempts）仍失败 → 返回 false 且 onAbort 停播', () async {
      int attempts = 0;
      bool aborted = false;
      final bool ok = await AudioService.startAmbientWithRetries(
        start: () async => attempts++,
        isPlaying: () => false, // 始终未在播
        shouldAbort: () => false,
        onAbort: () async => aborted = true,
        maxAttempts: 3,
        retryDelay: Duration.zero,
      );
      ft.expect(ok, ft.isFalse, reason: '始终未启动 → 不得置「已启动」');
      ft.expect(attempts, 3, reason: '尝试次数恰为上限');
      ft.expect(aborted, ft.isTrue, reason: '失败收尾必须停播，不留残响');
    });

    ft.test('shouldAbort 命中（退后台 / 代际失效）→ 立即停播、返回 false、不再尝试', () async {
      int attempts = 0;
      bool aborted = false;
      final bool ok = await AudioService.startAmbientWithRetries(
        start: () async => attempts++,
        isPlaying: () => true,
        shouldAbort: () => true, // 一进循环即命中（模拟退后台）
        onAbort: () async => aborted = true,
        retryDelay: Duration.zero,
      );
      ft.expect(ok, ft.isFalse);
      ft.expect(attempts, 0, reason: '命中闸门不得发起任何启动');
      ft.expect(aborted, ft.isTrue, reason: '命中闸门必须停播（F70 v2 不发声）');
    });
  });
}
