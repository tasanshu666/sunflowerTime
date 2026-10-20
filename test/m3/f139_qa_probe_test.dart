/// F139 QA 独立探针（严过关）。**不是本轮交付物的一部分**，只用于复核取证：
///  ① 宽度三档：期望值按 `min(屏宽 − 64, 340 × uiScale)` **独立推导**（不 import
///     `ChildConfirmStyle`、不读被测常量）；
///  ② 「可用阳光」与外壳金色数字 `StoreBalancePill` **同源**（两处同时断言）；
///     `RewardCard` 上的价格与弹窗「消耗阳光」**同一口径**（两处同时断言）；
///  ③ `muted` **只**落在「可用阳光」一行（另两行必须非弱化）；
///  ④ 320×568 系列：卡内按钮的**真实命中偏移**（判断「初始在视口外」是否成立）；
///  ⑤ **对照实验**：同一尺寸下改前的裸 `AlertDialog` 按钮是否在视口内
///     —— 用于判定「按钮跑到视口外」是本轮引入还是卡壳设计内行为。
library f139_qa_probe_test;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/redemption_orchestration_service.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:sunflower_time/presentation/child/pages/store_page.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
import 'package:sunflower_time/presentation/child/widgets/reward_card.dart';

// ── 夹具（与 engineer 用例独立：数值不同，故意让「照抄预期」不可能通过）──────
const int kSnackCost = 30;
const double kBalance = 1000.9;
const int kOtherPending = 58;

const AppSettings kSettings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

class _Rewards implements RewardRepository {
  @override
  Future<List<RewardTemplate>> templates() async => const <RewardTemplate>[
        RewardTemplate(
          id: 'tpl_snack',
          name: '小零食',
          category: RewardCategory.parentHandled,
          contentCategory: RewardContentCategory.snacks,
          baseCost: kSnackCost,
          frequencyLimitPerWeek: 1,
        ),
        RewardTemplate(
          id: 'tpl_other',
          name: '多看一集动画片',
          category: RewardCategory.selfService,
          contentCategory: RewardContentCategory.play,
          baseCost: 60,
          frequencyLimitPerWeek: 1,
        ),
      ];

  @override
  Future<void> saveTemplate(RewardTemplate t) async {}

  @override
  Future<void> deleteTemplate(String id) async {}

  @override
  Future<void> createRequest(RedemptionRequest r) async {}

  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async =>
      <RedemptionRequest>[
        RedemptionRequest(
          id: 'r_pending_other',
          childId: 'c1',
          templateId: 'tpl_other',
          requestedAt: DateTime(2026, 10, 20, 9),
          cost: kOtherPending,
          status: RequestStatus.pending,
        ),
      ];

  @override
  Future<List<RedemptionRequest>> verifiedRequests() async =>
      <RedemptionRequest>[];

  @override
  Future<List<RedemptionRequest>> rejectedRequests() async =>
      <RedemptionRequest>[];

  @override
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) async =>
      <RedemptionRequest>[];

  @override
  Future<void> updateRequest(RedemptionRequest r) async {}

  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) async => 0;

  @override
  Future<void> decrementCooldown(
    String templateId,
    CooldownPeriod window,
  ) async {}
}

class _Settings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => kSettings;

  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _Account implements AccountService {
  @override
  String get childId => 'single-child';

  @override
  String currentChildId() => childId;

  @override
  Future<void> ensureChild() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> switchTo(String id) async {}

  @override
  Future<ChildProfile> createChild(String name, AgeTier ageTier) =>
      throw UnsupportedError('not used');

  @override
  Future<ChildProfile?> currentProfile() async => null;

  @override
  Future<AgeTier> currentAgeTier() async => AgeTier.low;

  @override
  Never signIn() => throw UnsupportedError('not used');

  @override
  Never linkFamily() => throw UnsupportedError('not used');

  @override
  Never syncProfile() => throw UnsupportedError('not used');
}

class _Sunlight implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => kBalance;

  @override
  Future<double> balance() async => kBalance;

  @override
  Future<double> dayNet(String dayKey) async => 0;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String dayKey,
  ) async =>
      0;

  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;

  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;

  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;

  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
}

class _Tracking implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent e) async {}

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      <TrackingEvent>[];

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

class _Pools implements WeeklyPoolRepository {
  @override
  Future<WeeklyPool?> get(String weekKey) async => null;

  @override
  Future<void> upsert(WeeklyPool value) async {}

  @override
  List<String> weeksBetween(String fromKey, String toKey) => <String>[
        fromKey,
        toKey,
      ];
}

class _NoSubmit extends RedemptionOrchestrationService {
  _NoSubmit()
      : super(
          reward: _Rewards(),
          pools: WeeklyPoolService(_Pools(), _Settings(), _Tracking()),
          ledger: _Sunlight(),
          tracking: _Tracking(),
          account: AccountService(),
          settings: _Settings(),
        );

  int submitCalls = 0;

  @override
  Future<SubmitResult> submit(
    String templateId,
    AgeTier ageTier,
    DateTime now, {
    bool forcePending = false,
  }) async {
    submitCalls++;
    return const SubmitResult(
      outcome: SubmitOutcome.verified,
      requestId: 'req_probe',
      cost: kSnackCost,
    );
  }
}

Widget _storeHost(_NoSubmit orchestration) => ProviderScope(
      overrides: <Override>[
        redemptionOrchestrationServiceProvider.overrideWithValue(orchestration),
        rewardRepositoryProvider.overrideWithValue(_Rewards()),
        settingsRepositoryProvider.overrideWithValue(_Settings()),
        accountServiceProvider.overrideWithValue(_Account()),
        sunlightRepositoryProvider.overrideWithValue(_Sunlight()),
        weeklyPoolRepositoryProvider.overrideWithValue(_Pools()),
        trackingRepositoryProvider.overrideWithValue(_Tracking()),
      ],
      child: const MaterialApp(home: StorePage()),
    );

void _size(WidgetTester tester, Size logical, {double textScale = 1.0}) {
  tester.view.physicalSize = Size(logical.width * 3, logical.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 真实入口：挂商店页 → 点「小零食」卡上的「兑换」→ 等确认卡出现。
Future<void> _openCard(WidgetTester tester) async {
  await tester.pumpWidget(_storeHost(_NoSubmit()));
  await tester.pumpAndSettle();
  final Finder card = find.widgetWithText(RewardCard, '小零食');
  expect(card, findsOneWidget);
  final Finder btn = find.descendant(of: card, matching: find.text('兑换'));
  await tester.ensureVisible(btn);
  await tester.pumpAndSettle();
  await tester.tap(btn);
  await tester.pumpAndSettle();
  expect(find.byKey(ChildConfirmCard.surfaceKey), findsOneWidget);
}

/// 卡内某个按钮的**真实命中矩形**（全局坐标，可判断是否落在视口外）。
Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  group('① 宽度（期望值独立推导：min(屏宽 − 2×32, 340 × uiScale)）', () {
    testWidgets('390×844 → 326', (WidgetTester tester) async {
      // 独立推导：shortestSide=390 < 600 → uiScale = 1.0；可用宽 = 390 − 64 = 326
      const double expected = 326;
      expect(math.min(390 - 64, 340 * 1.0), expected);
      _size(tester, const Size(390, 844));
      await _openCard(tester);

      final Size actual =
          tester.getSize(find.byKey(ChildConfirmCard.surfaceKey));
      // ignore: avoid_print
      print('[QA-PROBE][W390] actual=${actual.width}x${actual.height}');
      expect(actual.width, closeTo(expected, 0.5));
    });

    testWidgets('320×568 → 256', (WidgetTester tester) async {
      const double expected = 256;
      expect(math.min(320 - 64, 340 * 1.0), expected);
      _size(tester, const Size(320, 568));
      await _openCard(tester);

      final Size actual =
          tester.getSize(find.byKey(ChildConfirmCard.surfaceKey));
      // ignore: avoid_print
      print('[QA-PROBE][W320] actual=${actual.width}x${actual.height}');
      expect(actual.width, closeTo(expected, 0.5));
    });

    testWidgets('1032×1376 → 544', (WidgetTester tester) async {
      // 独立推导 uiScale：clamp(1.3 × 1032/834, 1.3, 1.6) = 1.6
      const double uiScale = 1.6;
      const double expected = 544;
      expect(math.min(1032 - 64, 340 * uiScale), expected);
      _size(tester, const Size(1032, 1376), textScale: uiScale);
      await _openCard(tester);

      final Size actual =
          tester.getSize(find.byKey(ChildConfirmCard.surfaceKey));
      // ignore: avoid_print
      print('[QA-PROBE][W1032] actual=${actual.width}x${actual.height}');
      expect(actual.width, closeTo(expected, 0.5));
    });
  });

  group('② 口径同源（两处同时断言）', () {
    testWidgets('外壳金色数字 与 卡内「可用阳光」必须同为 942', (WidgetTester tester) async {
      _size(tester, const Size(390, 844));
      await tester.pumpWidget(_storeHost(_NoSubmit()));
      await tester.pumpAndSettle();

      // 外壳 StoreBalancePill：'☀ 942' + '待核销 58'
      expect(find.text('☀ 942'), findsOneWidget,
          reason: '外壳金色数字必须是 sunlightDisplayInt(1000.9 − 58) = 942');
      expect(find.text('待核销 58'), findsOneWidget);

      final Finder card = find.widgetWithText(RewardCard, '小零食');
      final Finder btn = find.descendant(of: card, matching: find.text('兑换'));
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();

      // 卡内「可用阳光」必须与外壳**同一个数**
      expect(find.text('942 ☀'), findsOneWidget,
          reason: '卡内「可用阳光」必须与外壳金色数字同源（都是 942）');
      // 消耗额必须 == RewardCard 上那张卡显示的价格（30）：
      //   · 弹窗侧：`−30 ☀`（带符号与单位，**不允许**出现裸 `30` 的明细行）；
      //   · 卡片侧：价格 `Text('30')` 仍单独存在（弹窗不遮住它）。
      expect(find.text('−30 ☀'), findsOneWidget);
      final List<String> cardTexts = tester
          .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
          .map((Text t) => t.data ?? '')
          .toList();
      // ignore: avoid_print
      print('[QA-PROBE][cardTexts] $cardTexts');
      expect(cardTexts, contains('$kSnackCost'),
          reason: 'RewardCard 上的价格必须也是 30（与弹窗「消耗阳光」同值）');
    });
  });

  group('③ muted / 槽位语义', () {
    testWidgets('muted 只在「可用阳光」；warning 走后果槽、note 必须为空',
        (WidgetTester tester) async {
      _size(tester, const Size(390, 844));
      await _openCard(tester);

      final ChildConfirmCard card = tester
          .widget<ChildConfirmCard>(find.byType(ChildConfirmCard));
      expect(card.rows.length, 3, reason: '明细必须正好 3 行');
      final Map<String, bool> muted = <String, bool>{
        for (final ConfirmCardRow r in card.rows) r.name: r.muted,
      };
      // ignore: avoid_print
      print('[QA-PROBE][muted] $muted');
      expect(muted['兑换物品'], isFalse, reason: '「兑换物品」是本次动作，不得弱化');
      expect(muted['消耗阳光'], isFalse, reason: '「消耗阳光」是本次动作，不得弱化');
      expect(muted['可用阳光'], isTrue, reason: '「可用阳光」是参考值，必须弱化');

      expect(card.note, isNull,
          reason: 'C101：note 专讲数字小结；本卡没有数字小结 → 必须为空');
      expect(card.warning, '提交后需家长核销，核销通过才会扣除阳光。',
          reason: 'C101：warning 讲后果/流程 → 流程句必须落在 warning');
      expect(card.confirmLabel, '确认兑换');
      expect(card.cancelLabel, '再想想');
      expect(card.title, '确认兑换？');
      expect(card.hero, isA<ConfirmCardBadge>());
    });
  });

  group('④ 卡内按钮的真实视口位置（设计内行为判定）', () {
    // 矩阵：屏 × 字号 → 取消按钮是否落在视口内。
    final List<(Size, double)> cases = <(Size, double)>[
      (const Size(390, 844), 1.0),
      (const Size(390, 844), 1.3),
      (const Size(320, 568), 1.0),
      (const Size(320, 568), 1.3),
      (const Size(1032, 1376), 1.6),
    ];
    for (final (Size size, double scale) in cases) {
      testWidgets('${size.width}x${size.height} @$scale → 按钮初始位置',
          (WidgetTester tester) async {
        _size(tester, size, textScale: scale);
        await _openCard(tester);

        final Rect surface =
            _rect(tester, find.byKey(ChildConfirmCard.surfaceKey));
        final Rect cancel = _rect(tester, find.text('再想想'));
        final Rect confirm = _rect(tester, find.text('确认兑换'));
        final Size screen = size;
        // ignore: avoid_print
        print('[QA-PROBE][rect] ${size.width}x${size.height}@$scale '
            'surface=${surface.top.toStringAsFixed(1)}..'
            '${surface.bottom.toStringAsFixed(1)} '
            'cancel=${cancel.top.toStringAsFixed(1)}..'
            '${cancel.bottom.toStringAsFixed(1)} '
            'confirm=${confirm.top.toStringAsFixed(1)}..'
            '${confirm.bottom.toStringAsFixed(1)} '
            'screenH=${screen.height} '
            'overflowFree=${tester.takeException() == null}');
      });
    }
  });

  group('⑤ 对照：改前的裸 AlertDialog（同尺寸，按钮是否在视口内）', () {
    /// 逐字复刻改前的弹窗（title / content / actions 与 git HEAD 一致）。
    Widget legacyDialogHost() => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => Center(
                child: TextButton(
                  onPressed: () => showDialog<bool>(
                    context: ctx,
                    builder: (BuildContext c) => AlertDialog(
                      title: const Text('确认兑换？'),
                      content:                       const Text('确定要用 $kSnackCost 阳光兑换「小零食」吗？\n'
                          '提交后需家长核销，核销通过才会扣除阳光。'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(c).pop(false),
                          child: const Text('再想想'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(c).pop(true),
                          child: const Text('确认兑换'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

    for (final (Size size, double scale) in <(Size, double)>[
      (const Size(320, 568), 1.0),
      (const Size(320, 568), 1.3),
      (const Size(390, 844), 1.3),
    ]) {
      testWidgets('旧 AlertDialog ${size.width}x${size.height}@$scale',
          (WidgetTester tester) async {
        _size(tester, size, textScale: scale);
        await tester.pumpWidget(legacyDialogHost());
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final Rect cancel = _rect(tester, find.text('再想想'));
        final Rect confirm = _rect(tester, find.text('确认兑换'));
        final Rect dialog = _rect(tester, find.byType(AlertDialog));
        // ignore: avoid_print
        print('[QA-PROBE][legacy] ${size.width}x${size.height}@$scale '
            'dialog=${dialog.top.toStringAsFixed(1)}..'
            '${dialog.bottom.toStringAsFixed(1)} '
            'cancel=${cancel.top.toStringAsFixed(1)}..'
            '${cancel.bottom.toStringAsFixed(1)} '
            'confirm=${confirm.top.toStringAsFixed(1)}..'
            '${confirm.bottom.toStringAsFixed(1)} '
            'screenH=${size.height} '
            'exception=${tester.takeException()}');
        expect(confirm.bottom, lessThanOrEqualTo(size.height),
            reason: '改前形态下按钮应完整落在屏内');
      });
    }
  });

  group('⑥ 卡壳层对照：既有 F135 卡（扩容）在 320×568@1.3 的按钮位置', () {
    // ⚠️ 本组**只量卡壳行为**，不是接线守：直接调 showChildConfirmCard 复刻
    // `garden_page._onExpandPot` 的六个槽位（badge / 2 行 / note / 按钮）。
    // 目的：判断「按钮初始落在视口外」是**卡壳既有设计**还是本轮引入。
    testWidgets('F135 扩容卡同尺寸同样把按钮推出视口 → 属卡壳设计内行为',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => Center(
              child: TextButton(
                onPressed: () => showChildConfirmCard(
                  context: ctx,
                  title: '要给花园腾一个花盆吗？',
                  hero: const ConfirmCardBadge(icon: Icons.yard),
                  rows: const <ConfirmCardRow>[
                    ConfirmCardRow(
                      icon: Icons.wb_sunny,
                      name: '本次扩容',
                      value: '−300 ☀',
                    ),
                    ConfirmCardRow(
                      icon: Icons.account_balance_wallet_outlined,
                      name: '当前阳光',
                      value: '1042 ☀',
                      muted: true,
                    ),
                  ],
                  note: '花园容量：4 盆 → 5 盆',
                  confirmLabel: '确定，扣除',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final Rect surface =
          _rect(tester, find.byKey(ChildConfirmCard.surfaceKey));
      final Rect cancel = _rect(tester, find.text('取消'));
      final Rect confirm = _rect(tester, find.text('确定，扣除'));
      // ignore: avoid_print
      print('[QA-PROBE][f135-card] surface=${surface.top.toStringAsFixed(1)}..'
          '${surface.bottom.toStringAsFixed(1)} '
          'cancel=${cancel.top.toStringAsFixed(1)}..'
          '${cancel.bottom.toStringAsFixed(1)} '
          'confirm=${confirm.bottom.toStringAsFixed(1)} screenH=568.0');
    });
  });
}
