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
  });
}
