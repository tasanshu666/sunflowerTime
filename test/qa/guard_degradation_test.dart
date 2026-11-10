/// 花园守卫独立验收 · **V6 降级路径**
///
/// 三条都必须「孩子看不到错误」：
///  ① prefs 不可用 ⇒ 今日页照常渲染、胶囊不存在（花园页同理，见报告静态证据）；
///  ② 守卫读链路超时（`kGuardTodayReadTimeout` = 600ms）⇒ 胶囊不存在、其余正常；
///  ③ 存档是未来日期 / 损坏 JSON ⇒ 不抛到 UI。
///
/// `[Guard]` 开头的 `debugPrint` 是**正常降级日志**，本文件不把它当失败。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
// B2：页面第 0 项已换场景卡，页面级存在性断言跟着换 key
// （胶囊本体 guard_pill.dart 仍保留作其他 QA 夹具，本文件不再用它）。
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

import 'guard_probe_support.dart';

/// 永远不返回的守卫服务（模拟「IO 卡住不抛错」）。
class _HangingGuardService extends GuardService {
  _HangingGuardService({
    required super.store,
    required super.ledger,
    required super.focus,
    required super.plants,
    required super.growth,
    required super.childId,
  });

  @override
  Future<GuardExpireOutcome> expire({DateTime? now}) =>
      Completer<GuardExpireOutcome>().future;

  @override
  Future<GuardResolveResult> resolve({DateTime? now}) =>
      Completer<GuardResolveResult>().future;

  @override
  Future<int> energyAvailable({DateTime? now}) => Completer<int>().future;
}

/// 挂今日页并推进 [frames] × 100ms（**绝不** `pumpAndSettle`：阳光气泡是无限循环）。
Future<ProviderContainer> _pumpToday(
  WidgetTester tester,
  GuardProbeEnv env, {
  bool withPrefs = true,
  GuardService? service,
  int frames = 24,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appDatabaseProvider.overrideWithValue(env.database),
      accountServiceProvider.overrideWithValue(env.account),
      if (withPrefs) sharedPreferencesProvider.overrideWithValue(env.sp),
      if (service != null) guardServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChildTodayPage()),
    ),
  );
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // V6-1 prefs 不可用
  // ══════════════════════════════════════════════════════════════════════
  group('V6-1 prefs 不可用（不 override sharedPreferencesProvider）', () {
    testWidgets('今日页照常渲染、胶囊零占位、无异常冒泡', (WidgetTester tester) async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);
      final ProviderContainer container =
          await _pumpToday(tester, env, withPrefs: false);

      expect(tester.takeException(), isNull,
          reason: '🔴 prefs 不可用必须是正常降级，不能把异常抛到 UI');
      expect(find.byKey(GuardSceneCard.cardKey), findsNothing,
          reason: '守卫读链路不可用 ⇒ 视同没有守卫');
      expect(container.read(guardTodayProvider).mode, GuardPillMode.absent);
      expect(find.text('今日获取阳光'), findsOneWidget);
    });

    testWidgets('对照组：prefs 正常 + 有存活株 ⇒ 胶囊出现', (WidgetTester tester) async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);
      await env.seedPlant('plant_1', now: DateTime.now());

      final ProviderContainer container = await _pumpToday(tester, env);

      expect(tester.takeException(), isNull);
      expect(container.read(guardTodayProvider).isVisible, isTrue,
          reason: '有存活株 ⇒ resolve 必生成小偷');
      expect(find.byKey(GuardSceneCard.cardKey), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V6-2 守卫读链路超时
  // ══════════════════════════════════════════════════════════════════════
  group('V6-2 守卫读链路卡住（不抛错、永不返回）', () {
    testWidgets('超过 600ms ⇒ 胶囊不存在、今日页其余正常', (WidgetTester tester) async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);
      await env.seedPlant('plant_1', now: DateTime.now());

      final GuardService hanging = _HangingGuardService(
        store: env.store,
        ledger: env.ledger,
        focus: env.focus,
        plants: env.plants,
        growth: env.growth,
        childId: () => env.childId,
      );

      final ProviderContainer container =
          await _pumpToday(tester, env, service: hanging, frames: 30);

      expect(tester.takeException(), isNull);
      expect(container.read(guardTodayProvider).mode, GuardPillMode.absent);
      expect(find.byKey(GuardSceneCard.cardKey), findsNothing,
          reason: '🔴 链路卡住时绝不能把今日页拖成转圈 / 白屏');
      expect(find.text('今日获取阳光'), findsOneWidget);
    });

    test('超时常量就是 600ms（字面量，防悄悄调大）', () {
      expect(kGuardTodayReadTimeout, const Duration(milliseconds: 600));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V6-3 存档损坏 / 未来日期
  // ══════════════════════════════════════════════════════════════════════
  group('V6-3 存档损坏 / 未来日期', () {
    test('损坏 JSON（半截）⇒ 读成今天空白态，不抛', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);

      await env.sp.setString(
        'guard_day_state_v2_${env.childId}',
        '{"dayKey":"${env.today}","status":"pending","thiefKind":',
      );
      final GuardDayState state = await env.store.read(env.childId);

      expect(state.dayKey, env.today);
      expect(state.hasThief, isFalse);
      expect(state.status, GuardDayStatus.none);
    });

    test('损坏 JSON（非 Map：数组 / 数字 / 空串）⇒ 一律空白态', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);

      for (final String bad in <String>['[]', '42', '"abc"', '']) {
        await env.sp.setString('guard_day_state_v2_${env.childId}', bad);
        final GuardDayState state = await env.store.read(env.childId);
        expect(state.hasThief, isFalse, reason: '坏存档 = $bad');
        expect(state.dayKey, env.today);
      }
    });

    test('未知线名（未来版本写入的 status / thiefKind）⇒ 安全兜底，不抛', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);

      await env.sp.setString(
        'guard_day_state_v2_${env.childId}',
        '{"dayKey":"${env.today}","status":"from_the_future",'
        '"thiefKind":"ufo","dropKind":"jackpot","winSun":9,'
        '"energyUsed":0,"paidSun":0,"sunStolen":0,"growthStolen":{}}',
      );
      final GuardDayState state = await env.store.read(env.childId);

      expect(state.status, GuardDayStatus.none);
      expect(state.thiefKind, isNull, reason: '未知贼名 ⇒ null（不是抛异常）');
      expect(state.winSun, 9, reason: '数字字段照读');
    });

    test('未来日期存档：expire 空操作、resolve 覆盖成本天、全程不抛', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);
      await env.seedPlant('plant_1');

      await env.store.write(
        env.childId,
        const GuardDayState(
          dayKey: '2099-01-01',
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 3,
          sunStolen: 5,
        ),
      );

      final GuardExpireOutcome expired = await env.guard.expire();
      expect(expired.settled, isFalse, reason: '绝不结算「未来的一天」');
      expect((await env.store.read(env.childId)).dayKey, '2099-01-01',
          reason: '也绝不清档');

      final GuardResolveResult resolved = await env.guard.resolve();
      expect(resolved.dayKey, dayKey(env.clock()));
      expect((await env.store.read(env.childId)).dayKey, dayKey(env.clock()));
    });
  });
}
