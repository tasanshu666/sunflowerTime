/// 独立复验（QA/Edward）· P0-③ 一键护理音效 + P1-④ 种植音效 + 一键收集音效（**行为级**，
/// 非源码字符串守卫）。
///
/// 工程用例 `one_click_care_sfx_guard_test.dart` 只是 `grep` 源码字符串（弱测试）。本文件
/// 用项目**既有可注入钩子** `just_audio` 的 `JustAudioPlatform.instance` 打桩（记录型假平台），
/// 在**真实 GardenPage** 上跑完整交互链路，断言音频资产**确实被加载并起播**：
///   · D1 一键护理（**仅杂草**）→ 恰好加载并播放一次 `care_weed.mp3`（且**不**加载 `care_pest.mp3`）；
///   · D2 种植成功 → 恰好加载一次 `cultivate.mp3`；
///   · D3 种植「取消」→ **不**加载 `cultivate.mp3`（失败/取消路径不得播音）。
///   · D4 一键收集（**2 盆 × 2 条 = 4 条**到期晨露）→ 恰好加载并播放一次 `collect_reward.mp3`。
///        🔴 玄参 2026-11-09 真机 Bug 的回归钉：修复前 `_onOneClickCollect` 完全不播音效
///        （`_collectRewards` 内部不播，谁调谁负责）；修复后**整批只播一次**。本用例的
///        红线是「**播放总量与收集条数无关**」——若实现被改成在逐条循环里播，4 条 → 4 次
///        → 本断言即红。
///   · D5 一键收集**空态**（无任何到期晨露）→ **不**加载 `collect_reward.mp3`（只弹
///        「暂时没有可以采集的晨露」居中提示）。
library qa_independent_p0_care_sfx_behavior_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_reward_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

import '../helpers/no_hit_random.dart';

// ── 记录型假 just_audio 平台（可注入钩子，项目既有平台接口）────────────────────

class _RecPlayer extends AudioPlayerPlatform {
  _RecPlayer(super.id, this.log);
  final List<String> log;
  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final AudioSourceMessage m = request.audioSourceMessage;
    final String uri = m is UriAudioSourceMessage ? m.uri : m.toString();
    log.add('load:$uri');
    scheduleMicrotask(() => _events.add(PlaybackEventMessage(
          processingState: ProcessingStateMessage.ready,
          updateTime: DateTime.now(),
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
          duration: const Duration(seconds: 4),
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null,
        )));
    return LoadResponse(duration: const Duration(seconds: 4));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    log.add('play');
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
          SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();
  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
              SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest
                  request) async =>
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();
  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
          SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();
  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
          SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async =>
      DisposeResponse();
}

class _RecPlatform extends JustAudioPlatform {
  final List<String> log = <String>[];
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      _RecPlayer(request.id, log);
  @override
  Future<DisposePlayerResponse> disposePlayer(
          DisposePlayerRequest request) async =>
      DisposePlayerResponse.fromMap(<dynamic, dynamic>{});
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse.fromMap(<dynamic, dynamic>{});
}

late final _RecPlatform _fake;

// ── 假仓储 ──────────────────────────────────────────────────────────────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

AppSettings _settings() => const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: 6,
      bgmOn: false, // 关掉氛围音，避免背景 BGM 污染音频记录
    );

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings();
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepository implements SunlightRepository {
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
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}

/// **记账版**阳光仓储（D4/D5 用）：把每次 [append] 的金额记下来，用来给
/// [_drainUntil] 提供「业务已收完 N 条」的**确定性完成信号** —— 只有业务真收完，
/// 「整批只播一次」的断言才有意义（否则可能在音效还没发起时就去数次数 = 假绿）。
class _RecordingSunlightRepository implements SunlightRepository {
  _RecordingSunlightRepository(this._inner);
  final SunlightRepository _inner;
  final List<double> appended = <double>[];

  @override
  Future<double> append(SunlightEntry entry) async {
    appended.add(entry.net);
    return _inner.append(entry);
  }

  @override
  Future<double> balance() => _inner.balance();
  @override
  Future<double> dayNet(String dayKey) => _inner.dayNet(dayKey);
  @override
  Future<double> verifiedRedeemTotal() => _inner.verifiedRedeemTotal();
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) =>
      _inner.netByRefTypeOnDay(refType, dayKey);
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) =>
      _inner.netByRefTypeInMonth(refType, monthKey);
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) =>
      _inner.countByRefTypeAndRefIdOnDay(refType, refId, dayKey);
  @override
  Future<int> countByRefType(String refType) =>
      _inner.countByRefType(refType);
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) =>
      _inner.countByRefTypeAndRefIdSince(refType, refId, since);
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) =>
      _inner.lastTsByRefTypeAndRefId(refType, refId);
  @override
  Future<double> earnGrossOnDay(String dayKey) =>
      _inner.earnGrossOnDay(dayKey);
  @override
  Future<double> earnNetOnDay(String dayKey) => _inner.earnNetOnDay(dayKey);
  @override
  Future<List<SunlightEntry>> all() => _inner.all();
  @override
  Future<SunlightEntry?> latestByRefType(String refType) =>
      _inner.latestByRefType(refType);
}

class _FakeFocusRepository implements FocusRepository {
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

class _StoringPlantRepository implements PlantRepository {
  _StoringPlantRepository(this._plants);
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

/// 4 株「有杂草」的活株（可触发一键护理；weedPestRollDay=今天 → 刷新不重 roll）。
List<Plant> _fourWeedySprouts() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  return <Plant>[
    for (int i = 0; i < 4; i++)
      Plant(
        id: 'p$i',
        speciesId: 'species_sunflower',
        potIndex: i,
        stage: PlantStage.sprout,
        stageStartedAt: now.subtract(const Duration(hours: 2)),
        growthProgress: 0.3,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: now.subtract(const Duration(hours: 2)),
        lastWaterAt: now,
        weedAt: today,
        weedPestRollDay: today,
      ),
  ];
}

/// 4 株「正在盛开」的成株 —— 一键收集用例的宿主。
///
/// 为什么必须 4 株：一键操作 FAB 的出现条件是**存活株 ≥ kOneClickMinPlants = 4**；
/// 且只有**盛开态**的植株才会挂晨露（`collectibleBloomRewards` 的数据源）。
///
/// `bloomedAt` 取 3 小时前：晨露的 `dueAt` 必须**不早于**本轮花期起点（`kBloomSameRoundToleranceSeconds`
/// 容差内），否则会被判成「旧轮滞留」而不可收集。
List<Plant> _fourBloomingPlants() {
  final DateTime now = DateTime.now();
  return <Plant>[
    for (int i = 0; i < 4; i++)
      Plant(
        id: 'p$i',
        speciesId: 'species_sunflower',
        potIndex: i,
        stage: PlantStage.adult,
        stageStartedAt: now.subtract(const Duration(hours: 5)),
        growthProgress: 1.0,
        growthFactor: 1.0,
        status: PlantStatus.bloomed,
        plantedAt: now.subtract(const Duration(days: 5)),
        bloomedAt: now.subtract(const Duration(hours: 3)),
        bloomCount: 1,
        lastWaterAt: now, // 刚浇过水 → 3 天内不枯萎
      ),
  ];
}

/// 4 株普通幼苗（无晨露 —— 一键收集空态用例的宿主）。
List<Plant> _fourSprouts() {
  final DateTime now = DateTime.now();
  return <Plant>[
    for (int i = 0; i < 4; i++)
      Plant(
        id: 'p$i',
        speciesId: 'species_sunflower',
        potIndex: i,
        stage: PlantStage.sprout,
        stageStartedAt: now.subtract(const Duration(hours: 2)),
        growthProgress: 0.3,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: now.subtract(const Duration(hours: 2)),
        lastWaterAt: now,
      ),
  ];
}

/// 每条晨露预先定奖的阳光数（取 6：与真实掉落同量级；> 0 才能证明「真入账」）。
const int _kDewSunlight = 6;

/// 给 [plantIds] 里**每株**各挂 [perPlant] 条「已到期、即刻可收」的开花瞬间晨露。
///
/// 与真实掉落的形状一致（`rewardKind='instant'` + `dueAt` 在过去 → 立即可收集）；
/// id 全局唯一（仓储主键冲突会让「条数」失真 → 断言变成空转）。
///
/// ⚠️ **`dueAt` 必须逐条错开**（这里每条差 1 分钟）：花园页 `_reload` 会跑
/// `dedupePendingBloomRewards()`，它按 `plantId | dueAt.millisecondsSinceEpoch | rewardKind`
/// 去重 —— 同株两条 `dueAt` 完全相同的 pending 会被当成「同一槽位重复登记」删掉一条，
/// 「4 条」会静默退化成「2 条」→ 本用例的「条数无关」就白测了（实测踩过这个坑）。
/// 错开 1 分钟仍远在 `bloomedAt`（3 小时前）之后 → 依旧是**本轮可收集**。
List<PendingBloomReward> _dueDew(
  List<String> plantIds, {
  int perPlant = 1,
}) {
  final DateTime now = DateTime.now();
  return <PendingBloomReward>[
    for (final String pid in plantIds)
      for (int k = 0; k < perPlant; k++)
        PendingBloomReward(
          id: 'dew_${pid}_$k',
          plantId: pid,
          dueAt: now.subtract(Duration(hours: 1, minutes: -k)),
          rewardKind: 'instant',
          rewardSunlight: _kDewSunlight,
        ),
  ];
}

Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 200,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 花园页宿主。[rewards] / [ledger] 可选，缺省时与 D1~D3 的既有行为**逐位一致**。
Widget _host(
  PlantRepository plants, {
  InMemoryBloomRewardRepository? rewards,
  SunlightRepository? ledger,
}) =>
    ProviderScope(
      overrides: <Override>[
        // 阶段 4：一键操作按档位门控（free 隐藏 FAB）→ 本用例按**买断档**运行。
        entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider
            .overrideWithValue(ledger ?? _FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(plants),
        bloomRewardRepositoryProvider
            .overrideWithValue(rewards ?? InMemoryBloomRewardRepository()),
        plantGrowthServiceProvider.overrideWith((Ref ref) => PlantGrowthService(
              plants: ref.watch(plantRepositoryProvider),
              focus: ref.watch(focusRepositoryProvider),
              ledger: ref.watch(sunlightRepositoryProvider),
              settings: ref.watch(settingsRepositoryProvider),
              bloomRewards: ref.watch(bloomRewardRepositoryProvider),
              weedRandom: NoHitRandom(),
            )),
      ],
      child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    );

/// 一键收集用例的宿主装置：泵花园页 → 等 FAB → 展开「一键操作」卡 → 就绪。
///
/// 返回（种子晨露, 记账阳光仓储），供用例做「业务层前置/完成」校验。
///
/// ⚠️ **就绪判据必须是页面级事实**（不是睡固定时长）：
///   · 有晨露 → 等 `BloomRewardIconsBar` 出现 **且数量 == 有晨露的盆数** —— 这直接证明
///     `_collectibles` 已灌好（否则点下去会走空态分支，用例变成假绿）；
///   · 空态 → 等 FAB 出现即可（此时 `_collectibles` 必然为空）。
Future<
    ({
      List<PendingBloomReward> seeded,
      _RecordingSunlightRepository ledger,
    })> _pumpGardenForOneClickCollect(
  WidgetTester tester, {
  required List<Plant> plants,
  List<String> dewOnPots = const <String>[],
  int perPlant = 1,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final List<PendingBloomReward> seeded = _dueDew(dewOnPots, perPlant: perPlant);
  final InMemoryBloomRewardRepository rewards = InMemoryBloomRewardRepository();
  for (final PendingBloomReward r in seeded) {
    await rewards.insertPendingBloomReward(r);
  }
  final _RecordingSunlightRepository ledger =
      _RecordingSunlightRepository(_FakeSunlightRepository());

  await tester.pumpWidget(
    _host(_StoringPlantRepository(plants), rewards: rewards, ledger: ledger),
  );

  // 等花园页首次加载完（悬浮球出现 = 存活株 ≥4 已判定）。
  final bool fabShown = await _pumpUntil(
    tester,
    () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
  );
  expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作悬浮球');

  if (dewOnPots.isNotEmpty) {
    // 页面真的认出了这些晨露（每盆一个聚合图标条）→ `_collectibles` 已就绪。
    final bool iconsShown = await _pumpUntil(
      tester,
      () =>
          find.byType(BloomRewardIconsBar).evaluate().length ==
          dewOnPots.length,
    );
    expect(iconsShown, isTrue,
        reason: '前置：页面应认出 ${dewOnPots.length} 盆的到期晨露'
            '（实得 ${find.byType(BloomRewardIconsBar).evaluate().length} 盆）');
  }

  // 展开操作卡。
  await tester.tap(find.byIcon(Icons.touch_app));
  final bool cardShown = await _pumpUntil(
    tester,
    () => find.text(_kCollectLabel).evaluate().isNotEmpty,
  );
  expect(cardShown, isTrue, reason: '展开卡必须有「$_kCollectLabel」这一行（第 4 行）');
  await tester.pump(const Duration(milliseconds: 300));

  return (seeded: seeded, ledger: ledger);
}

/// 一键操作卡第 4 行的文案（`garden_action_collect`）。
const String _kCollectLabel = '一键采集';

/// 一键收集空态文案（`garden_batch_none_collect`）。
const String _kCollectEmptyHint = '暂时没有可以采集的晨露';

int _countLoads(String substr) =>
    _fake.log.where((String e) => e.startsWith('load:') && e.contains(substr)).length;

/// 假平台记录到的 `play()` 次数。
///
/// ⚠️ 为什么「加载」断言不够（F116 收尾实测）：`load:` 是在 `setAsset` **内部同步**记录的，
/// 而 `play` 是它**之后**的环节 —— 一旦 `setAsset` 挂死（例如跨 FakeAsync Zone 复用旧
/// 播放器、永远等不到 `ready`），`load:` 照样会记录、断言依旧通过 = **假绿**。故本组用例
/// 一律「等到 `play` 真发生」才收尾，并断言恰好一次。
int _countPlays() => _fake.log.where((String e) => e == 'play').length;

/// 自适应排空：交替 `runAsync`（真实异步窗口）+ `pump`（假时钟微任务排空），
/// 直到 [ready] 为真（或达 [maxRounds] 上限）——替代**定长窗口**，避免并行全量
/// 高负载下真实 `setAsset` I/O 未跑完而误判（QA 2026-10-07 修：消除偶发红）。
/// 达标后再补 [extraRounds] 轮，让「恰好一次」计数稳定。
Future<void> _drainUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxRounds = 100,
  int extraRounds = 12,
  Duration step = const Duration(milliseconds: 60),
}) async {
  for (int i = 0; i < maxRounds; i++) {
    if (ready()) break;
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
  for (int i = 0; i < extraRounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _fake = _RecPlatform();
    JustAudioPlatform.instance = _fake;
  });

  setUp(() async {
    // ⚠️ **必须**：`AudioService.instance` 跨用例复用，而每个 `testWidgets` 一套独立
    // FakeAsync Zone —— 不清就会把上一个用例 Zone 的 `_sfxPlayer` 带进来，本用例的
    // `setAsset` 内部永远等不到 `ready` 事件（`play` 从未发生），而 `load:` 已同步记录
    // → 断言侥幸通过 = **假绿**。花园页音效是直接调单例（绕过 provider），只能用本钩子。
    AudioService.instance.resetForTest();
    _fake.log.clear();
    // path_provider：just_audio 的 setAsset 会把资产拷到临时缓存目录。
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('qa_sfx');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  testWidgets('D1 一键护理（仅杂草）成功 → 恰好加载一次 care_weed.mp3（且不加载 care_pest.mp3）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(_fourWeedySprouts())));

    final bool fabShown = await _pumpUntil(
      tester,
      () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
    );
    expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');

    await tester.tap(find.byIcon(Icons.touch_app));
    await _pumpUntil(tester, () => find.text('一键护理').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('一键护理'));

    await _pumpUntil(tester, () => find.text('要一键护理吗？').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确定'));
    // onPressed 同步触发 playSfx（fire-and-forget）；just_audio 的 setAsset 是多次
    // 真实 I/O（rootBundle→临时文件），FakeAsync 下不会推进 → 交替「真实异步窗口
    // (runAsync) + 假时钟微任务排空 (pump)」把整条异步链跑完。**自适应**：轮询到
    // care_weed 真加载（防并行全量高负载下定长窗口跑不完 → 偶发红）。
    await _drainUntil(
        tester,
        () =>
            _countLoads('audio/sfx/care_weed.mp3') >= 1 && _countPlays() >= 1);

    expect(_countLoads('audio/sfx/care_weed.mp3'), 1,
        reason: '一键护理（**仅杂草**）→ 按实际内容恰好播一次除草音效 care_weed.mp3（整批一次）');
    expect(_countLoads('audio/sfx/care_pest.mp3'), 0,
        reason: '仅杂草不应播除虫音效（玄参 2026-10-07 口径修订：按实际护理内容选音效）');
    expect(_countPlays(), 1,
        reason: '音效必须**真的起播**（恰好一次）—— 钉死「`load:` 已记录但 `setAsset` 挂死」的假绿');
  });

  testWidgets('D2 种植成功 → 恰好加载一次 cultivate.mp3', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 空花园：首株向日葵免费。
    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[])));

    // 点第一个空花盆 → 选种弹窗。
    final Finder emptyPot = find.byType(EmptyPot);
    await _pumpUntil(tester, () => emptyPot.evaluate().isNotEmpty);
    expect(emptyPot.evaluate(), isNotEmpty, reason: '空花园应有空花盆');
    await tester.tap(emptyPot.first);
    final bool sheetShown = await _pumpUntil(
        tester, () => find.text('选择要种的植物').evaluate().isNotEmpty);
    expect(sheetShown, isTrue, reason: '点空盆应弹出选种弹窗');

    await tester.tap(find.text('免费'));
    final bool confirmShown = await _pumpUntil(
        tester, () => find.text('要种下向日葵吗？').evaluate().isNotEmpty);
    expect(confirmShown, isTrue, reason: '选免费应弹二次确认');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确定种植'));
    await _drainUntil(
        tester,
        () => _countLoads('audio/sfx/cultivate.mp3') >= 1 && _countPlays() >= 1);

    expect(_countLoads('audio/sfx/cultivate.mp3'), 1,
        reason: '种植成功后应恰好加载一次 cultivate.mp3');
    expect(_countPlays(), 1,
        reason: '音效必须**真的起播**（恰好一次）—— 钉死「`load:` 已记录但 `setAsset` 挂死」的假绿');
  });

  testWidgets('D3 种植「取消」→ 不加载 cultivate.mp3', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[])));

    final Finder emptyPot = find.byType(EmptyPot);
    await _pumpUntil(tester, () => emptyPot.evaluate().isNotEmpty);
    await tester.tap(emptyPot.first);
    await _pumpUntil(
        tester, () => find.text('选择要种的植物').evaluate().isNotEmpty);
    await tester.tap(find.text('免费'));
    await _pumpUntil(
        tester, () => find.text('要种下向日葵吗？').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('取消'));
    // 取消路径不应播音效：给足排空窗口（若真会播，此时也必然已加载）。
    await _drainUntil(tester, () => false, maxRounds: 15, extraRounds: 0);

    expect(_countLoads('audio/sfx/cultivate.mp3'), 0,
        reason: '取消种植不得播放种植音效（失败/取消路径不播）');
  });

  // ── 一键收集音效（玄参 2026-11-09 真机 Bug 回归钉）──────────────────────────

  testWidgets(
      'D4 一键收集（2 盆 × 2 条 = 4 条晨露）→ 恰好加载并播放一次 collect_reward.mp3',
      (WidgetTester tester) async {
    // 🔴 本用例的核心红线：**播放总量与收集条数无关**。
    // 修前：`_onOneClickCollect` 完全不播音效 → 总量 0（本用例第一/第三条断言直接红）。
    // 修后：整批只播一次 → 4 条仍是 1 次。
    // 若有人把 `playSfx` 挪进逐条循环 → 4 条变 4 次 → 本用例红（这就是「防回归」的意义）。
    final ({
      List<PendingBloomReward> seeded,
      _RecordingSunlightRepository ledger,
    }) ctx = await _pumpGardenForOneClickCollect(
      tester,
      plants: _fourBloomingPlants(),
      dewOnPots: <String>['p0', 'p1'], // 2 盆
      perPlant: 2, // 每盆 2 条 → 合计 4 条
    );

    expect(ctx.seeded.length, 4, reason: '前置：本场景必须是「4 条晨露分布在 2 盆」');
    expect(_countLoads('audio/sfx/collect_reward.mp3'), 0,
        reason: '前置：点「$_kCollectLabel」之前不得有任何收集音效（否则后面的计数无意义）');

    await tester.tap(find.text(_kCollectLabel));
    // 自适应排空：**同时**等「业务真收完 4 条」（记账仓储是确定性完成信号）与
    // 「音效真起播」——只看音效会漏掉「播了但账没落」；只看账会漏掉「load 记录了但
    // play 从未发生」（F116 假绿）。两条都满足后，再补若干轮让「恰好一次」计数稳定。
    await _drainUntil(
      tester,
      () => ctx.ledger.appended.length >= 4 && _countPlays() >= 1,
    );

    // ① 一键收集**确实播了** collect_reward.mp3（修前这里是 0 = 玄参真机的「没声音」）。
    expect(_countLoads('audio/sfx/collect_reward.mp3'), 1,
        reason: '一键收集必须播收集音效 collect_reward.mp3（玄参 2026-11-09 真机「没声音」）'
            '；实得 load 日志 ${_fake.log}');
    // ② 且必须**真的起播**（不是 `load:` 记录了、`setAsset` 却挂死的假绿）。
    expect(_countPlays(), 1,
        reason: '音效必须**真的起播**（恰好一次）—— 钉死「`load:` 已记录但 `setAsset` 挂死」的假绿'
            '；实得 load 日志 ${_fake.log}');
    // ③ 全部音频加载次数恰好 1 —— 「与条数无关」的最强表达（4 条 → 1 次，不是 4 次），
    //    同时防止「播错 cue 也算过」（例如误播 care_water / cultivate）。
    expect(
        _fake.log.where((String e) => e.startsWith('load:')).length, 1,
        reason: '整批收集只允许一次音频加载（不多播、不误播其它 cue）；实得 ${_fake.log}');
    expect(_countLoads('audio/sfx/care_water.mp3'), 0,
        reason: '收集奖励不得误播浇水音效（负向断言：播错 cue 不算过）');
    expect(_countLoads('audio/sfx/cultivate.mp3'), 0,
        reason: '收集奖励不得误播种植音效（负向断言：播错 cue 不算过）');

    // ④ 业务侧复核：4 条确实**全部入账**（证明「有声音」不是凭空来的那一下，
    //    也证明排空判据里的「业务已收完」不是靠等时长蒙的）。
    expect(ctx.ledger.appended.length, 4, reason: '4 条晨露应各入账一笔');
    expect(ctx.ledger.appended.every((double v) => v > 0), isTrue,
        reason: '每条晨露都必须有真实入账（金额 > 0）');
  });

  testWidgets('D5 一键收集空态（无到期晨露）→ 不加载 collect_reward.mp3',
      (WidgetTester tester) async {
    final ({
      List<PendingBloomReward> seeded,
      _RecordingSunlightRepository ledger,
    }) ctx = await _pumpGardenForOneClickCollect(
      tester,
      plants: _fourSprouts(), // 4 株幼苗：无晨露，但有 FAB
    );
    expect(ctx.seeded, isEmpty, reason: '前置：本场景不得有任何到期晨露');

    await tester.tap(find.text(_kCollectLabel));
    // 空态应弹「暂时没有可以采集的晨露」居中提示（行为前置：证明点到了正经入口，
    // 而不是「什么都没发生」的假绿）。
    final bool hinted = await _pumpUntil(
      tester,
      () => find.text(_kCollectEmptyHint).evaluate().isNotEmpty,
    );
    expect(hinted, isTrue,
        reason: '空态必须给「$_kCollectEmptyHint」（与其余三项空态同节奏）');
    // 再给足排空窗口：若实现错误地在空态也播音，此时必然已加载。
    await _drainUntil(tester, () => false, maxRounds: 20, extraRounds: 0);

    expect(_countLoads('audio/sfx/collect_reward.mp3'), 0,
        reason: '没有任何到期晨露时**不得**播放收集音效（空态早退，不写账也不出声）');
    expect(_countPlays(), 0,
        reason: '空态不得起播任何音效');
    expect(ctx.ledger.appended, isEmpty, reason: '空态不得写任何阳光流水');
  });
}
