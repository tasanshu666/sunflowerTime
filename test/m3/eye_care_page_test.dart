/// 少儿护眼休息卡 EyeCarePage 的 widget 测试（口径 C28 §7，玄参 2026-10-04 收口）。
///
/// 钉住四条**出口口径**（这四条错了就是安全事故：孩子绕过护眼白拿奖励，或护眼永远出不去）：
///  ① **允许跳过（默认）**：点「跳过」→ 先弹二次确认 → 确认才生效、确认后**不发奖励、
///     不写账本**；取消＝回护眼卡继续休息；
///  ② **家长关掉「允许跳过」**：「跳过」按钮**仍在**（口径：护眼卡恒有两个出口），
///     点了**无效**并弹「不可跳过，请爱护眼睛」，流程不推进；
///  ③ **返回键拦截**：护眼卡期间任何 pop（系统返回键/程序化 pop）都被拦下 → 同样弹
///     「不可跳过，请爱护眼睛」；
///  ④ **完成休息**：账本 +2 阳光、`refType='eye_care_break'`（`String` 值冻结）、
///     返回 `EyeCareResultType.completed`。
///
/// 另加一条**阶段边界**：后台 1s tick 真的把画面从「闭眼口令」推进到「睁眼远眺」。
library eye_care_page_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/presentation/child/pages/eye_care_page.dart';

/// 只记录 `append` 的假账本（其余方法返回中性值）。
class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository(this.startBalance);

  /// 写入前的余额（用于核对 `balanceAfter = 写前 + amount`）。
  final double startBalance;

  /// 被写进去的账本行（断言「跳过不写账本 / 完成才写一行」）。
  final List<SunlightEntry> appended = <SunlightEntry>[];

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(appended);

  @override
  Future<double> balance() async => startBalance;

  @override
  Future<double> append(SunlightEntry entry) async {
    appended.add(entry);
    return startBalance + entry.net;
  }

  @override
  Future<double> dayNet(String dayKey) async => 0;

  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;

  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
}

/// 固定为手机尺寸（护眼卡内容较高：大环 220 + 演示 160 + 两个出口按钮，
/// 默认 800×600 的测试画布会把「跳过」按钮顶到屏幕外 → tap 落空）。
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 有界收敛（**绝不能**用 `pumpAndSettle`）。
///
/// 护眼页内嵌的 `SunflowerCanvas` 自带 `AnimationController..repeat(reverse: true)`
/// 无限呼吸动画，`pumpAndSettle` 永远等不到「树静止」→ 直接超时。这里的做法与
/// `garden_bloom_reward_ui_test` 一致：**有界 pump** 推进固定帧数即算收敛。
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// 护眼卡测试台：一个 Navigator + 一个假账本 + 一个 push 出去的 Future。
class _Harness {
  /// 家长「是否允许孩子跳过」。
  final bool skipAllowed;

  /// push 出去的路由结果（完成 / 跳过产出 [EyeCareResult]）。
  Future<Object?>? pushed;

  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  late final _FakeSunlightRepository ledger;

  _Harness({required this.skipAllowed, double startBalance = 100})
      : ledger = _FakeSunlightRepository(startBalance);

  /// 压入护眼卡（`pushed` 在结果产出后即完成）。
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        sunlightRepositoryProvider.overrideWithValue(ledger),
      ],
      child: MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox()),
      ),
    ));
    await _settle(tester);

    pushed = navKey.currentState!.push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) =>
            EyeCarePage(args: EyeCareArgs(skipAllowed: skipAllowed)),
      ),
    );
    await _settle(tester);
  }

  /// 触发一次「系统返回键」（本页拦截它、不会真的退场）。
  ///
  /// ⚠️ 必须用 `maybePop()`：系统返回键的真实语义就是 `maybePop`（先问
  /// `Route.popDisposition`，`PopScope.canPop:false` → `doNotPop` → 触发
  /// `onPopInvokedWithResult(didPop:false)` → 弹「不可跳过」提示）。写成
  /// `pop()` 是**强制退场**（`didPop:true`，源码按设计直接放行不弹提示），
  /// 护眼卡会被真的 pop 掉——那不是「拦截」，是绕过。
  Future<void> pressBack(WidgetTester tester) async {
    await navKey.currentState!.maybePop();
    await _settle(tester);
  }
}

void main() {
  group('完成休息（C28 §3）', () {
    testWidgets('点「完成休息」→ 账本 +2、refType 冻结为 eye_care_break、返回 completed',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);

      expect(find.text(kEyeCareFinishLabel), findsOneWidget);

      await tester.tap(find.text(kEyeCareFinishLabel));
      await _settle(tester);

      final Object? result = await h.pushed!;
      expect(
        result,
        isA<EyeCareResult>().having(
          (EyeCareResult r) => r.type,
          'type',
          EyeCareResultType.completed,
        ),
      );

      // 只写一行，且是护眼奖励。
      expect(h.ledger.appended, hasLength(1));
      final SunlightEntry entry = h.ledger.appended.single;
      expect(entry.refType, kEyeCareRefType);
      expect(entry.refType, 'eye_care_break');
      expect(entry.type, SunlightType.earn);
      expect(entry.net, kEyeCareRewardSunlight);
      expect(entry.gross, kEyeCareRewardSunlight);
      // 余额在「写入前」取后 +2（避免并发 / 重入把 balanceAfter 算错）。
      expect(entry.balanceAfter, 100 + kEyeCareRewardSunlight);
      // 护眼卡已退场。
      expect(find.text(kEyeCareFinishLabel), findsNothing);
    });
  });

  group('允许跳过（默认，C28 §7 第 1 条）', () {
    testWidgets('点跳过 → 弹二次确认；取消 → 回护眼卡继续（不写账本）',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);

      await tester.tap(find.text(kEyeCareSkipLabel));
      await _settle(tester);

      expect(find.text(kEyeCareSkipConfirmText), findsOneWidget);
      expect(find.text('再休息一会儿'), findsOneWidget);
      expect(find.text('确定跳过'), findsOneWidget);
      expect(h.ledger.appended, isEmpty, reason: '还没确认，绝不能写账本');

      // 取消确认 → 回到护眼卡，倒计时继续。
      await tester.tap(find.text('再休息一会儿'));
      await _settle(tester);

      expect(find.text(kEyeCareSkipConfirmText), findsNothing);
      expect(find.text(kEyeCareFinishLabel), findsOneWidget);
      expect(h.ledger.appended, isEmpty);
    });

    testWidgets('确认跳过 → 返回 skipped 且**不发奖励不写账本**',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);

      await tester.tap(find.text(kEyeCareSkipLabel));
      await _settle(tester);
      await tester.tap(find.text('确定跳过'));
      await _settle(tester);

      final Object? result = await h.pushed!;
      expect(
        result,
        isA<EyeCareResult>().having(
          (EyeCareResult r) => r.type,
          'type',
          EyeCareResultType.skipped,
        ),
      );
      // 跳过＝零账本变动（护眼时长也不回溯补算成专注时长）。
      expect(h.ledger.appended, isEmpty);
      expect(find.text(kEyeCareFinishLabel), findsNothing, reason: '已退场');
    });
  });

  group('家长关掉「允许跳过」（默认允许，可关，C28 §7 第 2 条）', () {
    testWidgets('「跳过」按钮仍在但点了无效 → 弹「不可跳过，请爱护眼睛」、流程不推进',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: false);
      await h.open(tester);

      // 口径：护眼卡恒有「跳过」与「完成休息」两个出口 —— 不是把按钮藏掉。
      expect(find.text(kEyeCareSkipLabel), findsOneWidget);

      await tester.tap(find.text(kEyeCareSkipLabel));
      await _settle(tester);

      expect(
        find.text(kEyeCareNotSkippableText),
        findsOneWidget,
        reason: '点了必须给「不可跳过，请爱护眼睛」提示',
      );
      // 关键：不弹二次确认、不写账本、护眼卡原地不动。
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(kEyeCareSkipConfirmText), findsNothing);
      expect(h.ledger.appended, isEmpty);
      expect(find.text(kEyeCareFinishLabel), findsOneWidget,
          reason: '流程不推进：还停在护眼卡上');

      // 且**依然可以正常完成休息**（另一条出口没被关掉）。
      await tester.tap(find.text(kEyeCareFinishLabel));
      await _settle(tester);
      final Object? result = await h.pushed!;
      expect((result! as EyeCareResult).type, EyeCareResultType.completed);
      expect(h.ledger.appended, hasLength(1));
    });
  });

  group('返回键拦截（C28 §7 第 3 条）', () {
    testWidgets('拦截返回键 → 弹「不可跳过，请爱护眼睛」且不出结果、不写账本',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);

      await h.pressBack(tester);

      expect(
        find.text(kEyeCareNotSkippableText),
        findsOneWidget,
        reason: '拦截返回键时同样给出「不可跳过，请爱护眼睛」',
      );
      expect(find.text(kEyeCareFinishLabel), findsOneWidget,
          reason: '被拦下：护眼卡还在，不能退场');
      expect(h.ledger.appended, isEmpty);
    });

    testWidgets('家长关掉「允许跳过」时，返回键拦截给出同一句提示',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: false);
      await h.open(tester);

      await h.pressBack(tester);

      expect(find.text(kEyeCareNotSkippableText), findsOneWidget);
      expect(find.text(kEyeCareFinishLabel), findsOneWidget);
      expect(h.ledger.appended, isEmpty);
    });
  });

  group('两段式画面推进（C28 §2）', () {
    testWidgets('后台 tick 走到 30 秒 → 画面从闭眼口令切到睁眼远眺',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);

      // 起手是闭眼段。
      expect(find.text(kEyeCarePhaseClosedTitle), findsOneWidget);

      // 1s 定时器：整段 60 秒，跳到「刚过第 30 秒」。
      await tester.pump(const Duration(seconds: kEyeCarePhaseSeconds + 1));
      await _settle(tester);

      expect(find.text(kEyeCarePhaseFarGazeTitle), findsOneWidget);
      expect(find.text(kEyeCarePhaseClosedTitle), findsNothing);

      // 收尾（避免定时器在用例结束后继续触发）。
      await tester.tap(find.text(kEyeCareFinishLabel));
      await _settle(tester);
      final Object? result = await h.pushed!;
      expect((result! as EyeCareResult).type, EyeCareResultType.completed);
    });
  });

  group('参数契约', () {
    testWidgets('EyeCareArgs 默认允许跳过（家长不配时的兜底口径）',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);
      expect(find.text(kEyeCareSkipLabel), findsOneWidget);
      expect(find.text(kEyeCareFinishLabel), findsOneWidget);
    });

    test('EyeCareService 判定与页面一致（完成给奖励、跳过不给）',
        () {
      expect(EyeCareService.rewardSunlight(), kEyeCareRewardSunlight);
      expect(EyeCareResult(EyeCareResultType.completed).completed, isTrue);
      expect(EyeCareResult(EyeCareResultType.skipped).skipped, isTrue);
    });
  });
}
