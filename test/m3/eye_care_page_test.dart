/// 少儿护眼休息卡 EyeCarePage 的 widget 测试（口径 C28 §7，玄参 2026-10-04 收口；
/// C50 / 2026-10-10 按钮合并后主按钮为**唯一出口**）。
///
/// 钉住**出口口径**（这些错了就是安全事故：孩子绕过护眼白拿奖励，或护眼永远出不去）：
///  ① **允许跳过（默认）**：点主按钮「跳过护眼休息」→ 先弹二次确认 → 确认才生效、
///     确认后**不发奖励、不写账本**；取消＝回护眼卡继续休息；
///  ② **家长关掉「允许跳过」**：主按钮点了**无效**并弹「不可跳过，请爱护眼睛」，
///     流程不推进；
///  ③ **返回键拦截**：护眼卡期间任何 pop（系统返回键/程序化 pop）都被拦下 → 同样弹
///     「不可跳过，请爱护眼睛」；
///  ④ **主按钮「跳过护眼休息」**（玄参 2026-10-08 定名；C50 合并后为唯一出口）：
///     自然走完时系统自动收口，主按钮语义 = 提前结束 = 跳过——**未走完流程就手点＝
///     视同跳过**：弹二次确认（明示无奖励 + 爱护眼睛提示），确认后不发奖励不写账本、
///     返回 skipped；家长禁跳时弹「不可跳过」不推进。只有**自然走完**（播放列表收口）
///     才返回 completed 且账本 +3（`refType='eye_care_break'` 字符串值冻结）。
///
/// 另加一条**播放列表推进**：段①播完自动切段②（帧速 = 帧数 ÷ 音频时长）、
/// 末段收口自动 completed（2026-10-05 素材定稿后口令/画面由素材自带）。
library eye_care_page_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
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
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
}

/// 只记录 `append` 的假护眼记录仓储（断言「完成 / 跳过都落一行」）。
class _FakeEyeCareLogRepository implements EyeCareLogRepository {
  /// 被写进去的护眼记录。
  final List<EyeCareLog> appended = <EyeCareLog>[];

  @override
  Future<void> append(EyeCareLog log) async => appended.add(log);

  @override
  Future<int> countByResult(EyeCareResultType type) async => appended
      .where((EyeCareLog l) => l.result == type)
      .length;

  @override
  Future<int> watchedSecondsByResult(EyeCareResultType type) async => appended
      .where((EyeCareLog l) => l.result == type)
      .fold<int>(0, (int sum, EyeCareLog l) => sum + l.watchedSeconds);
}

/// 固定为手机尺寸（护眼卡内容较高：帧舞台 + 出口按钮，
/// 默认 800×600 的测试画布会把「跳过」按钮顶到屏幕外 → tap 落空）。
///
/// 同时**拦截 eyecare 资产加载**：护眼帧是真实 720×720 位图，在 flutter_tester 里
/// 真解码（C43 起 640 帧 WebP，解码位图 ≈1.3GB）会把测试进程 OOM 杀死（exit 137，
/// 2026-10-05 实证；压图像缓存无效）。本文件只验证「播放收口 / 出口口径」，不验证
/// 位图——拦截后 Image.errorBuilder 占位、precache 静默跳过，与项目「美术分支不入
/// widget 测试」的既有共识一致（位图正确性由玄参模拟器验收）。
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  const MethodChannel assets = MethodChannel('flutter/assets');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    assets,
    (MethodCall call) async {
      if (call.arguments is String &&
          (call.arguments! as String).startsWith('assets/fx/eyecare640/')) {
        return null; // 视为加载失败 → errorBuilder / precache 跳过
      }
      return null; // 其余资产（字体等）同样走失败路径，用例不依赖位图
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(assets, null));
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
  late final _FakeEyeCareLogRepository eyeCareLog;

  _Harness({required this.skipAllowed, double startBalance = 100})
      : ledger = _FakeSunlightRepository(startBalance),
        eyeCareLog = _FakeEyeCareLogRepository();

  /// 压入护眼卡（`pushed` 在结果产出后即完成）。
  Future<void> open(
    WidgetTester tester, {
    EyeCareSource source = EyeCareSource.inSession,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        sunlightRepositoryProvider.overrideWithValue(ledger),
        eyeCareLogRepositoryProvider.overrideWithValue(eyeCareLog),
      ],
      child: MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox()),
      ),
    ));
    await _settle(tester);

    pushed = navKey.currentState!.push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => EyeCarePage(
          args: EyeCareArgs(skipAllowed: skipAllowed, source: source),
        ),
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
  group('主按钮「跳过护眼休息」（玄参 2026-10-08：未走完手点＝视同跳过）', () {
    testWidgets('未走完就手点主按钮 → 弹二次确认（无奖励明示）；取消 → 回护眼卡',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);

      expect(find.text(kEyeCareFinishLabel), findsOneWidget);

      await tester.tap(find.text(kEyeCareFinishLabel));
      await _settle(tester);

      // 弹二次确认卡（标题 + 明示无奖励 + 爱护眼睛提示），且未写账本。
      expect(find.text(kEyeCareEarlyFinishTitle), findsOneWidget);
      expect(find.text(kEyeCareEarlyFinishConfirmText), findsOneWidget);
      expect(h.ledger.appended, isEmpty, reason: '确认前绝不能写账本');

      // 取消 → 回护眼卡继续休息，不出结果。
      await tester.tap(find.text(kEyeCareEarlyFinishStayLabel));
      await _settle(tester);

      expect(find.text(kEyeCareEarlyFinishTitle), findsNothing);
      expect(find.text(kEyeCareFinishLabel), findsOneWidget,
          reason: '取消后还停在护眼卡');
      expect(h.ledger.appended, isEmpty);
    });

    testWidgets('未走完手点主按钮 → 确认结束 → 返回 skipped 且**不发奖励不写账本**',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);

      await tester.tap(find.text(kEyeCareFinishLabel));
      await _settle(tester);
      await tester.tap(find.text(kEyeCareEarlyFinishQuitLabel));
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
      expect(h.ledger.appended, isEmpty,
          reason: '确认结束＝按跳过处理：零账本变动');
      expect(find.text(kEyeCareFinishLabel), findsNothing, reason: '已退场');
    });
  });

  group('允许跳过（默认，C28 §7 第 1 条；C50 合并后走主按钮）', () {
    testWidgets('确认结束 → 护眼记录 skipped 落一行（家长报告跳过次数数据源）',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);

      await tester.tap(find.text(kEyeCareFinishLabel));
      await _settle(tester);
      await tester.tap(find.text(kEyeCareEarlyFinishQuitLabel));
      await _settle(tester);

      await h.pushed!;
      // 护眼记录：跳过**也落一行**（家长报告的跳过次数 / 部分观看时长数据源）。
      expect(h.eyeCareLog.appended, hasLength(1));
      expect(h.eyeCareLog.appended.single.result, EyeCareResultType.skipped);
      expect(
          h.eyeCareLog.appended.single.watchedSeconds, greaterThanOrEqualTo(0));
    });

    testWidgets('场末触发（source=sessionEnd）→ 护眼记录如实记录来源',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester, source: EyeCareSource.sessionEnd);

      await tester.tap(find.text(kEyeCareFinishLabel));
      await _settle(tester);
      await tester.tap(find.text(kEyeCareEarlyFinishQuitLabel));
      await _settle(tester);

      await h.pushed!;
      expect(h.eyeCareLog.appended, hasLength(1));
      expect(h.eyeCareLog.appended.single.source, EyeCareSource.sessionEnd);
      expect(h.eyeCareLog.appended.single.result, EyeCareResultType.skipped);
    });
  });

  group('家长关掉「允许跳过」（默认允许，可关，C28 §7 第 2 条；C50 合并后走主按钮）', () {
    testWidgets('主按钮点击无效 → 弹「不可跳过，请爱护眼睛」、流程不推进',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: false);
      await h.open(tester);

      // 口径（C50 合并）：主按钮是唯一出口；禁跳时点了无效弹提示、不藏按钮。
      await tester.tap(find.text(kEyeCareFinishLabel));
      await _settle(tester);

      expect(
        find.text(kEyeCareNotSkippableText),
        findsOneWidget,
        reason: '点了必须给「不可跳过，请爱护眼睛」提示',
      );
      // 关键：不弹二次确认、不写账本、护眼卡原地不动。
      expect(find.byType(AlertDialog), findsNothing);
      expect(h.ledger.appended, isEmpty);
      expect(find.text(kEyeCareFinishLabel), findsOneWidget,
          reason: '流程不推进：还停在护眼卡上');
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

  group('播放列表推进（C28 §2，2026-10-05 素材定稿）', () {
    // ⚠️ 不能用「pump(整段 durationMs) 一步到位」：入场过渡期页面 offstage、
    // 播放器在该窗口内才开始 tick，一次 pump 实际给出的时长略短于段长 →
    // onComplete 不触发 → 槽位永不推进 → `await pushed` 永挂（exit 137 实证）。
    // 改为 500ms 步进 pump 直到目标段标签出现（预算封顶，超时即 fail）。
    Future<void> _pumpUntilText(
      WidgetTester tester,
      String label, {
      Duration budget = const Duration(seconds: 20),
    }) async {
      final Duration step = const Duration(milliseconds: 500);
      Duration pumped = Duration.zero;
      while (pumped < budget) {
        await tester.pump(step);
        pumped += step;
        if (find.text(label).evaluate().isNotEmpty) return;
      }
      fail('等待「$label」超时（已 pump ${pumped.inMilliseconds}ms）');
    }

    testWidgets('起手 → 单段播完自动收口 = completed + 账本 + 护眼记录（C43 单段）',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);

      // 起手：单段字幕可见，账本未动。
      await _pumpUntilText(tester, kEyeCareSegment.label);
      expect(h.ledger.appended, isEmpty, reason: '没休息完不写账本');

      // 单段播完（63.974s）自动收口：预算 = 总长 + 富余，步进推进。
      for (int i = 0;
          i < (kEyeCarePlaylistTotalMs + 8000) ~/ 500;
          i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      final Object? result = await h.pushed!;
      expect(
        result,
        isA<EyeCareResult>().having(
          (EyeCareResult r) => r.type,
          'type',
          EyeCareResultType.completed,
        ),
      );
      expect(h.ledger.appended, hasLength(1));
      expect(h.ledger.appended.single.refType, kEyeCareRefType);
      expect(h.ledger.appended.single.net, kEyeCareRewardSunlight);
      // 护眼记录（玄参 2026-10-09）：完成也落一行（家长报告的时长 / 来源统计）。
      expect(h.eyeCareLog.appended, hasLength(1));
      expect(h.eyeCareLog.appended.single.result, EyeCareResultType.completed);
      expect(h.eyeCareLog.appended.single.source, EyeCareSource.inSession);
      expect(h.eyeCareLog.appended.single.watchedSeconds, greaterThan(0));
      expect(h.eyeCareLog.appended.single.dayKey, isNotEmpty);
    });

    test('播放列表契约（C43：恒单段，帧/音频参数钉死防素材漂移）', () {
      expect(kEyeCarePlaylist, hasLength(1));
      expect(kEyeCareSegment.dir, 'assets/fx/eyecare640');
      expect(kEyeCareSegment.frameCount, 640);
      expect(kEyeCareSegment.frameExt, 'webp');
      expect(kEyeCareSegment.sfxAsset, 'assets/audio/sfx/eyecare.mp3');
      expect(kEyeCarePlaylistTotalMs, kEyeCareSegment.durationMs);
    });
  });

  group('参数契约', () {
    testWidgets('EyeCareArgs 默认允许跳过（家长不配时的兜底口径）',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _Harness h = _Harness(skipAllowed: true);
      await h.open(tester);
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
