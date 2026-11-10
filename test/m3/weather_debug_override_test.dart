/// 「今日天气」调试 override（第五批 2026-11-07，玄参「调试面板里面没有关于
/// 天气的调试按钮」）· 验收测试。
///
/// ## 覆盖口径
///  · **override 接线**（真页面 + `debugWeatherOverrideProvider`，**不** override
///    `todayWeatherProvider`——保持生产装配）：置 drought ⇒ provider 快照换成
///    `WeatherSystem.ofKind(drought)`，状态灯变红底 +「!」角标，对话框显示
///    暴风雨…… 不对，是**干旱**的措施详情 + 买棚按钮 + 明日预告行；
///    置 null ⇒ 全链路回真实日型（watch 订阅，自动刷新，无手动 invalidate）；
///  · **账本口径守卫**：override 状态下买棚，service 收到的时间戳仍是
///    **真实今天**（`WeatherSystem.dayKey(captured) == WeatherSystem.dayKey(now)`）
///    —— override 只换「显示的日型」，账本 dayKey 永不乱（A3 §13 同源纪律）；
///  · **调试面板按钮接线**：点 drought 钮 ⇒ override 变 drought；点
///    「跟随真实日期」⇒ 回 null。
///
/// ## 测试手法（同 `garden_fab_entitlement_reactive_test` 的容器手法）
/// `ProviderContainer` + 假仓储挂真 `GardenPage`；日期**绝不手写**，日型一律
/// `WeatherSystem.ofDay(now)` 实测（「哪天是什么天气」只能实测，不许猜）。
///
/// ⚠️ 花园页木牌呼吸 / 氛围音是无限动画 → 全程禁 `pumpAndSettle`，用有界 pump。
library weather_debug_override_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/di/today_weather.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart'
    show kShelterButtonHitKey, weatherNameOf;

// ── 内存 Fake 仓储（口径与 garden_fab_entitlement_reactive_test 一致）────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: 'Sunflower',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

class _FakeSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _FakePlants implements PlantRepository {
  _FakePlants(this._plants);

  final List<Plant> _plants;

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(_plants);

  @override
  Future<Plant?> plant(String id) async => null;

  @override
  Future<void> savePlant(Plant plant) async {}

  @override
  Future<void> deletePlant(String id) async {}

  @override
  Future<List<PlantSpecies>> species() async => const <PlantSpecies>[
        _sunflower,
      ];
}

class _FakeFocus implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      const <FocusSession>[];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _FakeLedger implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 100.0;

  @override
  Future<double> balance() async => 100.0;

  @override
  Future<List<SunlightEntry>> all() async => const <SunlightEntry>[];

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;

  @override
  Future<double> dayNet(String key) async => 0;

  @override
  Future<double> earnGrossOnDay(String key) async => 0;

  @override
  Future<double> earnNetOnDay(String key) async => 0;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String key) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String key) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String key) async =>
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

class _FakeEntitlementRepo implements EntitlementRepository {
  @override
  Future<Entitlement> read() async => Entitlement.free;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async {}

  @override
  Future<void> clear() async {}
}

/// 记录型成长服务：截获 `buyShelter` 收到的 `now` 与显式 `shelterRefType`，
/// 其余动作不真执行。
///
/// 为什么截参数而不是查账本：第六批（2026-11-07「买棚后不出现绿对勾」）起，
/// 页面必须**显式传入** override 日型的推荐件 —— 截参数对任意真实日型都确定
/// 可断言「落账 refType = override 日型推荐件、dayKey = 真实今天」。
/// 第八批起 done 判据 = 仅买棚，浇水次数已不参与判定，`careQuotas` 恒喂 0。
class _RecordingGrowthService extends PlantGrowthService {
  _RecordingGrowthService({
    required super.plants,
    required super.focus,
    required super.ledger,
    required super.settings,
    required super.bloomRewards,
  });

  DateTime? capturedBuyNow;
  String? capturedBuyRefType;

  @override
  Future<ShelterBuyResult> buyShelter(
    DateTime now, {
    String? shelterRefType,
  }) async {
    capturedBuyNow = now;
    capturedBuyRefType = shelterRefType;
    if (shelterRefType == null) return const ShelterBuyResult.notNeeded();
    // 成功态（记录型：不真写账），页面据此走「已购 → done」就地生效分支。
    return ShelterBuyResult.bought(shelterRefType, 90, isRecommended: false);
  }

  @override
  Future<Map<String, PlantCareQuota>> careQuotas(
    List<Plant> plants,
    DateTime now,
  ) async {
    return <String, PlantCareQuota>{
      for (final Plant p in plants)
        p.id: const PlantCareQuota(
          waterUsedToday: 0,
          fertilizeUsedToday: 0,
          minutesUntilNextWater: 0,
          waterBlockReason: null,
          fertilizeBlockReason: null,
          waterQuota: kPlantWaterMaxPerDay,
        ),
    };
  }
}

// ── 宿主 ────────────────────────────────────────────────────────────────────

List<Plant> _alivePlants(int n) {
  final DateTime now = DateTime.now();
  return List<Plant>.generate(
    n,
    (int i) => Plant(
      id: 'dbg_weather_p$i',
      speciesId: _sunflower.id,
      potIndex: i,
      stage: PlantStage.sprout,
      stageStartedAt: now,
      growthProgress: 0.4,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
    ),
  );
}

/// 真页面宿主（不 override `todayWeatherProvider`：override 走
/// [debugWeatherOverrideProvider]，装配保持生产链）。
Widget _pageHost(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: GardenPage(embedded: true)),
      ),
    );

ProviderContainer _makeContainer({PlantGrowthService? growthService}) {
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  return ProviderContainer(
    overrides: <Override>[
      appDatabaseProvider.overrideWithValue(database),
      settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      sunlightRepositoryProvider.overrideWithValue(_FakeLedger()),
      focusRepositoryProvider.overrideWithValue(_FakeFocus()),
      plantRepositoryProvider.overrideWithValue(_FakePlants(_alivePlants(5))),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      entitlementRepositoryProvider.overrideWithValue(_FakeEntitlementRepo()),
      if (growthService != null)
        plantGrowthServiceProvider.overrideWithValue(growthService),
    ],
  );
}

/// 有界帧推进：最多 [maxFrames] 帧、每帧 [step]，直到 [ready] 为真即停。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 60,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 等真页面数据就绪（badge 在场 = 非 loading）。
Future<void> _pumpPageReady(WidgetTester tester, Widget host) async {
  await tester.pumpWidget(host);
  final bool ready = await _pumpUntil(
    tester,
    () => find.byKey(kGardenWeatherBadgeKey).evaluate().isNotEmpty,
  );
  expect(ready, isTrue, reason: '真页面应在有限帧内加载完成（badge 在场）');
  await tester.pump();
}

void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();

  setUp(() {});
  // （日期日型一律运行时实测，绝无手写 —— 见文件头。）

  testWidgets(
      'override 接线：置 drought → 快照换日型 / 状态灯红底+叹号 / '
      '对话框显示干旱详情 + 买棚按钮 + 明日预告；置 null → 回真实日型',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final ProviderContainer container = _makeContainer();
    addTearDown(container.dispose);
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfGarden;
    container.read(childShellOnStageProvider.notifier).state = true;

    await _pumpPageReady(tester, _pageHost(container));

    // 前置：override 恒 null = 跟随真实日期；快照日型 = 真实今天。
    final WeatherKind realKind =
        container.read(todayWeatherProvider).day.kind;
    expect(container.read(debugWeatherOverrideProvider), isNull,
        reason: 'override 默认 null（跟随真实日期）');
    expect(realKind, WeatherSystem.ofDay(DateTime.now()).kind,
        reason: '无 override 时快照日型 = 真实今天（生产装配未被替换）');

    // 置 drought（若真实今天已是 drought 则用 wind，保证「换了」这个事实可见）。
    final WeatherKind target =
        realKind == WeatherKind.drought ? WeatherKind.wind : WeatherKind.drought;
    container.read(debugWeatherOverrideProvider.notifier).state = target;
    await _pumpUntil(
      tester,
      () => container.read(todayWeatherProvider).day.kind == target,
    );
    await tester.pump();
    expect(container.read(todayWeatherProvider).day.kind, target,
        reason: 'watch 订阅 ⇒ override 变化快照自动重算（ofKind 单点，不手搓字段）');
    expect(container.read(todayWeatherProvider).dayKey,
        WeatherSystem.dayKey(DateTime.now()),
        reason: 'dayKey 仍来自真实 now（账本口径不被 override 带歪）');

    // 状态灯（极端 todo 态）：雾霾青蓝底 + 红描边 + 红色「!」角标（第八批新样式）。
    expect(
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
              .decoration! as BoxDecoration)
          .color,
      const Color(0xFF6FA3A0),
      reason: 'override 极端日 ⇒ 状态灯雾霾青蓝底（第八批加深：纯白雪花要清晰）',
    );
    expect(
      ((tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
                  .decoration! as BoxDecoration)
              .border! as Border)
          .top
          .color,
      const Color(0xFFE24B4A),
      reason: 'override 极端日 ⇒ 状态灯 1.5 红描边',
    );
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsOneWidget,
        reason: 'override 极端日 ⇒ 叹号角标在场');
    expect(find.text('!'), findsOneWidget, reason: '角标内容 = 白色「!」');

    // 对话框：干旱措施详情 + 买棚按钮 + 明日预告行（明日 = 真实 observedAt+1）。
    await tester.tap(find.byKey(kGardenWeatherBadgeKey));
    await _pumpUntil(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isNotEmpty,
    );
    expect(find.text(zh.garden_weather_guide_drought), findsOneWidget,
        reason: '对话框详情 = 干旱孩子视角引导文案（override 生效到弹窗，第六批）');
    // 明日预告行：明日 kind 仍按**真实日历**（快照 observedAt + 1 天）。
    final DateTime now = DateTime.now();
    final WeatherKind realTomorrow = WeatherSystem.ofDay(
      DateTime(now.year, now.month, now.day + 1),
    ).kind;
    expect(
        find.text(zh.garden_weather_dialog_tomorrow(
            weatherNameOf(realTomorrow, zh))),
        findsOneWidget,
        reason: '明日预告行在场且 =「明天 · 真实明天的日型名」'
            '（override 只换今日显示，不动日历）');
    expect(find.byKey(kGardenWeatherDialogTomorrowKey), findsOneWidget,
        reason: '明日预告行 Key 在场');
    expect(find.byKey(kShelterButtonHitKey), findsOneWidget,
        reason: '极端 todo ⇒ 买棚按钮在对话框里');
    expect(
        find.text('${zh.garden_shelter_shade} · $kWeatherShelterPrice ☀'),
        findsOneWidget,
        reason: '买棚按钮 = 遮阳棚 · 10 ☀');

    // 关对话框 → override 置 null → 回真实日型（对话框名字 = 真实日型名）。
    await tester.tap(find.text(zh.garden_weather_dialog_close));
    await _pumpUntil(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isEmpty,
    );
    container.read(debugWeatherOverrideProvider.notifier).state = null;
    await _pumpUntil(
      tester,
      () => container.read(todayWeatherProvider).day.kind == realKind,
    );
    await tester.pump();
    expect(container.read(debugWeatherOverrideProvider), isNull,
        reason: '复位后 override 回 null');

    await tester.tap(find.byKey(kGardenWeatherBadgeKey));
    await _pumpUntil(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isNotEmpty,
    );
    expect(find.text(weatherNameOf(realKind, zh)), findsOneWidget,
        reason: '复位后对话框回到真实日型名（全链路刷新无需手动 invalidate）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('账本口径守卫：override 状态下买棚，service 收到的 dayKey 仍是真实今天',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _RecordingGrowthService service = _RecordingGrowthService(
      plants: _FakePlants(_alivePlants(5)),
      focus: _FakeFocus(),
      ledger: _FakeLedger(),
      settings: _FakeSettings(),
      bloomRewards: InMemoryBloomRewardRepository(),
    );
    final ProviderContainer container = _makeContainer(growthService: service);
    addTearDown(container.dispose);
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfGarden;
    container.read(childShellOnStageProvider.notifier).state = true;

    await _pumpPageReady(tester, _pageHost(container));

    // override 置 drought（日型换了，账本不该跟着换）。
    container.read(debugWeatherOverrideProvider.notifier).state =
        WeatherKind.drought;
    await _pumpUntil(
      tester,
      () => container.read(todayWeatherProvider).day.kind ==
          WeatherKind.drought,
    );

    // 点状态灯 → 对话框 → 买棚 → 确认卡「搭起来」。
    await tester.tap(find.byKey(kGardenWeatherBadgeKey));
    await _pumpUntil(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(kShelterButtonHitKey));
    await _pumpUntil(
      tester,
      () => find.text(zh.garden_shelter_confirm_ok).evaluate().isNotEmpty,
    );
    await tester.tap(find.text(zh.garden_shelter_confirm_ok));
    final bool captured = await _pumpUntil(
      tester,
      () => service.capturedBuyNow != null,
    );
    expect(captured, isTrue, reason: '确认后应走到 service.buyShelter（链路打通）');
    expect(
      WeatherSystem.dayKey(service.capturedBuyNow!),
      WeatherSystem.dayKey(DateTime.now()),
      reason: 'override 只换显示日型；service 收到的时间戳仍是真实今天 '
          '⇒ 落账 dayKey 永不因调试被带歪',
    );
    // 第六批新语义：落账 refType 必须等于 **override 日型**的推荐件
    // （显示的按钮 = 落账的道具 = done 判定的依据，三者同源）。
    expect(
      service.capturedBuyRefType,
      kWeatherShelterRefTypeShade,
      reason: 'override drought ⇒ 落账 refType = shelter_shade '
          '（旧实现缺省取「真实今天推荐件」，温和日 → notNeeded 永不 done）',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('回归（第六批）：override=drought → 买棚 → badge 立即绿底对勾、'
      '对话框出盾牌行（显示 / 落账 / done 三者同源）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 第八批：done 判据 = 仅买棚，不再喂 waterUsedToday（浇水次数不参与判定）。
    final _RecordingGrowthService service = _RecordingGrowthService(
      plants: _FakePlants(_alivePlants(5)),
      focus: _FakeFocus(),
      ledger: _FakeLedger(),
      settings: _FakeSettings(),
      bloomRewards: InMemoryBloomRewardRepository(),
    );
    final ProviderContainer container = _makeContainer(growthService: service);
    addTearDown(container.dispose);
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfGarden;
    container.read(childShellOnStageProvider.notifier).state = true;
    // **进页前**先置 override：首帧 _reload 即按干旱快照取当日事实
    // （anyWatered=0 / _shelterBoughtToday=0 ⇒ 缺棚，todo）。
    container.read(debugWeatherOverrideProvider.notifier).state =
        WeatherKind.drought;

    await _pumpPageReady(tester, _pageHost(container));

    // 前置：买棚前是 todo 态（角标在场）。
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsOneWidget,
        reason: '买棚前 badge 应为 todo（角标在场）');

    // 买棚全链路：状态灯 → 对话框 → 买棚按钮 → 确认卡「搭起来」。
    await tester.tap(find.byKey(kGardenWeatherBadgeKey));
    await _pumpUntil(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(kShelterButtonHitKey));
    await _pumpUntil(
      tester,
      () => find.text(zh.garden_shelter_confirm_ok).evaluate().isNotEmpty,
    );
    await tester.tap(find.text(zh.garden_shelter_confirm_ok));
    final bool captured = await _pumpUntil(
      tester,
      () => service.capturedBuyNow != null,
    );
    expect(captured, isTrue, reason: '确认后应走到 service.buyShelter（链路打通）');
    expect(service.capturedBuyRefType, kWeatherShelterRefTypeShade,
        reason: '落账 refType = override 日型的推荐件（三源同快照）');
    expect(
      WeatherSystem.dayKey(service.capturedBuyNow!),
      WeatherSystem.dayKey(DateTime.now()),
      reason: 'dayKey 仍等于真实今天（账本日期口径不被 override 带歪）',
    );

    // badge **立即**（不等下一次刷新）变 done：绿底 + 对勾，叹号退场。
    await tester.pump();
    expect(
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
              .decoration! as BoxDecoration)
          .color,
      const Color(0xFFC0DD97),
      reason: '买棚成功 ⇒ badge 立即绿底（done 态，玄参本次反馈的验收点）',
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget,
        reason: '绿底白对勾角标在场');
    expect(find.text('!'), findsNothing, reason: '叹号随 done 退场');

    // 重开对话框：买棚按钮退场（done）；盾牌行已迁往 badge 左侧（第七批），
    // 框内不再有「已获保护」。
    await tester.tap(find.byKey(kGardenWeatherBadgeKey));
    await _pumpUntil(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isNotEmpty,
    );
    expect(find.text(zh.garden_weather_protected), findsNothing,
        reason: '对话框不再渲染盾牌 /「已获保护」行（第七批迁往 badge 左侧）');
    expect(find.byKey(kShelterButtonHitKey), findsNothing,
        reason: 'done 态对话框不再显示买棚按钮');
    // 关对话框 → 断言 badge 左侧盾牌在场（第七批新位置）。
    await tester.tap(find.text(zh.garden_weather_dialog_close));
    await _pumpUntil(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isEmpty,
    );
    expect(find.byKey(kGardenWeatherBadgeShelterKey), findsOneWidget,
        reason: '已购棚 ⇒ badge 左侧盾牌位图在场（第七批 2026-11-07）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('调试面板按钮接线：点 drought 钮 → override 变 drought；'
      '点「跟随真实日期」→ 回 null', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final ProviderContainer container = _makeContainer();
    addTearDown(container.dispose);

    // 直接挂 BloomDebugSheet（面板本体），不走整页 —— 面板按钮接线是本用例焦点。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: BloomDebugSheet(maxHeight: 700)),
        ),
      ),
    );
    // 等面板加载完成（_loaded：标题在场），再把列表滚到底 —— 天气区块按末尾
    // 位置纪律排在空盆区块之后，懒构建 ListView 不滚不建。
    expect(
      await _pumpUntil(
        tester,
        () => find.text('花期调试').evaluate().isNotEmpty,
        maxFrames: 120,
      ),
      isTrue,
      reason: '面板本体应加载完成',
    );
    // 🔴 B5a 修正：守卫区块（列表最末尾）加高后，固定 6×-600 拖动的总行程
    // 会越过天气区块，把日型钮顶出视口（tap 报「Offset 越界」）。改为
    // **事件驱动滚动**（滚到 drought 钮可见为止）—— 与懒构建 ListView 的
    // 测试纪律一致（同 guard_debug_script_test 的 scrollUntilVisible 口径）。
    final Finder droughtBtn =
        find.byKey(const ValueKey<String>('debug_weather_kind_drought'));
    await tester.scrollUntilVisible(
      droughtBtn,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final bool sectionReady = await _pumpUntil(
      tester,
      () => droughtBtn.evaluate().isNotEmpty,
      maxFrames: 60,
    );
    expect(sectionReady, isTrue, reason: '面板应渲染「今日天气」调试区块（9 日型按钮）');
    // 9 种日型按钮 + 复位钮全部在场。
    for (final WeatherKind kind in WeatherKind.values) {
      expect(
          find.byKey(ValueKey<String>('debug_weather_kind_${kind.name}')),
          findsOneWidget,
          reason: '日型按钮在场：${kind.name}');
    }
    expect(find.text('跟随真实日期'), findsOneWidget, reason: '复位钮在场');
    expect(container.read(debugWeatherOverrideProvider), isNull);

    // 点 drought → override 变 drought（provider 层写入，页面侧 watch 自动刷新）。
    await tester.tap(
        find.byKey(const ValueKey<String>('debug_weather_kind_drought')));
    await tester.pump();
    expect(container.read(debugWeatherOverrideProvider), WeatherKind.drought,
        reason: '点 drought 钮 ⇒ override = drought');

    // 点复位钮 → 回 null（跟随真实日期）。同样事件驱动滚动到可见（理由同上）。
    await tester.scrollUntilVisible(
      find.text('跟随真实日期'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('跟随真实日期'));
    await tester.pump();
    expect(container.read(debugWeatherOverrideProvider), isNull,
        reason: '复位钮 ⇒ override = null');

    expect(tester.takeException(), isNull);
  });
}
