/// 调试面板「清除会员票据」+「大招能量」按钮行为级回归。
///
/// 钉死：点击后 ① 真实安全区三键被清空（MethodChannel 假后端可观侧效应）；
/// ② UI 层快照与领域层内存态**同时**回 free（F142 两个内存源）；
/// ③ 面板内有可见回执（C62 不静默失败）；④ 大招能量按钮走真实
/// `GuardUltimateService`：+1 格 → 1、充满 → 2（钳满格、零头归 0）。
library entitlement_ticket_clear_debug_test;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/entitlement_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/data/local/secure_entitlement_store.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart'
    show UltimateEnergy;
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart'
    show MatrixEntitlementService;
import 'package:sunflower_time/domain/services/guard_ultimate_service.dart'
    show GuardUltimateService;
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/repositories/guard_ultimate_energy_store.dart'
    show GuardUltimateEnergyStore;
import 'package:sunflower_time/presentation/child/state/guard_debug_script.dart'
    show kDebugUltimateFillKey, kDebugUltimateGrantCellKey;
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';

import '../helpers/no_hit_random.dart';

const MethodChannel _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

Plant _sprout() {
  final DateTime now = DateTime.now();
  return Plant(
    id: 'p1',
    speciesId: _sunflower.id,
    potIndex: 0,
    stage: PlantStage.sprout,
    stageStartedAt: now.subtract(const Duration(hours: 2)),
    growthProgress: 0.3,
    growthFactor: 1.0,
    status: PlantStatus.growing,
    plantedAt: now.subtract(const Duration(hours: 2)),
    lastWaterAt: now,
  );
}

class _Settings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 4,
      );
  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _Ledger implements SunlightRepository {
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
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}

class _Focus implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _Plants implements PlantRepository {
  _Plants(this._plants);
  final List<Plant> _plants;

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(_plants);
  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in _plants) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    _plants.removeWhere((Plant p) => p.id == plant.id);
    _plants.add(plant);
  }

  @override
  Future<void> deletePlant(String id) async =>
      _plants.removeWhere((Plant p) => p.id == id);
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

class _Pots implements PotDisturbanceRepository {
  @override
  Future<List<PotDisturbance>> disturbances() async =>
      const <PotDisturbance>[];
  @override
  Future<PotDisturbance?> disturbanceOf(int potIndex) async => null;
  @override
  Future<void> save(PotDisturbance disturbance) async {}
  @override
  Future<void> deletePot(int potIndex) async {}
  @override
  Future<void> deleteAll() async {}
}

/// 大招能量内存存储（真实 [GuardUltimateService] 直接读写它，副作用可断言）。
class _UltimateStore implements GuardUltimateEnergyStore {
  final Map<String, List<String>> _ids = <String, List<String>>{};

  /// 单孩子模型：忽略 childId，最后一个写即当前态。
  Object? lastWritten;

  @override
  Future<UltimateEnergy> read(String childId) async {
    final Object? raw = lastWritten;
    if (raw is UltimateEnergy) return raw;
    return UltimateEnergy.empty;
  }

  @override
  Future<void> write(String childId, UltimateEnergy energy) async {
    lastWritten = energy;
  }

  @override
  Future<Set<String>> readCreditedSessionIds(String childId) async =>
      Set<String>.of(_ids[childId] ?? const <String>[]);

  @override
  Future<void> writeCreditedSessionIds(String childId, Set<String> ids) async {
    _ids[childId] = List<String>.of(ids);
  }
}

/// 面板宿主所需的最小 Provider 装配（与 `guard_debug_panel_test` 同款）。
class _Harness {
  final _Settings settings = _Settings();
  final _Ledger ledger = _Ledger();
  final _Focus focus = _Focus();
  late final _Plants plants = _Plants(<Plant>[_sprout()]);

  /// 大招能量：真实服务 + 内存存储（childId 固定，便于断言）。
  final _UltimateStore ultimateStore = _UltimateStore();
  late final GuardUltimateService ultimateService = GuardUltimateService(
    store: ultimateStore,
    childId: () => 'child-debug-test',
  );

  ProviderContainer container({List<Override> extra = const <Override>[]}) {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        accountServiceProvider.overrideWithValue(AccountService()),
        settingsRepositoryProvider.overrideWithValue(settings),
        sunlightRepositoryProvider.overrideWithValue(ledger),
        focusRepositoryProvider.overrideWithValue(focus),
        plantRepositoryProvider.overrideWithValue(plants),
        bloomRewardRepositoryProvider
            .overrideWithValue(InMemoryBloomRewardRepository()),
        potDisturbanceRepositoryProvider.overrideWithValue(_Pots()),
        guardUltimateServiceProvider.overrideWithValue(ultimateService),
        plantGrowthServiceProvider.overrideWith((Ref ref) => PlantGrowthService(
              plants: ref.watch(plantRepositoryProvider),
              focus: ref.watch(focusRepositoryProvider),
              ledger: ref.watch(sunlightRepositoryProvider),
              settings: ref.watch(settingsRepositoryProvider),
              bloomRewards: ref.watch(bloomRewardRepositoryProvider),
              weedRandom: NoHitRandom(),
            )),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    return c;
  }
}

/// 有界帧推进（面板自身无无限动画）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 200,
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(const Duration(milliseconds: 16));
  }
  return ready();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Map<String, String> keychain = <String, String>{};

  setUp(() {
    keychain.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (MethodCall call) async {
      final Map<dynamic, dynamic> args = call.arguments is Map
          ? call.arguments as Map<dynamic, dynamic>
          : <dynamic, dynamic>{};
      switch (call.method) {
        case 'read':
          return keychain[args['key'] as String];
        case 'write':
          keychain[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          keychain.remove(args['key'] as String);
          return null;
        case 'containsKey':
          return keychain.containsKey(args['key'] as String);
        case 'readAll':
          return Map<String, String>.of(keychain);
        default:
          return null;
      }
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureChannel, null));

  testWidgets('点「清除会员票据」→ 三键清空 + 两个内存源回 free + 有回执',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 真实票据落库（含合法 productId）+ 真实仓储/服务，确保点击走完整链路。
    final SecureEntitlementStore store = SecureEntitlementStore();
    await store.writeTicket(
      productId: kIapProductIdLifetime,
      jws: 'jws.header.payload.signature',
      acquiredAt: DateTime(2026, 10, 30),
    );
    final EntitlementLocalRepository repo = EntitlementLocalRepository(store);
    final MatrixEntitlementService service =
        MatrixEntitlementService(repository: repo);
    await service.load();
    expect(service.current.isPremium, isTrue, reason: '前置：票据读成会员');
    expect(keychain.length, 3, reason: '前置：三键齐全');

    final ProviderContainer c = _Harness().container(extra: <Override>[
      entitlementRepositoryProvider.overrideWithValue(repo),
      entitlementServiceProvider.overrideWithValue(service),
    ]);
    // 打开调试「会员模式」，验证清除按钮会连调试覆盖一起关掉。
    debugSetPremiumUnlockIn(c, true);
    expect(c.read(entitlementProvider).isPremium, isTrue);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: BloomDebugSheet(maxHeight: 640)),
      ),
    ));
    final bool ready = await _pumpUntil(
      tester,
      () => find.text('催熟到成株').evaluate().isNotEmpty,
    );
    expect(ready, isTrue, reason: '面板应完成 _refresh');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>(kDebugClearEntitlementTicketKey)),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>(kDebugClearEntitlementTicketKey)));

    final bool feedbackShown = await _pumpUntil(
      tester,
      () => find.textContaining('会员票据已清除').evaluate().isNotEmpty,
    );
    expect(feedbackShown, isTrue, reason: 'C62：点击后必须有面板内可见回执');

    expect(keychain, isEmpty, reason: '三键必须真的删掉');
    expect(c.read(entitlementProvider).tier, EntitlementTier.free,
        reason: 'UI 层快照立刻回免费档');
    expect(service.current.tier, EntitlementTier.free,
        reason: '领域层内存态同步回免费档（F142 两源一致）');
    expect(c.read(debugPremiumUnlockProvider), isFalse,
        reason: '调试会员模式一并关闭');
  });

  testWidgets('点「大招能量 +1 格」⇒ 能量 1 格；点「大招能量充满」⇒ 2 格',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    final ProviderContainer c = h.container();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: BloomDebugSheet(maxHeight: 640)),
      ),
    ));
    final bool ready = await _pumpUntil(
      tester,
      () => find.text('催熟到成株').evaluate().isNotEmpty,
    );
    expect(ready, isTrue, reason: '面板应完成 _refresh');

    // ── 点「+1 格」─────────────────────────────────────────────────────
    await tester.scrollUntilVisible(
      find.byKey(const Key(kDebugUltimateGrantCellKey)),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key(kDebugUltimateGrantCellKey)));

    final bool oneCellShown = await _pumpUntil(
      tester,
      () => find.textContaining('当前能量：1/2').evaluate().isNotEmpty,
    );
    expect(oneCellShown, isTrue, reason: '常显行必须当帧反映 +1（服务 emit）');
    expect(find.textContaining('已加 1 格'), findsOneWidget,
        reason: 'C62：点了必须有面板内可见回执');
    final UltimateEnergy afterOne = await h.ultimateService.read();
    expect(afterOne.filledCells, 1, reason: '真实服务必须真的写库 +1');
    expect(afterOne.fractionMin, 0, reason: '加格时零头清零（grantCellForDebug 口径）');

    // ── 点「充满」→ 钳到 2 格 ─────────────────────────────────────────
    await tester.scrollUntilVisible(
      find.byKey(const Key(kDebugUltimateFillKey)),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key(kDebugUltimateFillKey)));

    final bool fullShown = await _pumpUntil(
      tester,
      () => find.textContaining('当前能量：2/2').evaluate().isNotEmpty,
    );
    expect(fullShown, isTrue, reason: '充满后常显行必须显示 2/2');
    expect(find.textContaining('大招能量已充满'), findsOneWidget);
    final UltimateEnergy afterFill = await h.ultimateService.read();
    expect(afterFill.filledCells, 2, reason: '充满必须钳到 maxCells=2');
    expect(afterFill.fractionMin, 0, reason: '满 2 格时零头恒 0（不变量）');
  });
}
