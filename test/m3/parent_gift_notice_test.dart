/// 家长赠予到账提醒 · 孩子端金色卡 widget 测试（F150，2026-10-23）。
///
/// 玄参反馈：家长赠了阳光，孩子端无感（只有余额静默刷新）。修复后口径：
///  · 检查时机**只有两处** —— 外壳首帧后 + 家长天地 pop 回孩子端（RouteAware
///    didPopNext）；**绝不挂 economyRevision 监听**（家长仍在家长端操作时弹卡
///    会挡住家长）。
///  · 判据（🔴 F202 2026-11-14 改版）：`ts > 已读水位` 的**全部** `parent_gift`
///    记录逐笔一行（旧「最新一条 id」口径会把前一笔未读吞掉 —— 玄参实证：
///    先赠 5 再赠 10 只弹 10）。旧单 id 键在首跑时迁移成水位（宁少弹不误弹）。
///
/// 宿主与 fake 集同 `test/m4/child_shell_app_cap_test.dart`（有界 pump 纪律）。
library parent_gift_notice_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart'
    show kChildIdDefault;
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

SunlightEntry _gift(String id, {double net = 12.0, DateTime? ts}) => SunlightEntry(
      id: id,
      ts: ts ?? DateTime(2026, 10, 23, 12),
      type: SunlightType.earn,
      gross: net,
      net: net,
      balanceAfter: net,
      refType: 'parent_gift',
      refId: null,
      dayKey: '2026-10-23',
    );

/// 账本 fake：`gifts` 可变（模拟「家长在家长端又赠了一笔」）。
/// 🔴 F202：壳层判据走 `all()` 过滤 parent_gift，fake 以 [gifts] 供数。
class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository({List<SunlightEntry>? gifts})
      : gifts = gifts ?? <SunlightEntry>[];
  final List<SunlightEntry> gifts;
  int allReadCount = 0;

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async {
    // F202 后壳层不再走 latestByRefType；保留实现供其它调用方兜底。
    final List<SunlightEntry> hits = gifts
        .where((SunlightEntry e) => e.refType == refType)
        .toList();
    return hits.isEmpty ? null : hits.last;
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
  Future<List<SunlightEntry>> all() async {
    allReadCount++;
    return List<SunlightEntry>.from(gifts);
  }
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
        _FakeSunlightRepository(gifts: <SunlightEntry>[_gift('gift-1')]);

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
        _FakeSunlightRepository(gifts: <SunlightEntry>[_gift('gift-1')]);

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

    // 重建外壳（模拟重新进入孩子端）：已读水位生效，绝不重弹。
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
    expect(_giftCard(), findsNothing, reason: '已读水位去重，不重复打扰');
    expect(ledger.allReadCount, greaterThan(1),
        reason: '接线守：重建后首帧检查必须真的跑过（防 element 复用假绿）');
  });

  testWidgets('🔴 economyRevision 自增（家长端操作路径）绝不弹赠予卡',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final _FakeSunlightRepository ledger =
        _FakeSunlightRepository(gifts: <SunlightEntry>[_gift('gift-1')]);

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
    // 🔴 F202：新笔 ts 必须晚于已读水位（同毫秒会被 `>` 判定吞掉 —— 真实操作
    //    也不可能同毫秒连赠两笔）。
    ledger.gifts.add(_gift('gift-2', net: 20,
        ts: DateTime(2026, 10, 23, 12, 5)));
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

    ledger.gifts.add(_gift('gift-9', net: 8,
        ts: DateTime(2026, 10, 23, 12, 5)));

    // 家长退出 → pop 回孩子端 → didPopNext 检查 → 弹卡。
    await tester.pageBack();
    await _pumpFrames(tester);

    expect(_giftCard(), findsOneWidget,
        reason: 'pop 回台前的 didPopNext 是赠予卡的第二触发点');
    expect(find.text('+8'), findsOneWidget);
  });

  testWidgets('🔴 F202：连赠两笔（5 + 10）未读 → 一张卡逐笔两行，5 不再被吞',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // 玄参真机实证的场景：先赠 5、紧接着赠 10，孩子端首次回前台时两笔都未读。
    final _FakeSunlightRepository ledger = _FakeSunlightRepository(gifts:
        <SunlightEntry>[
      _gift('gift-5', net: 5, ts: DateTime(2026, 10, 23, 12)),
      _gift('gift-10', net: 10, ts: DateTime(2026, 10, 23, 12, 5)),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(prefs, sunlight: ledger),
        child: const MaterialApp(home: ChildShellPage()),
      ),
    );
    await _pumpFrames(tester);

    expect(_giftCard(), findsOneWidget, reason: '一张卡承载全部未读');
    expect(find.text('+5'), findsOneWidget, reason: '旧口径下 5 会被 10 吞掉');
    expect(find.text('+10'), findsOneWidget, reason: '两笔逐笔两行');

    // 确认后重建外壳：水位已推进到最新一笔 ⇒ 不再弹。
    await tester.tap(find.text('知道啦'));
    await _pumpFrames(tester);
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey<String>('shell-rebuild-f202'),
        overrides: _overrides(prefs, sunlight: ledger),
        child: MaterialApp(
          home: ChildShellPage(key: UniqueKey()),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(_giftCard(), findsNothing, reason: '水位已覆盖两笔，不重复打扰');
  });

  testWidgets('🔴 F202：旧「单 id 已读」键迁移 —— 旧 id 之前的赠予不重弹',
      (WidgetTester tester) async {
    // 升级用户：旧版已 ack 到 gift-1（@12:00），账本里还有更早的 gift-0 与
    // 更新的 gift-2。首跑新口径：水位 = gift-1.ts ⇒ 只弹更新的 gift-2，
    // 历史（gift-0）不重弹（少弹优于误弹）。
    SharedPreferences.setMockInitialValues(<String, Object>{
      ackedParentGiftIdKey(kChildIdDefault): 'gift-1',
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final _FakeSunlightRepository ledger = _FakeSunlightRepository(gifts:
        <SunlightEntry>[
      _gift('gift-0', net: 3, ts: DateTime(2026, 10, 23, 11)),
      _gift('gift-1', net: 12, ts: DateTime(2026, 10, 23, 12)),
      _gift('gift-2', net: 20, ts: DateTime(2026, 10, 23, 12, 5)),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(prefs, sunlight: ledger),
        child: const MaterialApp(home: ChildShellPage()),
      ),
    );
    await _pumpFrames(tester);

    expect(_giftCard(), findsOneWidget);
    expect(find.text('+20'), findsOneWidget,
        reason: '只弹水位之后的新笔');
    expect(find.text('+3'), findsNothing, reason: '旧 ack 之前的历史不重弹');
    expect(find.text('+12'), findsNothing,
        reason: '旧 ack 指向的那一笔视为已读');
  });
}
