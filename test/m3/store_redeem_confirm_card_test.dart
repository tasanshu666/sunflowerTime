/// F139（玄参 2026-10-20 截图反馈「商店页面兑换确认卡片也需要美化一下」）：
/// 商店兑换确认卡改走共享卡壳 [ChildConfirmCard] 后的**真实入口**回归。
///
/// ## 为什么不用「直接 new 一张 ChildConfirmCard」的组件层用例（C101-5「接线守」）
/// 上一批 F136 栽在「组件层用例自己传参 → 把参数删了 45 个用例全绿」。本轮的
/// 真实契约是「`StorePage._onRedeem` **接到了**卡壳上」，所以每一条用例都从
/// **真实商店页**走进去：挂 `StorePage` → 找到「小零食」那张 `RewardCard` →
/// 点它的「兑换」→ 再量弹窗。直接 new 卡片只能证明卡壳自己没坏，证明不了接线。
///
/// ## 覆盖 6 件事
///  ① **文案红线**：标题 / 两个按钮 / 三行明细 / 流程说明句，逐字（改一个字必红）；
///  ② **金额与余额正确**：消耗额 == 模板 `baseCost`；可用阳光 == `sunlightDisplayInt(余额 − 待核销)`
///     （假数据种成 1000.9 − 58 = 942.9 → 展示 942，任何「二次格式化」都会算错）；
///  ③ **取消分毫不扣**：点「再想想」→ 编排服务 `submit` **零调用**；
///  ④ **确认才提交**：点「确认兑换」→ `submit(tpl_snack, forcePending: true)` 真被调用；
///  ⑤ **宽度**：390 / 320 / 1032×1376 三档 → 326 / 256 / 544
///     （期望值按 `min(屏宽 − 64, 340 × uiScale)` **独立推导**，不引用被测常量）；
///  ⑥ **小屏 + 大字号零溢出**：320×568 + 1.3 倍字号 → `takeException() == null`。
///
/// ⚠️ 商店页没有无限动画（背景是静态 webp），故本文件可以用 `pumpAndSettle`；
/// 花园页那条禁令（木牌呼吸 / 害虫待机）不适用于此处。
library store_redeem_confirm_card_test;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/sunlight_display.dart';
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

// ── 夹具数值（可预测，便于独立推导期望值）────────────────────────────────────
/// 目标模板单价（截图里是 30 → 明细须显示 `−30 ☀`）。
const int _kSnackCost = 30;

/// 账本余额：**故意带小数**，用来钉住「向下取整」口径（1000.9 → 1000）。
const double _kBalance = 1000.9;

/// 另一张模板的待核销金额：计入「可用阳光」的扣减，但**不**涉及「小零食」这张卡
/// （否则该卡会因 hasActive 置灰，点不进去）。
const int _kOtherPendingCost = 58;

/// 期望的「可用阳光」：与页面同源口径（本测试独立算一遍，不复用页面里的变量）。
final int _kExpectedAvailable = sunlightDisplayInt(_kBalance - _kOtherPendingCost);

// ── 假仓储 ──────────────────────────────────────────────────────────────────

const AppSettings _kLowSettings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

class _FakeRewardRepository implements RewardRepository {
  static const List<RewardTemplate> _seeds = <RewardTemplate>[
    RewardTemplate(
      id: 'tpl_snack',
      name: '小零食',
      category: RewardCategory.parentHandled,
      contentCategory: RewardContentCategory.snacks,
      baseCost: _kSnackCost,
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
  Future<List<RewardTemplate>> templates() async => _seeds;

  @override
  Future<void> saveTemplate(RewardTemplate t) async {}

  @override
  Future<void> deleteTemplate(String id) async {}

  @override
  Future<void> createRequest(RedemptionRequest r) async {}

  /// 只有「多看一集动画片」有一笔待核销（58）→ 可用阳光 = 1000.9 − 58 = 942.9 → 942；
  /// 「小零食」不受影响，仍可点兑换。
  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async => <RedemptionRequest>[
        RedemptionRequest(
          id: 'r_pending_other',
          childId: 'c1',
          templateId: 'tpl_other',
          requestedAt: DateTime(2026, 10, 19, 9),
          cost: _kOtherPendingCost,
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
  Future<void> decrementCooldown(String templateId, CooldownPeriod window) async {}
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _kLowSettings;

  @override
  Future<void> saveSettings(AppSettings s) async {}
}

/// 低档账号桩（C91：周池预算按注入账号的当前年级现算；不钉低档会走「不限额」）。
class _LowTierAccountService implements AccountService {
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

class _FakeSunlightRepository implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => _kBalance;

  @override
  Future<double> balance() async => _kBalance;

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
          String refType, String refId, String dayKey) async =>
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
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}

class _FakeTrackingRepository implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent e) async {}

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      <TrackingEvent>[];

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

class _FakeWeeklyPoolRepository implements WeeklyPoolRepository {
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

/// 记录调用的假编排服务：`submit` 的**入参**被留证，用于断言「取消分毫不扣」。
class _RecordingOrchestrationService extends RedemptionOrchestrationService {
  _RecordingOrchestrationService()
      : super(
          reward: _FakeRewardRepository(),
          pools: WeeklyPoolService(
            _FakeWeeklyPoolRepository(),
            _FakeSettingsRepository(),
            _FakeTrackingRepository(),
          ),
          ledger: _FakeSunlightRepository(),
          tracking: _FakeTrackingRepository(),
          account: AccountService(),
          settings: _FakeSettingsRepository(),
        );

  /// 每次 `submit` 的入参快照（templateId / forcePending）。
  final List<String> calls = <String>[];

  @override
  Future<SubmitResult> submit(
    String templateId,
    AgeTier ageTier,
    DateTime now, {
    bool forcePending = false,
  }) async {
    calls.add('$templateId|forcePending=$forcePending');
    return const SubmitResult(
      outcome: SubmitOutcome.verified,
      requestId: 'req_f139',
      cost: _kSnackCost,
    );
  }
}

// ── 宿主与工具 ──────────────────────────────────────────────────────────────

/// 注入全部假实现后挂**真实** [StorePage]（与 test/m2/store_page_test.dart 同口径）。
Widget _host(_RecordingOrchestrationService orchestration) {
  return ProviderScope(
    overrides: <Override>[
      redemptionOrchestrationServiceProvider.overrideWithValue(orchestration),
      rewardRepositoryProvider.overrideWithValue(_FakeRewardRepository()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      accountServiceProvider.overrideWithValue(_LowTierAccountService()),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
      weeklyPoolRepositoryProvider
          .overrideWithValue(_FakeWeeklyPoolRepository()),
      trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
    ],
    child: const MaterialApp(home: StorePage()),
  );
}

/// 设屏 + 字号 → 挂商店页 → 点「小零食」卡的「兑换」→ 等确认卡出现。
///
/// 全程走真实入口（C101-5 接线守）：不 new 卡片、不直接调 `_onRedeem`。
Future<void> _openRedeemCard(
  WidgetTester tester, {
  required Size logicalSize,
  double textScale = 1.0,
  _RecordingOrchestrationService? orchestration,
}) async {
  tester.view.physicalSize = Size(
    logicalSize.width * 3,
    logicalSize.height * 3,
  );
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    _host(orchestration ?? _RecordingOrchestrationService()),
  );
  await tester.pumpAndSettle();

  // 找到「小零食」那张卡，点它自己的「兑换」（页里有两张卡 → 必须限定在卡内）。
  final Finder snackCard = find.widgetWithText(RewardCard, '小零食');
  expect(snackCard, findsOneWidget, reason: '真实商店页应渲染「小零食」这张奖励卡');
  final Finder redeemButton = find.descendant(
    of: snackCard,
    matching: find.text('兑换'),
  );
  expect(redeemButton, findsOneWidget, reason: '「小零食」卡上必须有「兑换」按钮');

  await tester.ensureVisible(redeemButton);
  await tester.pumpAndSettle();
  await tester.tap(redeemButton);
  await tester.pumpAndSettle();

  expect(find.byKey(ChildConfirmCard.surfaceKey), findsOneWidget,
      reason: '点兑换后必须弹出共享卡壳（接线守：走真实入口才测得到）');
}

/// 卡壳（奶油底 Container）的真实渲染宽度。
double _cardWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(ChildConfirmCard.surfaceKey)).width;

/// 排干异步尾巴：兑换成功会弹 2 秒庆祝动画 + `Future.delayed` 自动关闭，
/// 不排干会留 pending timer 让用例红在无关处。
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// 点「再想想」取消。
///
/// ⚠️ 必须先 `ensureVisible`：小屏 + 大字号下卡内容超出限高（`0.7 × 屏高`）→
/// 卡内滚动，按钮落在视口外的偏移上，直接 `tap` 会静默落空（在 320×568 + 1.3 倍
/// 字号下实测命中偏移 y=576 > 屏幕高 568）。
Future<void> _tapCancel(WidgetTester tester) async {
  final Finder cancel = find.text('再想想');
  await tester.ensureVisible(cancel);
  await tester.pumpAndSettle();
  await tester.tap(cancel);
  await tester.pumpAndSettle();
}

void main() {
  group('① 文案红线（真实商店页点进来）', () {
    testWidgets('标题 / 两个按钮 / 三行明细 / 流程说明句 全部逐字在位',
        (WidgetTester tester) async {
      await _openRedeemCard(tester, logicalSize: const Size(390, 844));

      // 回归红线：这三条字面量一个字符都不许改（截图已定稿）。
      expect(find.text('确认兑换？'), findsOneWidget, reason: '标题必须逐字为「确认兑换？」');
      expect(find.text('再想想'), findsOneWidget, reason: '取消按钮必须逐字为「再想想」');
      expect(find.text('确认兑换'), findsOneWidget,
          reason: '确认按钮必须逐字为「确认兑换」');

      // 原正文「确定要用 N 阳光兑换「X」吗？」的含义，落在明细三行里。
      expect(find.text('兑换物品'), findsOneWidget);
      expect(find.text('「小零食」'), findsOneWidget,
          reason: '明细必须点名兑换的是哪个奖励（原名，逐字）');
      expect(find.text('消耗阳光'), findsOneWidget);
      expect(find.text('可用阳光'), findsOneWidget);

      // 流程说明句：讲「会发生什么」→ 归 warning 槽（不是 note，禁混用）。
      expect(
        find.text('提交后需家长核销，核销通过才会扣除阳光。'),
        findsOneWidget,
        reason: '核销流程说明必须完整保留（孩子要知道「现在还没扣」）',
      );

      // 金档圆形徽标（ConfirmCardBadge），不是裸 AlertDialog。
      expect(find.byType(ConfirmCardBadge), findsOneWidget,
          reason: '卡头必须是金档圆形徽标（美化诉求的落点）');
      expect(find.byType(AlertDialog), findsNothing,
          reason: '不得再回退成裸 AlertDialog（改前形态）');

      await _tapCancel(tester);
    });
  });

  group('② 金额与余额正确', () {
    testWidgets('消耗额 == 模板 baseCost；可用阳光 == sunlightDisplayInt(余额 − 待核销)',
        (WidgetTester tester) async {
      await _openRedeemCard(tester, logicalSize: const Size(390, 844));

      // 消耗额：直接由夹具推导（30），不是「读页面变量再比页面」。
      expect(find.text('−$_kSnackCost ☀'), findsOneWidget,
          reason: '消耗阳光必须显示 −（模板 baseCost $_kSnackCost）');

      // 可用阳光：1000.9 − 58 = 942.9 → 向下取整 942。
      // 若调用方对 sunlightDisplayInt 的结果**再格式化一次**（round / toStringAsFixed），
      // 这里会变成 943 / 942.9，本断言必红。
      expect(_kExpectedAvailable, 942,
          reason: '夹具自检：期望值必须是 942（1000.9 − 58 向下取整）');
      expect(find.text('$_kExpectedAvailable ☀'), findsOneWidget,
          reason: '可用阳光必须与金色数字同源（余额 − 待核销，向下取整）');

      // 弱化行口径 + **槽位契约**（C101「warning / note 禁混用」）：
      // 直接从真实弹出来的卡片实例上读三个字段 —— 只看渲染出的文字是抓不到的，
      // 因为把 warning 挪进 `note` 后文字**一模一样**（QA 实测 M6b：8/8 全绿）。
      final ChildConfirmCard card =
          tester.widget<ChildConfirmCard>(find.byType(ChildConfirmCard));

      // ① note 必须为空：本卡没有「数字小结」，流程说明讲的是**后果**不是数字。
      expect(card.note, isNull,
          reason: '本卡没有数字小结，warning 讲后果不能挪进 note（C101 禁混用）');

      // ② 流程说明必须精确落在 warning 槽位（连标点逐字）。
      expect(card.warning, '提交后需家长核销，核销通过才会扣除阳光。',
          reason: '流程说明必须精确落在 warning 槽位');

      // ③ muted 逐行口径：[兑换物品, 消耗阳光, 可用阳光] → 只有参考值行弱化。
      expect(card.rows.map((ConfirmCardRow r) => r.muted).toList(),
          <bool>[false, false, true],
          reason: '只有参考值行（可用阳光）弱化');

      await _tapCancel(tester);
    });
  });

  group('③ 取消分毫不扣', () {
    testWidgets('点「再想想」→ 编排服务 submit 零调用', (WidgetTester tester) async {
      final _RecordingOrchestrationService orchestration =
          _RecordingOrchestrationService();
      await _openRedeemCard(
        tester,
        logicalSize: const Size(390, 844),
        orchestration: orchestration,
      );

      await _tapCancel(tester);

      expect(find.byKey(ChildConfirmCard.surfaceKey), findsNothing,
          reason: '点取消必须关卡');
      expect(orchestration.calls, isEmpty,
          reason: '取消是硬契约：`ok != true` 一律 return，领域层零触达（分毫不扣）');
    });
  });

  group('④ 确认才提交', () {
    testWidgets('点「确认兑换」→ 真的调了 submit（带 forcePending: true）',
        (WidgetTester tester) async {
      final _RecordingOrchestrationService orchestration =
          _RecordingOrchestrationService();
      await _openRedeemCard(
        tester,
        logicalSize: const Size(390, 844),
        orchestration: orchestration,
      );

      await tester.tap(find.text('确认兑换'));
      // 有限帧推进（submit 是 async，成功后还会推入 2 秒庆祝弹窗）：
      // 480ms 足够跑完 Dialog 关闭动画（150ms），又不足以跑完庆祝弹窗（2s）。
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(orchestration.calls, <String>['tpl_snack|forcePending=true'],
          reason: '确认后必须提交**选中的那个模板**，且走家长核销（forcePending: true）');
      expect(find.byKey(ChildConfirmCard.surfaceKey), findsNothing,
          reason: '确认后卡壳必须关闭（进入 submitting / 反馈流程）');

      // 排干：庆祝弹窗 2 秒自动关 + 经济修订号自增后的重算。
      await _drain(tester);
    });
  });

  group('⑤ 宽度（三档，期望值独立推导）', () {
    testWidgets('390 手机：min(390−64, 340×1.0) = 326', (WidgetTester tester) async {
      // 独立推导：Dialog 左右 insetPadding 各 32 → 可用宽 390 − 64 = 326；
      // 上限 340 × uiScale，而 390 屏 shortestSide = 390 < 600 → 手机倍率恒 1.0
      // → min(326, 340) = 326。
      final double expected = math.min(390 - 32 * 2, 340 * 1.0);
      await _openRedeemCard(tester, logicalSize: const Size(390, 844));

      expect(expected, 326, reason: '推导自检');
      expect(_cardWidth(tester), closeTo(expected, 0.5),
          reason: '手机 390：卡片顶满可用宽 326（与改前视觉一致，零回归）');

      await _tapCancel(tester);
    });

    testWidgets('320 小屏：min(320−64, 340×1.0) = 256', (WidgetTester tester) async {
      // 独立推导：可用宽 320 − 64 = 256 < 上限 340 → 256（宽度纯由屏宽决定）。
      final double expected = math.min(320 - 32 * 2, 340 * 1.0);
      await _openRedeemCard(tester, logicalSize: const Size(320, 568));

      expect(expected, 256, reason: '推导自检');
      expect(_cardWidth(tester), closeTo(expected, 0.5),
          reason: '320 小屏：卡片 = 屏宽 − 两侧 inset = 256');

      await _tapCancel(tester);
    });

    testWidgets('iPad 13″ 1032×1376（文字 1.6）：min(968, 340×1.6) = 544',
        (WidgetTester tester) async {
      // 独立推导：shortestSide = 1032 ≥ 600 → 平板；倍率 = clamp(1.3 × 1032/834, 1.3, 1.6)
      // = clamp(1.6086, 1.3, 1.6) = 1.6 → 上限 340 × 1.6 = 544；
      // 可用宽 1032 − 64 = 968 > 544 → 取 544（远窄于改前的 968）。
      const double uiScale = 1.6;
      final double expected = math.min(1032 - 32 * 2, 340 * uiScale);
      await _openRedeemCard(
        tester,
        logicalSize: const Size(1032, 1376),
        textScale: uiScale, // 生产口径：平板上文字也放大到 1.6
      );

      expect(expected, 544, reason: '推导自检');
      expect(_cardWidth(tester), closeTo(expected, 0.5),
          reason: '平板 544：既被 maxWidth×倍率 收住，又不能窄到装不下内容');
      expect(_cardWidth(tester), lessThan(968),
          reason: '🔴 改前平板宽 = 968（玄参：「太宽了」）；去掉限宽本断言必红');

      await _tapCancel(tester);
    });
  });

  group('⑥ 小屏 + 大字号零溢出', () {
    testWidgets('320×568 + 1.3 倍字号：takeException() == null',
        (WidgetTester tester) async {
      await _openRedeemCard(
        tester,
        logicalSize: const Size(320, 568),
        textScale: 1.3,
      );

      // 三行明细 + 流程说明句 + 两个按钮，在 320 宽 × 1.3 倍字号下必须零 overflow
      // （卡壳的限高 0.7 + 卡内滚动兜底；F126/F127 老坑位）。
      expect(tester.takeException(), isNull,
          reason: '小屏大字号下不得溢出（明细行名称可折行、金额不折行）');

      await _tapCancel(tester);
    });
  });
}