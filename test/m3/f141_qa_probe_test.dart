/// **F141 + C105 · QA 独立探针**（严过关 QA，2026-10-20）。
///
/// ## 这份文件与工程师自测的分工
/// `f141_confirm_card_unified_test.dart` 是**工程师自证**「我覆盖了什么」；
/// 本文件是 QA **从真实入口重新量一遍**，只信实测数字。刻意**不复用**他的用例，
/// 期望值全部来自 `git show HEAD:<file>` 里被删掉的删除行（改前文案）——
/// 即「改前长什么样」是基准，「改后必须逐字相同」是断言。
///
/// ## 每例意图（A–H 对应主理人验收清单）
/// | 组 | 清单项 | 意图 |
/// |----|--------|------|
/// | A  | A 文案零变更 | 6 处弹窗的**渲染文本集**（不是源码字符串）与改前逐字一致；③ 另用源码切片兜底 |
/// | B  | B 宽度 | 金色通知卡在 390 / 834 / 1032 / 320 四档的真实渲染宽度 |
/// | C  | C null 边界 | ① 系统返回键 pop 成 null → 专注**恢复计时**（不卡 `已暂停`） |
/// | D  | D key 唯一性 | ⑤ `perkLockedHintKey` 必须 findsOneWidget（不是 2） |
/// | E  | E 明细行结构 | ② 「名称 + 右侧备注」两段式在长备注 / 小屏大字号 / 多条下是否溢出 |
/// | F  | F barrier | ①④ 点卡外不关；⑤ 默认可关（默认值未被顺手改掉） |
/// | G  | H·M6 | ② 必须是 **warn 红档**（工程师零覆盖，本组补断言） |
///
/// ## 项目铁律遵循
/// · 专注 / 护眼 / 外壳页有无限动画 → 全程**有界 `pump(Duration)`**，零 `pumpAndSettle`；
/// · 序列帧真解码会 OOM → 拦 `flutter/assets` 通道；
/// · `SystemChannels.platform` 不 mock 时 `_restoreSystemChrome()` 的 future 永不完成
///   （表现「点结束没反应」）→ 凡涉专注页退出的用例统一 mock；
/// · 核实落盘一律 `File.readAsStringSync()`（本机 bash grep 不可靠）。
library f141_qa_probe_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart' show FeatureKey;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart'
    show EyeCareResultType;
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/pages/eye_care_page.dart';
import 'package:sunflower_time/presentation/child/pages/focus_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

// ═══════════════════════════ 通用夹具 ═══════════════════════════

/// 项目根（cwd 可能是 `test/m3`）。
String _root() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/m3') || cwd.endsWith(r'\test\m3')
      ? Directory.current.parent.parent.path
      : cwd;
}

String _src(String rel) =>
    File('${_root()}/lib/presentation/$rel').readAsStringSync();

/// 取 [src] 中从 [start] 到 [end] 的一段（用于「这一处调用点」的源码切片）。
String _slice(String src, String start, String end) {
  final int a = src.indexOf(start);
  expect(a, greaterThanOrEqualTo(0), reason: '切片起点 `$start` 不存在');
  final int b = src.indexOf(end, a + start.length);
  expect(b, greaterThan(a), reason: '切片终点 `$end` 不存在');
  return src.substring(a, b);
}

/// 固定视口 + 拦资产 + mock `SystemChannels.platform`。
void _useScreen(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  double textScale = 1.0,
}) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  if (textScale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  const MethodChannel assets = MethodChannel('flutter/assets');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    assets,
    (MethodCall call) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(assets, null));
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

/// Wakelock pigeon 通道假应答（否则 `await WakelockPlus.enable()` 永不回包）。
void _installWakelockNoop(WidgetTester tester) {
  for (final String name in <String>[
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
    'wakelock_plus_macos',
  ]) {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      name,
      (ByteData? m) async => null,
    );
    addTearDown(() =>
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(name, null));
  }
}

/// 有界泵（禁 `pumpAndSettle`：页面里有无限呼吸 / 序列帧动画）。
Future<void> _pump(WidgetTester tester, {int rounds = 20}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// 收集 [scope] 子树里所有 `Text.data`（渲染层文本集，顺序无关）。
List<String> _textsIn(WidgetTester tester, Finder scope) {
  return tester
      .widgetList<Text>(
          find.descendant(of: scope, matching: find.byType(Text)))
      .map((Text t) => t.data ?? '<rich>')
      .toList();
}

/// 内容集相等（多重集合口径：顺序无关、重复计数敏感）。
void _expectTextSet(List<String> actual, List<String> expected, String why) {
  expect(actual.toSet(), expected.toSet(), reason: why);
  expect(actual.length, expected.length, reason: '$why（重复/多渲染了一句）');
}

/// 卡头圆徽的实测底色（`_GoldNoticeItemRow` 与徽标都是 Container，用图标反查）。
Color _badgeColorOf(WidgetTester tester, IconData icon) {
  final Finder container = find
      .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
      .first;
  final Container c = tester.widget<Container>(container);
  return (c.decoration! as BoxDecoration).color!;
}

// ─────────────────────── 假仓储（只防真库触库） ───────────────────────

class _FakeSunlight implements SunlightRepository {
  _FakeSunlight(this._balance);
  final double _balance;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
  @override
  Future<double> balance() async => _balance;
  @override
  Future<double> append(SunlightEntry e) async => _balance + e.net;
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
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;
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
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
}

class _FakeFocus implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession s) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
      totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

class _FakeEyeCareLog implements EyeCareLogRepository {
  final List<EyeCareLog> rows = <EyeCareLog>[];
  @override
  Future<void> append(EyeCareLog log) async => rows.add(log);
  @override
  Future<int> countByResult(EyeCareResultType type) async =>
      rows.where((EyeCareLog l) => l.result == type).length;
  @override
  Future<int> watchedSecondsByResult(EyeCareResultType type) async => rows
      .where((EyeCareLog l) => l.result == type)
      .fold<int>(0, (int s, EyeCareLog l) => s + l.watchedSeconds);
}

class _FakeSettings implements SettingsRepository {
  _FakeSettings(this.s);
  final AppSettings s;
  @override
  Future<AppSettings> getSettings() async => s;
  @override
  Future<void> saveSettings(AppSettings v) async {}
}

class _FakeTracking implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent e) async {}
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      <TrackingEvent>[];
  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

/// 可配置的被拒申请列表（② 入口用）。
class _FakeReward implements RewardRepository {
  _FakeReward(this.rejected, this._templates);
  final List<RedemptionRequest> rejected;
  final List<RewardTemplate> _templates;

  @override
  Future<List<RewardTemplate>> templates() async => _templates;
  @override
  Future<List<RedemptionRequest>> rejectedRequests() async => rejected;
  @override
  Future<List<RedemptionRequest>> verifiedRequests() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) async =>
      <RedemptionRequest>[];
  @override
  Future<void> createRequest(RedemptionRequest r) async {}
  @override
  Future<void> updateRequest(RedemptionRequest r) async {}
  @override
  Future<void> saveTemplate(RewardTemplate t) async {}
  @override
  Future<void> deleteTemplate(String id) async {}
  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod w) async => 0;
  @override
  Future<void> decrementCooldown(String templateId, CooldownPeriod w) async {}
}

const AppSettings _kSettings = AppSettings(
  ageTier: AgeTier.high,
  dailyFocusCap: 60,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 400,
  eyeCareSkipAllowed: true,
);

// ═══════════════════════════ ① 专注页退出确认 ═══════════════════════════

GoRouter _focusRouter() => GoRouter(
      initialLocation: '/focus',
      routes: <RouteBase>[
        GoRoute(
          path: '/focus',
          builder: (BuildContext c, GoRouterState s) =>
              const FocusPage(plannedMinutes: 15, dnd: false),
        ),
        GoRoute(
          path: '/settle',
          builder: (BuildContext c, GoRouterState s) =>
              SettlePage(args: s.extra as SettleArgs?),
        ),
      ],
    );

Future<void> _pumpFocus(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlight(100)),
      focusRepositoryProvider.overrideWithValue(_FakeFocus()),
      eyeCareLogRepositoryProvider.overrideWithValue(_FakeEyeCareLog()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettings(_kSettings)),
      trackingRepositoryProvider.overrideWithValue(_FakeTracking()),
      audioServiceProvider
          .overrideWithValue(AudioService(playerFactory: () => null)),
    ],
    child: MaterialApp.router(routerConfig: _focusRouter()),
  ));
  await _pump(tester);
}

/// 真入口：系统返回键 → `PopScope(canPop:false)` → `_requestExit` → 退出确认卡。
Future<void> _openExitCard(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _pump(tester);
}

// ═══════════════════════════ ④ 护眼提前结束 ═══════════════════════════

Future<void> _pumpEyeCare(
  WidgetTester tester,
  GlobalKey<NavigatorState> navKey,
  Future<Object?>? Function() onPushed,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlight(100)),
      eyeCareLogRepositoryProvider.overrideWithValue(_FakeEyeCareLog()),
    ],
    child: MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox()),
    ),
  ));
  await _pump(tester);
  onPushed();
  await _pump(tester);
}

// ═══════════════════════════ ② 孩子端外壳（拒绝通知） ═══════════════════════════

const RewardTemplate _kTpl = RewardTemplate(
  id: 'tpl_x',
  name: '小零食',
  category: RewardCategory.parentHandled,
  contentCategory: RewardContentCategory.snacks,
  baseCost: 10,
  frequencyLimitPerWeek: 7,
  cooldownRule: CooldownRule.none,
);

/// 挂真 `ChildShellPage`，用真 `AccountService`（内存库）+ 假 Rewards 驱动 ② 入口。
Future<void> _pumpShell(
  WidgetTester tester,
  List<RedemptionRequest> rejected,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  await account.createChild('验收娃', AgeTier.mid);

  final List<RedemptionRequest> mine = rejected
      .map((RedemptionRequest r) => RedemptionRequest(
            id: r.id,
            childId: account.childId,
            templateId: r.templateId,
            requestedAt: r.requestedAt,
            cost: r.cost,
            status: r.status,
            parentNote: r.parentNote,
          ))
      .toList();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(database),
        accountServiceProvider.overrideWithValue(account),
        rewardRepositoryProvider
            .overrideWithValue(_FakeReward(mine, const <RewardTemplate>[_kTpl])),
      ]),
      child: const MaterialApp(home: ChildShellPage()),
    ),
  );
  await _pump(tester, rounds: 12);
}

RedemptionRequest _rejected({required String id, String? note}) =>
    RedemptionRequest(
      id: id,
      childId: 'ignored',
      templateId: 'tpl_x',
      requestedAt: DateTime(2026, 10, 20, 9),
      cost: 10,
      status: RequestStatus.rejected,
      parentNote: note,
    );

// ═══════════════════════════ main ═══════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────── A · 文案零变更 ─────────────────────────
  group('A 文案零变更（渲染文本集 vs 改前删除行）', () {
    testWidgets('A1 ① 专注退出确认：4 句逐字（标题/正文/再坐一会/结束）',
        (WidgetTester tester) async {
      _useScreen(tester);
      _installWakelockNoop(tester);
      await _pumpFocus(tester);
      await _openExitCard(tester);

      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '① 必须走统一确认卡壳');
      _expectTextSet(
        _textsIn(tester, find.byType(ChildConfirmCard)),
        <String>[
          '确定结束吗？',
          '向日葵还在这儿陪着你，要现在结束专注吗？',
          '再坐一会',
          '结束',
        ],
        '① 四句必须与 HEAD 版 AlertDialog 逐字相同',
      );
    });

    testWidgets('A2 ④ 护眼提前结束：3 个 prd 常量逐字', (WidgetTester tester) async {
      _useScreen(tester);
      final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
      Future<Object?>? pushed;
      await _pumpEyeCare(tester, navKey, () => pushed = navKey.currentState!
          .push<Object?>(MaterialPageRoute<Object?>(
        builder: (_) => const EyeCarePage(args: EyeCareArgs(skipAllowed: true)),
      )));

      await tester.tap(find.text(kEyeCareFinishLabel));
      await _pump(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget);
      _expectTextSet(
        _textsIn(tester, find.byType(ChildConfirmCard)),
        <String>[
          kEyeCareEarlyFinishTitle,
          kEyeCareEarlyFinishConfirmText,
          kEyeCareEarlyFinishStayLabel,
          kEyeCareEarlyFinishQuitLabel,
        ],
        '④ 标题/正文/两个按钮必须仍是 prd_params 那 4 个常量',
      );
      expect(pushed, isNotNull, reason: '沙盒里护眼页已 push');
      // 不改行为：还在护眼页（未关）。
      expect(find.byType(EyeCarePage), findsOneWidget);
    });

    testWidgets('A3 ② 兑换未被通过：标题/明细/兜底串/底部说明/知道啦', (WidgetTester tester) async {
      _useScreen(tester);
      await _pumpShell(tester, <RedemptionRequest>[_rejected(id: 'r1')]);

      expect(find.byType(GoldNoticeDialog), findsOneWidget,
          reason: '② 必须走统一通知卡壳');
      _expectTextSet(
        _textsIn(tester, find.byType(GoldNoticeDialog)),
        <String>[
          '🚫 兑换未被通过',
          '· 小零食',
          '（家长拒绝了该申请）',
          '本次阳光未被扣除，可重新兑换其他奖励',
          '知道啦',
        ],
        '② 五句必须与 HEAD 版 AlertDialog 逐字相同（含 parentNote==null 兜底串）',
      );
    });

    test('A4 ③ 完美日：源码切片里三句逐字 + 无裸 AlertDialog', () {
      final String src = _src('child/pages/child_task_page.dart');
      final String body = _slice(
        src,
        'Future<void> _celebratePerfectDay()',
        'void _snack(',
      );
      expect(body.contains("showGoldNoticeDialog("), isTrue,
          reason: '③ 必须走统一通知卡壳');
      expect(body.contains("title: '🌻 今日成长项全部完成！',"), isTrue,
          reason: '标题逐字');
      expect(
          body.contains("footerText: '你今天把全部成长项都做完啦，获得「完美日」标记！',"),
          isTrue,
          reason: '正文逐字（改前在 AlertDialog.content，现落到 footerText）');
      expect(body.contains("confirmLabel: '太棒啦',"), isTrue,
          reason: '按钮逐字');
      expect(body.contains('items: const <GoldNoticeItem>[],'), isTrue,
          reason: '③ 无明细：显式空列表（走「不画悬挂分隔线」分支）');
      expect(body.contains('AlertDialog'), isFalse, reason: '③ 不得残留裸弹窗');
      expect(body.contains('Text('), isFalse,
          reason: '③ 不应自己拼 Text（文案全由卡壳渲染）');
    });

    testWidgets('A4b ③ 空条目 + 有 footer 的渲染形态（不画悬挂分隔线 / 无异常）',
        (WidgetTester tester) async {
      _useScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showGoldNoticeDialog(
                  c,
                  title: '🌻 今日成长项全部完成！',
                  items: const <GoldNoticeItem>[],
                  footerText: '你今天把全部成长项都做完啦，获得「完美日」标记！',
                  confirmLabel: '太棒啦',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(GoldNoticeDialog), findsOneWidget);
      expect(find.text('太棒啦'), findsOneWidget);
      expect(find.byType(Divider), findsNothing,
          reason: '无明细时不得留一条「无来由」的悬挂分隔线（本轮改动点）');
      final Size card =
          tester.getSize(find.byKey(GoldNoticeDialog.surfaceKey));
      expect(card.width, moreOrLessEquals(310, epsilon: 0.5),
          reason: '手机 390：卡片仍 310（零回归）');
    });

    testWidgets('A5 ⑤ 锁标提示：只剩正文 + 知道了（无标题）',
        (WidgetTester tester) async {
      _useScreen(tester);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: FocusLevelBadge(
                progress: progressOf(900),
                totalMinutes: 900,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FocusLevelBadge.badgeTapKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(1)));
      await tester.pumpAndSettle();

      _expectTextSet(
        _textsIn(tester, find.byKey(FocusLevelDetailDialog.perkLockedHintKey)),
        <String>[kPremiumUpsellHintText, kLevelDetailHintConfirmText],
        '⑤ 改前只有 content + 一个 TextButton ⇒ 文本集必须只有两句',
      );
      expect(find.text('升级解锁'), findsNothing,
          reason: '⑤ 不允许抄 ⑥ 的标题（改前没有标题）');
    });

    testWidgets('A6 ⑥ 付费引导：升级解锁 / 「X」需要一次性买断解锁。/ 稍后 / 解锁全部功能',
        (WidgetTester tester) async {
      _useScreen(tester);
      final GoRouter router = GoRouter(
        initialLocation: '/g',
        routes: <RouteBase>[
          GoRoute(
            path: '/g',
            builder: (BuildContext c, GoRouterState s) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showPremiumUpsell(c, FeatureKey.gardenPotCapacity),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/parent/premium',
            builder: (BuildContext c, GoRouterState s) =>
                const Scaffold(body: Center(child: Text('购买页'))),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      _expectTextSet(
        _textsIn(tester, find.byType(ChildConfirmCard)),
        <String>[
          '升级解锁',
          '「更多花盆」需要一次性买断解锁。',
          '稍后',
          '解锁全部功能',
        ],
        '⑥ 四句必须与 HEAD 版 AlertDialog 逐字相同',
      );
    });
  });

  // ───────────────────────── B · 金色通知卡宽度 ─────────────────────────
  group('B 金色通知卡宽度（玄参 C105 诉求）', () {
    /// 从真入口弹一张「最长」通知卡（长标题 + 1 条明细 + 合计）。
    Future<void> openCard(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showGoldNoticeDialog(
                  c,
                  title: '🎉 家长已确认你的成长任务',
                  items: const <GoldNoticeItem>[
                    GoldNoticeItem(
                      icon: Icons.task_alt,
                      name: '自己整理书包',
                      amountText: '+12 阳光',
                    ),
                  ],
                  footerText: '共获得 12 阳光',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    /// 卡宽两种量法必须一致（surfaceKey ↔ 内容滚动区），防「Key 挂错层」假绿。
    void expectCardWidth(WidgetTester tester, double want) {
      final double byKey =
          tester.getSize(find.byKey(GoldNoticeDialog.surfaceKey)).width;
      final double byScroll =
          tester.getSize(find.byType(SingleChildScrollView)).width;
      // ignore: avoid_print
      print('B-MEASURE screen=${tester.view.physicalSize.width / 3} '
          'card=$byKey scroll=$byScroll want=$want');
      expect(byKey, moreOrLessEquals(want, epsilon: 0.5),
          reason: 'surfaceKey 量得卡宽应为 $want');
      expect(byScroll, moreOrLessEquals(want, epsilon: 0.5),
          reason: '内容区宽度应与卡宽一致（$want）');
    }

    testWidgets('B1 手机 390×844 → 310（= 390 − inset 80，零回归）',
        (WidgetTester tester) async {
      _useScreen(tester);
      await openCard(tester);
      expectCardWidth(tester, 310);
      expect(tester.takeException(), isNull);
    });

    testWidgets('B2 iPad 11″ 834×1194 → 442（= 340 × 1.3）', (WidgetTester tester) async {
      _useScreen(tester, width: 834, height: 1194);
      await openCard(tester);
      // 834 − 80 = 754 可用，上界 442 生效。
      expectCardWidth(tester, 442);
      expect(tester.takeException(), isNull);
    });

    testWidgets('B3 iPad 13″ 1032×1376 → 544（= 340 × 1.6）且 < 952（改前）',
        (WidgetTester tester) async {
      _useScreen(tester, width: 1032, height: 1376);
      await openCard(tester);
      expectCardWidth(tester, 544);
      expect(tester.getSize(find.byKey(GoldNoticeDialog.surfaceKey)).width,
          lessThan(952),
          reason: '改前 = 1032 − 80 = 952（几乎铺满屏），玄参判「太宽」');
      expect(tester.takeException(), isNull);
    });

    testWidgets('B4 小屏 320×568 → 240（= 320 − 80），零溢出（工程师完全没提这档）',
        (WidgetTester tester) async {
      _useScreen(tester, width: 320, height: 568);
      await openCard(tester);
      expectCardWidth(tester, 240);
      expect(tester.takeException(), isNull, reason: '320 小屏不得溢出');
    });
  });

  // ───────────────────────── C · ① 的 null 边界 ─────────────────────────
  group('C ① 系统返回键 → null 必须恢复计时（不卡「已暂停」）', () {
    testWidgets('C1 返回键关卡后：已暂停消失 + 再次返回能重弹', (WidgetTester tester) async {
      _useScreen(tester);
      _installWakelockNoop(tester);
      await _pumpFocus(tester);

      await _openExitCard(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget);
      expect(find.text('已暂停'), findsOneWidget,
          reason: '前置：退出确认期间处于 paused 遮罩');

      // 系统返回键：barrierDismissible:false 挡不住它 → 对话框 pop(null)。
      await tester.binding.handlePopRoute();
      await _pump(tester);

      expect(find.byType(ChildConfirmCard), findsNothing, reason: '返回键关掉卡片');
      expect(find.text('已暂停'), findsNothing,
          reason: 'null 分支必须走 _resume()：paused 遮罩消失（改前会永久留着）');
      expect(find.byType(FocusPage), findsOneWidget, reason: '没有误退出专注');

      // 能再次触发 = `_paused` 真的复位了（否则 `_requestExit` 被 `_paused` 闸门挡掉）。
      await _openExitCard(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '第二个返回键仍能弹出退出确认');
      expect(find.text('已暂停'), findsOneWidget);
    });

    testWidgets('C2 「结束」仍进结算、「再坐一会」不进（行为零变更）',
        (WidgetTester tester) async {
      _useScreen(tester);
      _installWakelockNoop(tester);
      await _pumpFocus(tester);

      await _openExitCard(tester);
      await tester.tap(find.text('再坐一会'));
      await _pump(tester);
      expect(find.byType(SettlePage), findsNothing, reason: '取消绝不进结算');
      expect(find.text('已暂停'), findsNothing);

      await _openExitCard(tester);
      await tester.tap(find.text('结束'));
      for (int i = 0; i < 80; i++) {
        if (find.byType(SettlePage).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SettlePage), findsOneWidget,
          reason: '确认结束 → 引擎 finished → 结算（副作用时机不变）');
    });
  });

  // ───────────────────────── D · ⑤ key 唯一性 ─────────────────────────
  group('D ⑤ perkLockedHintKey 必须恰好 1 个', () {
    testWidgets('D1 在场 findsOneWidget / 关闭后双双 findsNothing',
        (WidgetTester tester) async {
      _useScreen(tester);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: FocusLevelBadge(
                progress: progressOf(900),
                totalMinutes: 900,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FocusLevelBadge.badgeTapKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(1)));
      await tester.pumpAndSettle();

      expect(find.byKey(FocusLevelDetailDialog.perkLockedHintKey),
          findsOneWidget,
          reason: 'Key 必须只挂一层（下传到内部 Dialog 会变 findsNWidgets(2)）');
      expect(find.text(kPremiumUpsellHintText), findsOneWidget);
      // 详情卡仍在（V3-Q1：只提示、不 pop）。
      expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget);

      await tester.tap(find.text(kLevelDetailHintConfirmText));
      await tester.pumpAndSettle();
      expect(find.byKey(FocusLevelDetailDialog.perkLockedHintKey), findsNothing);
      expect(find.text(kPremiumUpsellHintText), findsNothing);
      expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget);
    });
  });

  // ───────────────────────── E · ② 明细行结构变化 ─────────────────────────
  group('E ② 「名称 + 右侧备注」两段式排版', () {
    testWidgets('E1 兜底串在 parentNote == null 时出现', (WidgetTester tester) async {
      _useScreen(tester);
      await _pumpShell(tester, <RedemptionRequest>[_rejected(id: 'r1')]);
      expect(find.text('（家长拒绝了该申请）'), findsOneWidget);
      expect(find.textContaining('家长拒绝了该申请'), findsOneWidget);
    });

    testWidgets('E2 长家长备注（24 字）在手机 390 不溢出，且备注右缘不越卡',
        (WidgetTester tester) async {
      _useScreen(tester);
      const String note = '这个奖励本周已经兑换过了，先攒着阳光下周再来找我哦';
      await _pumpShell(tester, <RedemptionRequest>[
        _rejected(id: 'r1', note: note),
      ]);

      expect(tester.takeException(), isNull,
          reason: '长备注不得触发 RenderFlex overflow（改前是一整句可折行 Text）');
      final Rect card =
          tester.getRect(find.byKey(GoldNoticeDialog.surfaceKey));
      final Rect amount = tester.getRect(find.text('（$note）'));
      expect(amount.right, lessThanOrEqualTo(card.right + 0.5),
          reason: '备注右缘不得越出卡片（实测 ${amount.right} vs ${card.right}）');
      expect(amount.left, greaterThanOrEqualTo(card.left - 0.5));
    });

    testWidgets('E3 3 条明细 + 320×568 + 字号 1.3 → 零异常、卡高 ≤ 0.7 屏、可滚动',
        (WidgetTester tester) async {
      _useScreen(tester, width: 320, height: 568, textScale: 1.3);
      const String longNote = '家长这次没有通过，你先把作业写完再来兑换吧';
      await _pumpShell(tester, <RedemptionRequest>[
        _rejected(id: 'r1', note: longNote),
        _rejected(id: 'r2', note: longNote),
        _rejected(id: 'r3', note: longNote),
      ]);

      expect(tester.takeException(), isNull,
          reason: '320 小屏 + 1.3 倍字号下 3 条明细不得溢出（F126 老坑位）');
      final Size card =
          tester.getSize(find.byKey(GoldNoticeDialog.surfaceKey));
      expect(card.width, moreOrLessEquals(240, epsilon: 0.5));
      expect(card.height, lessThanOrEqualTo(568 * 0.7 + 0.5),
          reason: '卡高受 maxHeightRatio(0.7) 约束，超出走卡内滚动');
      final ScrollPosition pos = tester
          .state<ScrollableState>(find
              .descendant(
                of: find.byKey(GoldNoticeDialog.surfaceKey),
                matching: find.byType(Scrollable),
              )
              .first)
          .position;
      expect(pos.maxScrollExtent, greaterThan(0),
          reason: '内容超高时必须能在卡内滚动（否则就是被裁掉）');
    });

    // 🔴 F141-BUG-01（QA 独立探针发现）：② 的明细行从「一整句可折行 Text」
    // 改成「名称 Expanded + 右侧无约束 Text」后，右侧备注**不参与折行/收缩**
    // → 只要备注偏长（或小屏 + 大字号下连兜底串都偏长），Row 就 RenderFlex 溢出。
    // 下面 E4/E5 用的**不是**造出来的长备注，而是 parentNote == null 的生产兜底串
    // 「（家长拒绝了该申请）」—— 即**当前代码路径上真实会发生**的文案。
    for (final (double scale, String tag) in <(double, String)>[
      (1.0, '1.0 倍字号'),
      (1.3, '1.3 倍字号'),
    ]) {
      testWidgets('E4/E5 兜底串在 320×568 + $tag 不溢出（生产可达路径）',
          (WidgetTester tester) async {
        _useScreen(tester, width: 320, height: 568, textScale: scale);
        await _pumpShell(tester, <RedemptionRequest>[_rejected(id: 'r1')]);
        expect(find.text('（家长拒绝了该申请）'), findsOneWidget,
            reason: '前置：兜底串确实渲染出来了');
        expect(tester.takeException(), isNull,
            reason: '320 小屏（$tag）下②的明细行不得溢出');
      });
    }

    testWidgets('E6 手机 390 兜底串时名称列剩余宽度（记录值，防继续恶化）',
        (WidgetTester tester) async {
      _useScreen(tester);
      await _pumpShell(tester, <RedemptionRequest>[_rejected(id: 'r1')]);
      final double nameW = tester.getSize(find.text('· 小零食')).width;
      final double amountW = tester.getSize(find.text('（家长拒绝了该申请）')).width;
      final double contentW =
          tester.getSize(find.byKey(GoldNoticeDialog.surfaceKey)).width - 40;
      // 记录实测值，只防「名称被挤到 1 个字宽」这种极端。
      // ignore: avoid_print
      print('E6-MEASURE name=$nameW amount=$amountW content=$contentW');
      expect(nameW, greaterThan(0));
      expect(amountW + 34 + 10, lessThan(contentW + 0.5),
          reason: '390 上兜底串 + 图标块必须仍留得出名称空间'
              '（实测 name=$nameW amount=$amountW content=$contentW）');
    });
  });

  // ───────────────────────── F · barrierDismissible 语义 ─────────────────────────
  group('F barrierDismissible', () {
    testWidgets('F1 ① 点卡外（5,5）卡片仍在场', (WidgetTester tester) async {
      _useScreen(tester);
      _installWakelockNoop(tester);
      await _pumpFocus(tester);
      await _openExitCard(tester);

      await tester.tapAt(const Offset(5, 5));
      await _pump(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '① 必须逐字透传 barrierDismissible: false');
      expect(find.text('已暂停'), findsOneWidget);
    });

    testWidgets('F2 ④ 点卡外卡片仍在场', (WidgetTester tester) async {
      _useScreen(tester);
      final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
      Future<Object?>? pushed;
      await _pumpEyeCare(tester, navKey, () => pushed = navKey.currentState!
          .push<Object?>(MaterialPageRoute<Object?>(
        builder: (_) => const EyeCarePage(args: EyeCareArgs(skipAllowed: true)),
      )));
      expect(pushed, isNotNull, reason: '前置：护眼页已 push 进来');
      await _pump(tester);

      await tester.tap(find.text(kEyeCareFinishLabel));
      await _pump(tester);

      await tester.tapAt(const Offset(5, 5));
      await _pump(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '④ 必须逐字透传 barrierDismissible: false');
    });

    testWidgets('F3 ⑤ 通知卡默认可关（默认 true 未被顺手改成 false）',
        (WidgetTester tester) async {
      _useScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showGoldNoticeDialog(
                  c,
                  title: '🎉 家长已确认你的兑换',
                  items: const <GoldNoticeItem>[
                    GoldNoticeItem(
                        icon: Icons.redeem, name: '小零食', amountText: '-10 阳光'),
                  ],
                  footerText: '共扣除 10 阳光',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(GoldNoticeDialog), findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(GoldNoticeDialog), findsNothing,
          reason: '既有两处通知卡（兑换核销 / 任务审批）原本点卡外可关，不得回归');
    });
  });

  // ───────────────────────── G · ② 必须是 warn 红档（M6 覆盖） ─────────────────────────
  group('G ② 语气档位（工程师零覆盖，本组补断言）', () {
    testWidgets('G1 ② 徽标 / 按钮底色 = warnBadge 红，不是金',
        (WidgetTester tester) async {
      _useScreen(tester);
      await _pumpShell(tester, <RedemptionRequest>[_rejected(id: 'r1')]);

      expect(_badgeColorOf(tester, Icons.block), GoldNoticeStyle.warnBadge,
          reason: '「被拒绝」不能用金色奖杯庆祝语义（tone: NoticeTone.warn）');
      // 按钮前景必须是白（红底白字），而不是金档的深棕。
      final FilledButton btn = tester.widget<FilledButton>(find.descendant(
        of: find.byType(GoldNoticeDialog),
        matching: find.byType(FilledButton),
      ));
      expect(btn.style!.foregroundColor!.resolve(<WidgetState>{}), Colors.white,
          reason: 'warn 档按钮 = 红底白字');
      expect(btn.style!.backgroundColor!.resolve(<WidgetState>{}),
          GoldNoticeStyle.warnBadge);

      // 家长备注必须「弱化」：非加粗 + amountMuted 深金（不抢「拒绝」的视觉）。
      final Text amount = tester.widget<Text>(find.text('（家长拒绝了该申请）'));
      expect(amount.style!.color, GoldNoticeStyle.amountMuted,
          reason: '② 明细备注用 amountMuted 深金，不是亮金金额色');
      expect(amount.style!.fontWeight, FontWeight.w500,
          reason: '② 明细备注非加粗（amountMuted: true）');
    });

    testWidgets('G2 对照组：默认 gold 档徽标仍是金色（tone 分档确实生效）',
        (WidgetTester tester) async {
      _useScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showGoldNoticeDialog(
                  c,
                  title: '🎉 家长已确认你的兑换',
                  items: const <GoldNoticeItem>[
                    GoldNoticeItem(
                        icon: Icons.redeem, name: '小零食', amountText: '-10 阳光'),
                  ],
                  footerText: '共扣除 10 阳光',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(_badgeColorOf(tester, Icons.emoji_events), GoldNoticeStyle.gold);
    });
  });
}
