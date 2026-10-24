/// 家长赠予到账提醒 · 孩子端金色卡 widget 测试（F150，2026-10-23）。
///
/// 玄参反馈：家长赠了阳光，孩子端无感（只有余额静默刷新）。修复后口径：
///  · 检查时机**只有两处** —— 外壳首帧后 + 家长天地 pop 回孩子端（RouteAware
///    didPopNext）；**绝不挂 economyRevision 监听**（家长仍在家长端操作时弹卡
///    会挡住家长）。
///  · 判据 = `parent_gift` 最新一条记录 id vs SP 已读键（按孩子分键）。
///
/// 宿主与 fake 集同 `test/m4/child_shell_app_cap_test.dart`（有界 pump 纪律）。
library parent_gift_notice_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/shared/child_route_observer.dart';

/// 有界 pump（shell 测试禁 pumpAndSettle：无限漂动/呼吸动画，C44e 纪律）。
Future<void> _pumpFrames(WidgetTester tester,
    {int frames = 14, int stepMs = 100}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(Duration(milliseconds: stepMs));
  }
}

const AppSettings _settings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 60,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

SunlightEntry _gift(String id, {double net = 12.0}) => SunlightEntry(
      id: id,
      ts: DateTime(2026, 10, 23, 12),
      type: SunlightType.earn,
      gross: net,
      net: net,
      balanceAfter: net,
      refType: 'parent_gift',
      refId: null,
      dayKey: '2026-10-23',
    );

/// 账本 fake：`latest` 可变（模拟「家长在家长端又赠了一笔」）。
class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository({this.latest});
  SunlightEntry? latest;
  int latestReadCount = 0;

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async {
    latestReadCount++;
    return latest;
  }

  @override
  Future<double> append(SunlightEntry entry) async => 999.0;
  @override
  Future<double> balance() async => 999.0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
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
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings;
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeFocusRepository implements FocusRepository {
  @override
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0,
          totalValidDays: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakeTaskRepository implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakePlantRepository implements PlantRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakeRewardRepository implements RewardRepository {
  @override
  Future<List<RewardTemplate>> templates() async => <RewardTemplate>[];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakeTrackingRepository implements TrackingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakeWeeklyPoolRepository implements WeeklyPoolRepository {
  @override
  Future<WeeklyPool?> get(String weekKey) async => null;
  @override
  Future<void> upsert(WeeklyPool pool) async {}
  @override
  List<String> weeksBetween(String fromKey, String toKey) =>
      const <String>[];
}

List<Override> _overrides(
  SharedPreferences prefs, {
  required SunlightRepository sunlight,
}) =>
    <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      sunlightRepositoryProvider.overrideWithValue(sunlight),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      rewardRepositoryProvider.overrideWithValue(_FakeRewardRepository()),
      trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
      weeklyPoolRepositoryProvider
          .overrideWithValue(_FakeWeeklyPoolRepository()),
    ];

/// 是否弹着「家长赠予」金色卡（标题被本测试钉死，文案在 ARB）。
Finder _giftCard() => find.textContaining('爸爸妈妈送来阳光啦');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('未读赠予 → 外壳首帧即弹金色卡（标题 + 金额 + 知道啦）',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final _FakeSunlightRepository ledger =
        _FakeSunlightRepository(latest: _gift('gift-1'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(prefs, sunlight: ledger),
        child: const MaterialApp(home: ChildShellPage()),
      ),
    );
    await _pumpFrames(tester);

    expect(_giftCard(), findsOneWidget, reason: '首帧后应弹赠予到账卡');
    expect(find.text('+12'), findsOneWidget,
        reason: '金额槽位只放金额（C105）');
    expect(find.text('知道啦'), findsOneWidget);
  });

  testWidgets('点「知道啦」写已读 → 重建外壳不再弹（去重）',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final _FakeSunlightRepository ledger =
        _FakeSunlightRepository(latest: _gift('gift-1'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(prefs, sunlight: ledger),
        child: const MaterialApp(home: ChildShellPage()),
      ),
    );
    await _pumpFrames(tester);
    expect(_giftCard(), findsOneWidget);

    await tester.tap(find.text('知道啦'));
    await _pumpFrames(tester);
    expect(_giftCard(), findsNothing);

    // 重建外壳（模拟重新进入孩子端）：已读键生效，绝不重弹。
    // 🔴 必须换 key 强制新建 element —— pumpWidget 树形相同会复用 element，
    // initState（含首帧检查）不会跑，「不重弹」会变假绿。
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey<String>('shell-rebuild-1'),
        overrides: _overrides(prefs, sunlight: ledger),
        child: MaterialApp(
          home: ChildShellPage(key: UniqueKey()),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(_giftCard(), findsNothing, reason: '已读 id 去重，不重复打扰');
    expect(ledger.latestReadCount, greaterThan(1),
        reason: '接线守：重建后首帧检查必须真的跑过（防 element 复用假绿）');
  });

  testWidgets('🔴 economyRevision 自增（家长端操作路径）绝不弹赠予卡',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final _FakeSunlightRepository ledger =
        _FakeSunlightRepository(latest: _gift('gift-1'));

    late final ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(prefs, sunlight: ledger),
        child: const MaterialApp(home: ChildShellPage()),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(ChildShellPage)),
    );
    await _pumpFrames(tester);
    expect(_giftCard(), findsOneWidget);
    await tester.tap(find.text('知道啦'));
    await _pumpFrames(tester);

    // 家长在家长端又赠一笔 → revision++（shell listener 触发既有三卡检查）。
    ledger.latest = _gift('gift-2', net: 20);
    container.read(economyRevisionProvider.notifier).state++;
    await _pumpFrames(tester);
    expect(_giftCard(), findsNothing,
        reason: '修订号路径不查赠予卡 —— 家长还在家长端时弹卡会挡住家长');

    // 家长退出（模拟 pop 回孩子端：RouteAware didPopNext）→ 此时才弹。
    // 🔴 换 key 强制新建 element（同上：树形相同会复用 element，首帧检查不跑）。
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey<String>('shell-rebuild-2'),
        overrides: _overrides(prefs, sunlight: ledger),
        child: MaterialApp(
          home: ChildShellPage(key: UniqueKey()),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(_giftCard(), findsOneWidget, reason: '回到台前的下一次检查应弹新赠予');
    expect(find.text('+20'), findsOneWidget);
  });

  testWidgets('didPopNext：家长天地 pop 回孩子端 → 弹未读赠予卡',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final _FakeSunlightRepository ledger = _FakeSunlightRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(prefs, sunlight: ledger),
        // 🔴 navigatorObservers 必须挂全局 childShellRouteObserver ——
        // 真实 App 由 GoRouter(observers:) 注册，这里用 MaterialApp 等价宿主。
        child: MaterialApp(
          navigatorObservers: [childShellRouteObserver],
          home: const ChildShellPage(),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(_giftCard(), findsNothing, reason: '无未读赠予，首帧无卡');

    // 孩子被切到家长端（push 覆盖），期间家长赠予一笔。
    final BuildContext ctx = tester.element(find.byType(ChildShellPage));
    // ignore: unawaited_futures
    Navigator.of(ctx).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('家长天地')),
        body: const SizedBox.expand(),
      ),
    ));
    await _pumpFrames(tester);

    ledger.latest = _gift('gift-9', net: 8);

    // 家长退出 → pop 回孩子端 → didPopNext 检查 → 弹卡。
    await tester.pageBack();
    await _pumpFrames(tester);

    expect(_giftCard(), findsOneWidget,
        reason: 'pop 回台前的 didPopNext 是赠予卡的第二触发点');
    expect(find.text('+8'), findsOneWidget);
  });
}
