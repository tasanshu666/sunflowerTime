/// 孩子端花园页（M3 T02 / M3 修订 / 2026-09-24 花园页 v3 改造）。
///
/// ## 显示形态（2026-09-24 v3 改造）
/// 背景为整页草地（`assets/garden/background.png`，`BoxFit.cover`）。v3 相比上一版：
///  · 花盆网格**锁死 2 行高度**，12 盆以内不再往下撑；超出部分在网格区域内**纵向滚动**，
///    右侧滚动条**仅在内容溢出时**出现。滚动区底界落在背景菜地上沿之上，
///    滚动时花盆永不遮挡固定背景植物；
///  · 底部「容量 / 养护节奏」半透明白块**整块删除**，这些信息收进左下角**木牌**弹窗；
///  · 左下角木牌**可点击**、带轻微呼吸高亮，点开「玩法说明」。
///
/// ```
///   ┌── 整页草地背景（background.png 铺满 body）──────────────────────┐
///   │ [独立路由] 左上角阳光胶囊（内嵌 tab 由 shell AppBar 提供）        │
///   │   🌻    🌵    ✚   │ ← 3 列花盆网格（最多显示 2 行）             │
///   │  ▓▓░░  ▓░░       │   超出 → 区域内纵向滚动 + 右侧滚动条          │
///   │ [木牌●]           │ ← 左下角木牌（可点 → 玩法说明弹窗）           │
///   └────────────────────────────────────────────────────────────────┘
/// ```
///
/// **点花盆里的植物**才弹出养护卡（[showPlantCareCard]，2026-09-29 由底部面板改居中卡），按钮不再摊在草地上；
/// 空盆点击进入种植选择。花盆与植物外观都在 `garden_pot.dart` / `plant_artwork.dart`，
/// 本页只负责数据、布局与动作编排。
///
/// 进页即跑一次 [PlantGrowthService.tickAll] 推进成长与枯萎计时；任意养护操作后
/// 重新 tick 并刷新。扣减经同账本，余额变化后自增 [economyRevisionProvider] 使孩子端
/// 阳光商店同步。
///
/// 沿用 M3 修订的既有纪律：
///  · 页首常驻**阳光余额**（原先没有余额展示，扣了阳光看不出来，像「养护不消耗」）；
///  · 动作期间置 [_busy] 闸门，避免连点绕过「不能连续浇水」；
///  · 「加盆」格子**始终可点**（busy 除外）：阳光不足时点击弹分因提示，不静默。
library garden_page;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/bloom_reward_outcome.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_reward_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/care_effect_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/child_snack.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_background_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_help_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_fx_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_sign_hotspot.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_care_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/sunlight_pill.dart';

/// 孩子端花园：植物养成主界面。
///
/// [embedded] = true 时作为孩子端「花园」tab 的内容渲染（不叠加独立 Scaffold/AppBar，
/// 用 [SafeArea] 包裹）；false 时保留独立路由页形态（`/garden`，含刷新按钮）。
class GardenPage extends ConsumerStatefulWidget {
  const GardenPage({super.key, this.embedded = false});

  /// 是否以内嵌 tab 形态渲染（无独立 Scaffold/AppBar）。
  final bool embedded;

  @override
  ConsumerState<GardenPage> createState() => _GardenPageState();
}

/// 正在播放的养护动效描述：类型 + 在页面 Stack 本地坐标里的位置/尺寸 + 关联植物（用于弹跳副本）。
class _CareEffectSpec {
  final CareEffectType type;
  final Offset offset;
  final Size size;
  final Plant? plant;
  final PlantSpecies? species;

  /// 效果帧 asset 列表（2026-09-28 起为正式路径；粒子路径不再使用时也一并携带）。
  final List<String> frames;

  /// 播放时长（毫秒）= 对应音频时长。
  final int durationMs;

  _CareEffectSpec({
    required this.type,
    required this.offset,
    required this.size,
    required this.frames,
    required this.durationMs,
    this.plant,
    this.species,
  });
}

/// 正在播放的「成长过渡」演出描述（**屏幕中央焦点卡片**，玄参 2026-09-29 改口径）。
///
/// 2026-09-28 旧口径是「在目标花盆格上居中放大播放」——玄参实测：格子太小看不清、
/// 与底层花盆重叠显得乱，且因逐帧解码出现「一闪一闪」。
/// 新口径：画面正中弹出圆角白卡（宽 = 屏宽 [kGrowFxCardWidthRatio]），卡内放大播放
/// 序列帧 + 成长音频，播完**整卡淡出**消失（见 `growth_fx_overlay.dart`）。
class _GrowthFxSpec {
  final GrowTransition transition;

  /// 卡片标题文案（如「长大啦！」/「开花啦！」）。
  final String title;

  _GrowthFxSpec({
    required this.transition,
    required this.title,
  });
}

class _GardenPageState extends ConsumerState<GardenPage> {
  List<Plant> _plants = <Plant>[];
  List<PlantSpecies> _species = <PlantSpecies>[];
  AgeTier _tier = AgeTier.low;
  int _capacity = kGardenPotCapacityDefault;
  double _balance = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// 花盆上方刚清除掉的干扰物提示（口径 C26）：`potIndex` 指明浮在哪一格。
  ///
  /// 只保留**最后一条**（同一格连续点两次时，第二条直接覆盖第一条，不排队）。
  ({int potIndex, String text})? _clearHint;
  Timer? _clearHintTimer;

  /// 当前「可收集」的待收集奖励（`plantId → 待收集奖励列表`，变更 A/B）。
  /// 到期后在该花盆**上方**掉落「头顶奖励图标」（玄参 2026-09-27 图标化），点击收集
  /// （见 [_collectReward]）。
  ///
  /// 变更 B 后同一株可能**同时**有两条：开花瞬间（`due = bloomedAt`，即刻可收集）+ 第二段
  /// （`due = bloomedAt + 48h`），故为列表；列表按 `dueAt` 升序（瞬间的更早）。
  Map<String, List<PendingBloomReward>> _collectibles =
      <String, List<PendingBloomReward>>{};

  /// 可用美术资源集合（`assets/rewards/*.png`；空集 → 头顶图标全回退内置 `Icons`）。
  ///
  /// 来源 [rewardAssetsProvider]（`AssetManifest.listAssets()`）。玄参后续丢素材进
  /// `assets/rewards/` 即自动生效，无需改代码。
  Set<String> _rewardAssets = <String>{};

  /// 精品碎片当前余额（花园页碎片入口展示，变更 B）。
  int _fragmentBalance = 0;

  /// 持有的免费种植券物种 id 集合（花园「选择要种的植物」列表判「种子兑换 · 免费」用）。
  Set<String> _unlockedSpecies = <String>{};

  /// 各花盆格的全局 Key（稳定）：用于在养护成功后定位该花盆在屏幕上的坐标，
  /// 把动效叠加层精确地摆到对应花盆之上。按 potIndex 懒创建、复用。
  final Map<int, GlobalKey> _potKeys = <int, GlobalKey>{};

  /// 页面根 Stack 的 Key：把花盆的全局坐标换算到本 Stack 的本地坐标系。
  final GlobalKey _pageStackKey = GlobalKey();

  /// 当前正在播放的一次性养护动效（null = 无）。动画结束由 [CareEffectOverlay.onComplete]
  /// 置回 null 以移除叠加层。
  _CareEffectSpec? _activeEffect;

  /// 当前正在播放的「成长过渡」演出（null = 无）。播完渐隐后由播放器回调移除。
  _GrowthFxSpec? _activeGrowth;

  /// 上一轮快照：`plantId → 'stage.name:status.name'`，用于在 [_reload] 后 diff 出
  /// 「升级」（种子→幼苗 / 幼苗→成株 / 成株→盛开）并触发生长演出。首次加载为空表
  /// → 不触发（进花园不该看到满屏动画）。
  Map<String, String> _lastPhases = <String, String>{};

  /// 花园氛围音计时器（玄参 2026-09-28：进入花园立即播一次 background.mp3，
  /// 之后每 [kGardenAmbientIntervalSeconds] 秒一次；离开花园 tab 停止并取消）。
  Timer? _ambientTimer;

  /// 氛围音当前是否应处于「激活」（花园 tab 可见）状态；build 里按 TickerMode 可见性
  /// 驱动（IndexedStack 保活 tab 切换不会 dispose，用 TickerMode 判可见性）。
  bool _ambientActive = false;

  /// 网格区域滚动控制器（v3：网格锁 2 行高度，溢出时区域内滚动）。
  final ScrollController _gridScroll = ScrollController();

  /// 网格内容是否溢出可视区（决定是否显示滚动条）。
  bool _gridScrollable = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    // ⚠️ dispose 内不得用 ref（unmount 先标 disposed，用必抛）——AudioService 用静态单例。
    _ambientTimer?.cancel();
    // ⚠️ 纯 Timer 字段（不碰 ref），dispose 里取消即可；不取消会让 setState 打到已卸载页。
    _clearHintTimer?.cancel();
    unawaited(AudioService.instance.stopGardenAmbient());
    _gridScroll.dispose();
    super.dispose();
  }

  /// 扩容一只花盆的阳光价（按年段，§4.6）：供按钮文案与确认卡使用，避免裸字面量。
  int get _expandCost =>
      _tier == AgeTier.low ? kPlantPotExpandCostLow : kPlantPotExpandCostHigh;

  /// [silent] = true 时不整页转圈（养护动作后静默刷新），避免每次浇水都闪一次
  /// 全屏 loading，孩子看着像「页面重载」而不是「浇完了」。
  Future<void> _reload({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final DateTime now = DateTime.now();
      final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
      // 花谢兜底自动到账：收集本次 tick 自动结算的奖励 outcome（用于「花朵凋谢，奖励已自动
      // 收下：…」提示——玄参要求花谢自动到账**也要提示**）。
      final List<BloomRewardOutcome> autoSettled = <BloomRewardOutcome>[];
      _plants = await svc.tickAll(now, autoSettled: autoSettled);
      // 任务 A（玄参 2026-09-28）：刷新时把「v12 之前登记的零值哨兵旧 pending 行」
      // 按当前档位回写为明细，使旧数据头顶图标直接显示阳光/碎片/种子（不再礼物盒）。
      await svc.materializeLegacyBloomRewards(now);
      final AppSettings settings =
          await ref.read(settingsRepositoryProvider).getSettings();
      _tier = settings.ageTier;
      _capacity = settings.gardenPotCapacity;
      // 花园氛围音与音效开关（玄参 2026-09-28）：花园页也应用一次最新设置，
      // 保证从家长端改完开关回到花园立即生效（专注页进页时也会应用一次）。
      ref.read(audioServiceProvider).applySettings(
            soundOn: settings.soundOn,
            bgmOn: settings.bgmOn,
          );
      _species = await ref.read(plantRepositoryProvider).species();
      // 变更 A/B：读取当前「可收集」的待收集奖励（开花瞬间 + 第二段）→ 花盆上方头顶图标，
      // 手动点击收集；同一株最多 2 条。
      _collectibles = await svc.collectibleBloomRewards(now);
      // 头顶图标美术资源集合（缺失回退内置 Icons）。
      _rewardAssets = await ref.read(rewardAssetsProvider.future);
      // 变更 B：碎片入口余额。
      _fragmentBalance =
          await ref.read(bloomRewardRepositoryProvider).premiumFragmentBalance();
      // 玄参 2026-09-27 物种表改版：持有的免费种植券（「选择要种」列表判免费）。
      _unlockedSpecies =
          await ref.read(bloomRewardRepositoryProvider).unlockedSpeciesIds();
      // 注意：养护额度不在这里取——草地不展示次数，额度由弹出的养护面板自行读取
      // （见 PlantCareCard），少一次查询，也避免两处口径漂移。
      _balance = await ref.read(sunlightRepositoryProvider).balance();
      _error = null;
      // 升级检测：与上一轮快照 diff，发现「阶段/开花」推进 → 播放成长过渡演出。
      _detectGrowthTransitions();
      // 花谢自动到账提示（有则可，无则静默）。
      if (autoSettled.isNotEmpty && mounted) {
        _snack('花朵凋谢，奖励已自动收下：${autoSettled.map(_outcomeParts).join('；')}');
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
    // 网格建好后，下一帧按实际滚动指标刷新滚动条可见性（仅溢出时显示）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollable());
  }

  /// 依据当前滚动指标刷新 [_gridScrollable]（仅内容溢出时显示滚动条）。
  void _syncScrollable() {
    if (!mounted || !_gridScroll.hasClients) return;
    final bool scrollable = _gridScroll.position.maxScrollExtent > 0;
    if (scrollable != _gridScrollable) {
      setState(() => _gridScrollable = scrollable);
    }
  }

  /// 执行养护动作：包裹异常 → SnackBar → 刷新 + 同步孩子端经济。返回是否成功（供成功提示用）。
  ///
  /// [_busy] 期间直接忽略后续点击：浇水额度靠账本判定，但连点会在两次异步扣账
  /// 完成前同时通过校验，故必须在 UI 侧加串行闸门。
  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    bool ok = false;
    try {
      await action();
      ref.read(economyRevisionProvider.notifier).state++;
      await _reload(silent: true);
      ok = true;
    } on PlantOperationException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return ok;
  }

  /// 花园页统一提示（儿童风浮空卡，2026-09-29 玄参：黑色默认 SnackBar 太丑）。
  void _snack(String msg) {
    if (mounted) showChildSnack(context, msg);
  }

  /// 点花盆里的植物 → 弹养护面板；面板关闭后**静默刷新草地**（进度条/形态可能变了）。
  ///
  /// 卡片自己负责读数据与动作（见 [PlantCareCard]），本页只做「打开 + 关闭后刷新」。
  /// 面板返回最后一次成功的养护类型（浇水/施肥），据此在该花盆位置播放一次性动效。
  Future<void> _openCareSheet(String plantId, int potIndex) async {
    final CareEffectType? effect = await showPlantCareCard(context, plantId);
    if (!mounted) return;
    // 养护成功 → 在该花盆位置播放一次性动效（动效结束自动移除自身）。
    if (effect != null) _playCareEffect(potIndex, effect);
    await _reload(silent: true);
  }

  /// 手动收集一条待收集奖励（变更 A/B + v12，花盆上方头顶图标点击）：调服务发放并刷新，
  /// 成功后按**实际发放结果**提示（数值从 [BloomRewardOutcome] 拼、不写死）。
  ///
  /// 点击任一图标 = 收下该条 pending 的**全部**奖励（按条收集）；文案区分「开花瞬间」
  /// （`+10 ☀ 阳光` / `+10 ☀ 阳光 · +1 植物碎片` / `+10 ☀ 阳光 · 掉落「番茄」种子`）与
  /// 「第二段」（前缀「盛开的礼物：」）。
  Future<void> _collectReward(PendingBloomReward reward) async {
    if (_busy) return;
    setState(() => _busy = true);
    BloomRewardOutcome? outcome;
    try {
      outcome = await ref
          .read(plantGrowthServiceProvider)
          .collectBloomReward(reward.id, DateTime.now());
      ref.read(economyRevisionProvider.notifier).state++;
      await _reload(silent: true);
    } on PlantOperationException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (outcome != null && mounted) {
      final String body = _outcomeParts(outcome);
      _snack(outcome.isInstantPhase ? body : '盛开的礼物：$body');
    }
  }

  /// 拔草 / 除虫（花园干扰物玩法，口径 C26）：**点图标即清除**，成功后在该花盆
  /// **正上方**浮一条提示（1.2s 自动消失），数值全部取自常量 —— 改奖励不用改 UI。
  ///
  /// 走 [_run]：异常 → SnackBar 分因提示；成功后 → 经济修订号自增 + 静默刷新
  /// （杂草消失、进度条恢复涨动）。
  ///
  /// ⚠️ [_busy] 闸门在这里同样必要：浮标与整格是**嵌套热区**，若手势穿透导致
  /// 同一帧触发两次，第二次会被 [_run] 挡掉，不会写出两条阳光账本行。
  Future<void> _clearPest(String plantId, int potIndex, {required bool weed}) async {
    final bool ok = await _run(() {
      final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
      final DateTime now = DateTime.now();
      return weed ? svc.clearWeed(plantId, now) : svc.clearPest(plantId, now);
    });
    if (!ok || !mounted) return;
    final String text = weed
        ? '${kGardenWeedEmoji} 除草 +${kGardenWeedReward.toInt()} ☀'
        : '${kGardenPestEmoji} 除虫 +${kGardenPestReward.toInt()} ☀';
    setState(() => _clearHint = (potIndex: potIndex, text: text));
    _clearHintTimer?.cancel();
    _clearHintTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _clearHint = null);
    });
  }

  /// 把一条奖励结果拼成用户可见文案（`+N ☀ 阳光` / `+N 植物碎片` / `掉落「X」种子` /
  /// `重复的「X」种子已分解为 N 植物碎片`）。
  String _outcomeParts(BloomRewardOutcome o) {
    final List<String> parts = <String>[];
    if (o.sunlight > 0) parts.add('+${o.sunlight} ☀ 阳光');
    if (o.decomposedSeedSpeciesId != null) {
      // 重复种子自动分解（玄参 2026-09-29）：此时 fragments 即分解所得，勿重复拼「+N 植物碎片」。
      parts.add(
          '重复的「${_speciesNameById(o.decomposedSeedSpeciesId!)}」种子已分解为 ${o.fragments} 植物碎片');
    } else {
      if (o.fragments > 0) parts.add('+${o.fragments} 植物碎片');
      final String? seed = o.seedSpeciesId;
      if (seed != null) parts.add('掉落「${_speciesNameById(seed)}」种子');
    }
    return parts.isEmpty ? '收到一份小礼物～' : parts.join(' · ');
  }

  /// 按物种 id 取显示名（找不到返回 id 本身）。
  String _speciesNameById(String speciesId) {
    for (final PlantSpecies sp in _species) {
      if (sp.id == speciesId) return sp.name;
    }
    return speciesId;
  }

  /// 打开「精品碎片」信息页（玄参 2026-09-28 计价模型）。
  ///
  /// **只读**：展示当前碎片余额 + 「各物种可用支付方式」，引导孩子去空花盆兑换种下。
  /// 旧「满 8 片手动解锁精品物种」体系已废弃（`unlockPremiumSpecies` 删除），本页**不含任何
  /// 解锁按钮**。打开时重新读取余额 / 物种（避免用缓存读到过期数据）。
  Future<void> _openFragmentSheet() async {
    final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
    final int balance = await svc.premiumFragmentBalance();
    final List<PlantSpecies> species =
        await ref.read(plantRepositoryProvider).species();
    // 各物种可用支付方式（名称 + 选项），顺序 = 物种表顺序。
    final List<({String name, List<PlantPaymentOption> options})> needs =
        <({String name, List<PlantPaymentOption> options})>[];
    for (final PlantSpecies sp in species) {
      final List<PlantPaymentOption> opts = await svc.plantPaymentOptions(sp);
      needs.add((name: sp.name, options: opts));
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => _FragmentSheet(
        balance: balance,
        needs: needs,
      ),
    );
  }

  /// 打开「花期调试」面板（**仅 debug**）：验收花开花谢链路用。
  ///
  /// 面板内所有动作都「写字段 + tickAll」走真实领域结算；动作后回调静默刷新草地
  /// （进度 / 可收集气泡 / 余额）。release 构建下入口不渲染，本方法不会被触达。
  Future<void> _openDebugPanel() {
    return showBloomDebugPanel(
      context,
      onChanged: () {
        if (mounted) _reload(silent: true);
      },
    );
  }

  /// 懒取某花盆格的稳定 GlobalKey（用于定位其屏幕坐标）。
  GlobalKey _potKey(int potIndex) =>
      _potKeys.putIfAbsent(potIndex, GlobalKey.new);

  /// 在指定花盆位置叠加一次性养护动效。
  ///
  /// 通过计算该花盆格相对页面根 Stack 的本地坐标，用 [Positioned] 把 [CareEffectOverlay]
  /// 精确摆到花盆上。若此时花盆未布局（context 为空，极端情况）则静默跳过，不抛错。
  ///
  /// 2026-09-28 起：效果帧序列（`assets/fx/care/{water|fertilize}`）+ 对应音频，
  /// 「帧速 = 音频时长」（玄参口径）；音频经 [AudioService.playSfx]（受「音效」开关控制）。
  void _playCareEffect(int potIndex, CareEffectType type) {
    final BuildContext? potCtx = _potKey(potIndex).currentContext;
    final BuildContext? stackCtx = _pageStackKey.currentContext;
    if (potCtx == null || stackCtx == null || !mounted) return;
    final RenderBox? potBox = potCtx.findRenderObject() as RenderBox?;
    final RenderBox? stackBox = stackCtx.findRenderObject() as RenderBox?;
    if (potBox == null || stackBox == null) return;
    final Offset local = stackBox.globalToLocal(potBox.localToGlobal(Offset.zero));
    final Plant? plant = _occupantOf(potIndex);
    final PlantSpecies? species =
        plant == null ? null : _speciesOf(plant);
    if (!mounted) return;
    final List<String> frames;
    final int durationMs;
    final AudioCue cue;
    switch (type) {
      case CareEffectType.water:
        frames = fxFrameAssets(kCareWaterFxDir, kFxFrameCount);
        durationMs = kCareWaterDurationMs;
        cue = AudioCue.careWater;
      case CareEffectType.fertilize:
        frames = fxFrameAssets(kCareFertilizeFxDir, kFxFrameCount);
        durationMs = kCareFertilizeDurationMs;
        cue = AudioCue.careFertilize;
    }
    AudioService.instance.playSfx(cue);
    setState(() => _activeEffect = _CareEffectSpec(
          type: type,
          offset: local,
          size: potBox.size,
          plant: plant,
          species: species,
          frames: frames,
          durationMs: durationMs,
        ));
  }

  /// 与上一轮快照 diff 出「升级」并触发生长演出（玄参 2026-09-28 拍板三段全播）。
  ///
  /// 判定（每株植物 `stage:status` 快照对比）：
  ///  · `seed → sprout` → [GrowTransition.seedToSprout]；
  ///  · `sprout → adult` → [GrowTransition.sproutToAdult]；
  ///  · adult 且 `growing → bloomed` → [GrowTransition.adultToBloomed]（开花也算升级）。
  /// 花谢回落（`bloomed → growing`）与枯萎/死亡**不播**（欢快动画配上蔫花很怪）；
  /// 同帧多株升级只播第一株（现实里几乎不会同 tick 多株推进）。
  void _detectGrowthTransitions() {
    final Map<String, String> current = <String, String>{};
    for (final Plant p in _plants) {
      current[p.id] = '${p.stage.name}:${p.status.name}';
    }
    final Map<String, String> prev = _lastPhases;
    _lastPhases = current;
    if (prev.isEmpty) return; // 首次加载：不触发
    for (final Plant p in _plants) {
      final String? before = prev[p.id];
      if (before == null || before == current[p.id]) continue;
      if (p.status == PlantStatus.wilting || p.status == PlantStatus.dead) {
        continue; // 枯萎/死亡态不播欢快动画
      }
      final List<String> parts = before.split(':');
      final String prevStage = parts[0];
      final String prevStatus = parts[1];
      GrowTransition? t;
      if (prevStage == PlantStage.seed.name &&
          p.stage == PlantStage.sprout) {
        t = GrowTransition.seedToSprout;
      } else if (prevStage == PlantStage.sprout.name &&
          p.stage == PlantStage.adult) {
        t = GrowTransition.sproutToAdult;
      } else if (p.stage == PlantStage.adult &&
          prevStage == PlantStage.adult.name &&
          prevStatus != PlantStatus.bloomed.name &&
          p.status == PlantStatus.bloomed) {
        t = GrowTransition.adultToBloomed;
      }
      if (t != null) {
        _playGrowthFx(t);
        return; // 一帧只播一场演出
      }
    }
  }

  /// 播放「屏幕中央焦点卡片」成长演出（玄参 2026-09-29 口径）+ 对应成长音频。
  ///
  /// 不再按花盆格定位（旧口径格子太小、与底层重叠显得乱）：卡片由
  /// [GrowthFxOverlay] 自己在屏幕正中渲染，播完整卡淡出后由 [onComplete] 移除。
  void _playGrowthFx(GrowTransition transition) {
    if (!mounted) return;
    AudioService.instance.playSfx(_growthCue(transition));
    setState(() => _activeGrowth = _GrowthFxSpec(
          transition: transition,
          title: _growthTitle(transition),
        ));
  }

  /// 成长演出卡片标题文案（单一真源，勿散在 build 里）。
  String _growthTitle(GrowTransition t) {
    switch (t) {
      case GrowTransition.seedToSprout:
        return '发芽啦！🌱';
      case GrowTransition.sproutToAdult:
        return '长大啦！🌿';
      case GrowTransition.adultToBloomed:
        return '开花啦！🌻';
    }
  }

  /// 成长过渡对应的音频 cue。
  AudioCue _growthCue(GrowTransition t) {
    switch (t) {
      case GrowTransition.seedToSprout:
        return AudioCue.growthSeedToSprout;
      case GrowTransition.sproutToAdult:
        return AudioCue.growthSproutToAdult;
      case GrowTransition.adultToBloomed:
        return AudioCue.growthAdultToBloomed;
    }
  }

  /// 按花园 tab 可见性启停氛围音计时器（build 内调用，无 setState，幂等）。
  ///
  /// 外壳用 IndexedStack 保活 tab：切走不 dispose，故用 `TickerMode.of` 判可见性
  /// （外壳对隐藏 tab 包了 `TickerMode(enabled: false)`，切换会触发本页重建）。
  /// 进入花园立即播一次，之后每 [kGardenAmbientIntervalSeconds] 秒一次；离开即停。
  void _syncAmbientTimer() {
    if (_ambientActive && _ambientTimer == null) {
      AudioService.instance.playGardenAmbient();
      _ambientTimer = Timer.periodic(
        const Duration(seconds: kGardenAmbientIntervalSeconds),
        (_) => AudioService.instance.playGardenAmbient(),
      );
    } else if (!_ambientActive && _ambientTimer != null) {
      _ambientTimer!.cancel();
      _ambientTimer = null;
      unawaited(AudioService.instance.stopGardenAmbient());
    }
  }

  /// 打开「玩法说明」弹窗（容量 / 种植 / 养护 / 生长 / 枯萎开花 / 扩容）。
  ///
  /// 全部数字取自 prd_params 常量或当前 state（见 [GardenHelpSheet]），无裸字面量。
  Future<void> _showGardenHelp() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => GardenHelpSheet(
        capacity: _capacity,
        expandCost: _expandCost,
      ),
    );
  }

  /// 扩容确认：先弹卡写明「当前阳光 / 将扣除多少 / 容量 N → N+1」，
  /// **只有点「确定，扣除」才真正调 `expandPot`**；点「取消」什么都不做、一分不扣。
  ///
  /// 仍经 [_run] 执行（异常 SnackBar + 经济修订号自增 + 静默刷新）。
  ///
  /// ⚠️ 2026-09-24 起本方法还承担**阳光不足时的分因提示**：`ExpandPotSlot`
  /// 在阳光不足时不再拦点击（旧口径 onTap: null → 孩子点了毫无反馈，被玄参
  /// 判定为缺陷），落到这里的兜底提示成了唯一反馈路径，文案要可执行。
  Future<void> _confirmAndExpand() async {
    if (_capacity >= kGardenPotCapacityMax || _busy) return;
    final int cost = _expandCost;
    // 阳光不足：不给确认卡，直接分因提示（此时格子虽可点，但绝不扣费）。
    if (_balance < cost) {
      _snack('阳光不足，还差 ${(cost - _balance).ceil()} ☀ —— 去专注赚阳光吧');
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('要给花园腾一个花盆吗？'),
        content: Text(
          '当前阳光：${_balance.toInt()} ☀\n'
          '本次扩容将扣除：$cost ☀\n'
          '花园容量：$_capacity 盆 → ${_capacity + 1} 盆',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定，扣除'),
          ),
        ],
      ),
    );
    if (ok != true) return; // 取消 / 关闭对话框 → 不扣任何阳光
    await _run(() =>
        ref.read(plantGrowthServiceProvider).expandPot(DateTime.now()));
  }

  /// 打开「选择要种的植物」弹窗（玄参 2026-09-28 计价模型：每个物种展示可用支付方式按钮）。
  ///
  /// 列表顺序 = 物种表顺序（向日葵第一、月光兰第二…）。每项展示：
  ///  · 向日葵 → 一个「免费」按钮（直接种）；
  ///  · 普通 → 两个按钮「400 阳光」「6 植物碎片」，各自按余额 enabled/disabled；
  ///  · 精英 → 一个「10 植物碎片」按钮（不足禁用）；
  ///  · 每物种同时仅一株仍按 `hasAlive` 判「成长中」禁用。
  /// 点击某支付方式按钮 → 关闭弹窗后 `plant(..., payWith: kind)`。
  ///
  /// 计价口径与领域层 [PlantGrowthService.plantPaymentOptions] **一致**（单点真源）。
  Future<void> _openPlantSheet(int potIndex) async {
    final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
    final List<({PlantSpecies sp, List<_PlantPaymentButton> buttons})> rows =
        <({PlantSpecies sp, List<_PlantPaymentButton> buttons})>[];
    for (final PlantSpecies sp in _species) {
      rows.add((sp: sp, buttons: await _plantPaymentButtons(sp, svc)));
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('选择要种的植物',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Text('当前阳光：${_balance.toInt()} ☀ · 植物碎片：$_fragmentBalance',
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          for (final ({PlantSpecies sp, List<_PlantPaymentButton> buttons}) e in rows)
            _PlantTile(
              species: e.sp,
              buttons: e.buttons,
              // 种子徽章（玄参 2026-09-29）：持有该物种免费种植券（掉落过种子且已收集）→ 卡片打「🌰 种子」标。
              hasSeed: _unlockedSpecies.contains(e.sp.id),
              onPay: (PlantCostKind kind) async {
                Navigator.of(ctx).pop();
                await _run(() => ref
                    .read(plantGrowthServiceProvider)
                    .plant(e.sp.id, potIndex, DateTime.now(), payWith: kind));
              },
            ),
        ],
      ),
    );
  }

  /// 计算某物种在「选择要种的植物」弹窗里的可用支付方式按钮（可用性 + 文案 + 禁用原因）。
  ///
  /// 计价口径与领域层 [PlantGrowthService.plantPaymentOptions] **一致**（单点真源）；
  /// 依赖账本与余额 → 异步，UI 不得自行重算价格：
  ///  · 已有存活植株（`status != dead`，凋萎仍算存活）→ 全部按钮禁用，原因「成长中」；
  ///  · 否则按 [PlantPaymentOption]：free→「免费」；sunlight→「N 阳光」（阳光不足禁用）；
  ///    fragments→「N 植物碎片」（碎片不足禁用并写明当前片数）。
  Future<List<_PlantPaymentButton>> _plantPaymentButtons(
    PlantSpecies sp,
    PlantGrowthService svc,
  ) async {
    final bool hasAlive = _plants.any(
      (Plant p) => p.speciesId == sp.id && p.status != PlantStatus.dead,
    );
    final List<PlantPaymentOption> options = await svc.plantPaymentOptions(sp);
    final List<_PlantPaymentButton> buttons = <_PlantPaymentButton>[];
    for (final PlantPaymentOption opt in options) {
      String label;
      bool enabled;
      String? reason;
      switch (opt.kind) {
        case PlantCostKind.free:
          // 种子券入口（玄参 2026-09-29）：非初始物种的免费项 = 持有该物种种子，文案点明来源。
          label = sp.id == kStarterSpeciesId ? '免费' : '用种子种（免费）';
          enabled = !hasAlive;
          reason = hasAlive ? '成长中' : null;
        case PlantCostKind.sunlight:
          label = '${opt.amount} 阳光';
          if (hasAlive) {
            enabled = false;
            reason = '成长中';
          } else if (_balance < opt.amount) {
            enabled = false;
            reason = '阳光不足';
          } else {
            enabled = true;
          }
        case PlantCostKind.fragments:
          label = '${opt.amount} 植物碎片';
          if (hasAlive) {
            enabled = false;
            reason = '成长中';
          } else if (_fragmentBalance < opt.amount) {
            enabled = false;
            reason = '植物碎片不足（当前 $_fragmentBalance 片）';
          } else {
            enabled = true;
          }
      }
      buttons.add(_PlantPaymentButton(
        kind: opt.kind,
        amount: opt.amount,
        label: label,
        enabled: enabled,
        disabledReason: reason,
      ));
    }
    return buttons;
  }

  /// 按 potIndex 找到占用该花盆的植物（无则 null）。
  Plant? _occupantOf(int potIndex) {
    for (final Plant p in _plants) {
      if (p.potIndex == potIndex) return p;
    }
    return null;
  }

  PlantSpecies _speciesOf(Plant plant) {
    for (final PlantSpecies s in _species) {
      if (s.id == plant.speciesId) return s;
    }
    // 种子数据变更/物种缺失时的兜底：不显示空白格。
    return PlantSpecies(
      id: plant.speciesId,
      name: '未知植物',
      rarity: Rarity.common,
      baseCostHigh: 0,
      baseCostLow: 0,
      growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
    );
  }

  /// 物种档位查询（物种缺失时按普通档兜底）——种子奖励图标据此选分档图。
  bool _isPremiumSpecies(String speciesId) {
    for (final PlantSpecies s in _species) {
      if (s.id == speciesId) return s.isPremium;
    }
    return false;
  }

  /// 草地上的格子：0..capacity-1 是花盆（空/有植物），末尾追加「加盆」格（未达上限时）。
  ///
  /// 变更 A/B + v12 图标化：有植物且存在「可收集」待收集奖励的花盆，**花盆上方**叠加一排
  /// 头顶奖励图标（`Positioned` 叠加、**不占布局高度**，避免改动矮屏测试钉死的网格高度）。
  /// 图标由奖励三列（阳光 / 植物碎片 / 种子）派生，点击任一图标 = 收下该条 pending 全部奖励。
  List<Widget> _buildCells() {
    final List<Widget> cells = <Widget>[];
    for (int i = 0; i < _capacity; i++) {
      final Plant? occupant = _occupantOf(i);
      if (occupant == null) {
        cells.add(EmptyPot(potIndex: i, onTap: () => _openPlantSheet(i)));
      } else {
        final Widget pot = GardenPot(
          key: _potKey(i),
          plant: occupant,
          species: _speciesOf(occupant),
          onTap: () => _openCareSheet(occupant.id, i),
          onClearWeed: () => _clearPest(occupant.id, i, weed: true),
          onClearPest: () => _clearPest(occupant.id, i, weed: false),
        );
        final List<PendingBloomReward> rewards =
            _collectibles[occupant.id] ?? const <PendingBloomReward>[];
        // ⚠️ StackFit.expand：让 GardenPot 仍收到「紧约束」（与直接嵌入网格一致）——
        // GardenPot 用 LayoutBuilder 按格宽推导高度，收到松约束会缩成内容高度而错位。
        // 这里**常驻** Stack（不再只在有奖励时包）：干扰物浮标与清除提示都要叠在盆上，
        // 且两者都是 Positioned、不占布局高度 → 草地网格高度不受影响。
        cells.add(Stack(
          fit: StackFit.expand,
          children: <Widget>[
            pot,
            if (rewards.isNotEmpty)
              // 头顶奖励图标：花盆上方、横向一排、整体居中；`Positioned` 叠加**不占布局高度**。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: BloomRewardIconsBar(
                    rewards: rewards,
                    availableAssets: _rewardAssets,
                    onCollect: _collectReward,
                    isPremiumOf: _isPremiumSpecies,
                  ),
                ),
              ),
            if (_clearHint?.potIndex == i)
              // 刚拔草 / 除虫的提示：浮在花盆正上方（玄参口径「在花盆上面显示提示」），
              // 1.2s 后自行消失；文案数值取常量，改奖励不用动 UI。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xEFFFFFFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _clearHint!.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
          ],
        ));
      }
    }
    if (_capacity < kGardenPotCapacityMax) {
      cells.add(ExpandPotSlot(
        cost: _expandCost,
        shortfall: (_expandCost - _balance).ceil(),
        busy: _busy,
        onTap: _confirmAndExpand,
      ));
    }
    return cells;
  }

  /// 正常态花盆区：**锁 2 行高度 + 溢出时区域内纵向滚动**。
  ///
  /// 可视高度的**唯一真源**是纯函数 [gardenGridVisibleHeight]（页面不再自己内联算行高/行数，
  /// 「改行数 → 测试必红」）。网格区顶部取自 `LayoutBuilder` 的剩余高度，底界取自背景图映射
  /// [gardenPotAreaBottom]，保证滚动时花盆永不压到背景植物。
  Widget _buildGardenBody(Size size) {
    final double potAreaBottom = gardenPotAreaBottom(size);
    const double pagePadH = 12;
    const double gridSpacing = 6;
    final double gridInnerWidth = size.width - pagePadH * 2;

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        // 把整块可摆区高度锁在背景「菜地上沿」之内（[gardenPotAreaBottom]）。
        height: potAreaBottom,
        child: Padding(
          // 底部 padding 交给纯函数的 bottomInset（12px 呼吸间距，不再为已删白块留位）。
          padding: const EdgeInsets.fromLTRB(pagePadH, 12, pagePadH, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 独立路由 /garden 没有 shell 的 AppBar 胶囊，故在内容区左上角补一个；
              // 内嵌（花园 tab）时由 shell AppBar 提供，避免重复。
              //
              // ⚠️ 此处**不加任何额外顶栏**：花盆网格的可视高度由纯函数
              // [gardenGridVisibleHeight] 单独钉死（矮屏用例要求顶部无多余占位），
              // 故「精品碎片」入口改为根 Stack 的浮层（见 build 内 Positioned）。
              if (!widget.embedded) ...<Widget>[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SunlightPill(),
                ),
                const SizedBox(height: 10),
              ],
              // Flexible（loose）：网格区占据「网格顶部 → 底界」的剩余高度；用 LayoutBuilder
              // 量出该剩余高度 → 还原网格区顶部 y → 交给纯函数算「锁 2 行 + 不越菜地上沿」。
              Flexible(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final double firstRowTop = potAreaBottom - c.maxHeight;
                    final double viewport = gardenGridVisibleHeight(
                      box: size,
                      gridInnerWidth: gridInnerWidth,
                      firstRowTop: firstRowTop,
                      cellAspectRatio: GardenGrid.cellAspectRatio,
                      spacing: gridSpacing,
                      bottomInset: 12,
                    );
                    // 网格**本帧**就布局完成 → 帧末按真实滚动指标刷新滚动条可见性。
                    // ⚠️ 不能只在 `_reload` 的帧末检查：那时网格还没建好，永远读不到溢出；
                    // 也不能只靠 `ScrollMetricsNotification`：首次布局的指标通知不保证派发。
                    // `_syncScrollable` 内部按「maxScrollExtent > 0」判定且仅在变化时 setState，
                    // 收敛后不再触发帧，不会空转。
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _syncScrollable());
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: double.infinity,
                        height: viewport,
                        child: Scrollbar(
                          controller: _gridScroll,
                          thumbVisibility: _gridScrollable,
                          radius: const Radius.circular(6),
                          child: SingleChildScrollView(
                            controller: _gridScroll,
                            physics: const ClampingScrollPhysics(),
                            child: GardenGrid(cells: _buildCells()),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ IndexedStack 保活数据陈旧回归（2026-09-23 真机 Bug）：外壳切 tab 不重建本页，
    // initState 只跑一次 → 别处（专注结算 / 商店核销 / 「我的」页操作）变更余额后，
    // 本页缓存的 _balance 仍是旧值 → 加盆格误算「还差 N☀」被判不可点（点击无响应）。
    // 修法：监听经济修订号，任何入账/扣账后静默重读（silent 避免闪全屏 loading）。
    // ref.listen 只能写在 build() 内（写在 initState 会触发框架断言）。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _reload(silent: true);
    });

    // 花园氛围音可见性（玄参 2026-09-28）：花园 tab 可见才播、切走即停。
    // 外壳 IndexedStack 保活 + 对隐藏 tab 包 TickerMode(enabled:false) → 切 tab 会
    // 触发本页重建，这里按 TickerMode 可见性幂等启停计时器（无 setState，纯副作用闸门）。
    final bool gardenVisible =
        !widget.embedded || TickerMode.valuesOf(context).enabled;
    if (gardenVisible != _ambientActive) {
      _ambientActive = gardenVisible;
      _syncAmbientTimer();
    }

    // 整页草地背景：铺满页面 body（内嵌 tab 用 SafeArea、独立路由用 Scaffold body），
    // 图片缺失/失败回退到绿色渐变。阳光胶囊与木牌热区都叠在图片之上。
    final Widget background = Positioned.fill(
      child: Image.asset(
        'assets/garden/background.png',
        fit: BoxFit.cover,
        errorBuilder: (
          BuildContext context,
          Object error,
          StackTrace? stackTrace,
        ) =>
            Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFBFE6A8), Color(0xFF8FCF74)],
            ),
          ),
        ),
      ),
    );

    // LayoutBuilder 拿到 body 可用尺寸：用于把木牌热区与花盆区底界都映射到背景图上。
    final Widget page = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final Widget content;
        if (_loading) {
          content = const Center(child: CircularProgressIndicator());
        } else if (_error != null) {
          content = Center(child: Text('加载失败：$_error'));
        } else {
          content = _buildGardenBody(size);
        }

        // 整页叠放：背景铺满 → 内容区（锁 2 行 + 区域内滚动）→ 左下角木牌热区
        // → 养护成功的一次性动效叠加层（仅播放期间存在）。
        // 木牌在左下、花盆区在中上部，互不重叠，故不会挡住花盆点击。
        // ⚠️ `clipBehavior: Clip.none`（2026-09-29）：养护效果帧按玄参口径「略大于格宽、
        // 允许越界」，帧顶部会落在花盆格**上方**（水壶 / 肥料袋位置）。Stack 默认
        // `hardEdge` 会把越界部分裁掉 → 只看得到水柱看不到壶。
        return Stack(
          key: _pageStackKey,
          clipBehavior: Clip.none,
          children: <Widget>[
            background,
            Positioned.fill(child: content),
            Positioned.fromRect(
              rect: gardenSignScreenRect(size),
              child: GardenSignHotspot(onTap: _showGardenHelp),
            ),
            // 精品碎片入口（变更 B）：根 Stack 浮层——**不占布局高度**，避免改动花盆网格
            // 的可视高度（矮屏用例硬钉该高度）。落在右下角草地空位（左下角是木牌）。
            if (!_loading && _error == null)
              Positioned(
                right: 12,
                bottom: 12,
                child: _FragmentEntry(
                  balance: _fragmentBalance,
                  onTap: _openFragmentSheet,
                ),
              ),
            // 「花期调试」入口（**仅 kDebugMode**）：同样为根 Stack 浮层——紧凑、不占布局
            // 高度（避免把矮屏用例顶出视口 / 触发 overflow），release 构建自动不渲染。
            // 摆在右上角（左上角是阳光胶囊、左下角木牌、右下角碎片入口）。
            if (kDebugMode && !_loading && _error == null)
              Positioned(
                top: 12,
                right: 12,
                child: BloomDebugEntry(onTap: _openDebugPanel),
              ),
            // 养护成功动效：精确摆到对应花盆格之上（效果帧叠加 + 音频），有限时长，结束自移除。
            if (_activeEffect != null)
              Positioned(
                left: _activeEffect!.offset.dx,
                top: _activeEffect!.offset.dy,
                width: _activeEffect!.size.width,
                height: _activeEffect!.size.height,
                child: CareEffectOverlay(
                  type: _activeEffect!.type,
                  plant: _activeEffect!.plant,
                  species: _activeEffect!.species,
                  frames: _activeEffect!.frames,
                  durationMs: _activeEffect!.durationMs,
                  width: _activeEffect!.size.width,
                  height: _activeEffect!.size.height,
                  onComplete: () {
                    if (mounted) setState(() => _activeEffect = null);
                  },
                ),
              ),
            // 成长过渡演出（玄参 2026-09-29 改口径）：**屏幕中央焦点卡片**内放大播放
            // 序列帧 + 成长音频，播完整卡淡出（组件内部处理），结束自移除。
            if (_activeGrowth != null)
              Positioned.fill(
                child: GrowthFxOverlay(
                  frames: fxFrameAssets(
                    growFxDir('sunflower', _activeGrowth!.transition),
                    kFxFrameCount,
                  ),
                  durationMs: _activeGrowth!.transition.durationMs,
                  title: _activeGrowth!.title,
                  onComplete: () {
                    if (mounted) setState(() => _activeGrowth = null);
                  },
                ),
              ),
          ],
        );
      },
    );

    // 内嵌（花园 tab）时不叠加第二层 Scaffold/AppBar，直接返回内容。
    if (widget.embedded) {
      return SafeArea(child: page);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的花园'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新成长',
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      body: page,
    );
  }
}

/// 花园「选择要种的植物」弹窗里某个支付方式按钮的展示模型。
class _PlantPaymentButton {
  const _PlantPaymentButton({
    required this.kind,
    required this.amount,
    required this.label,
    required this.enabled,
    this.disabledReason,
  });

  /// 支付方式（免费 / 阳光 / 碎片）。
  final PlantCostKind kind;

  /// 数量（阳光片数 / 碎片片数）。
  final int amount;

  /// 按钮文案（如「免费」「400 阳光」「10 植物碎片」）。
  final String label;

  /// 是否可点击种下（false = 置灰，如已有存活植株 / 余额不足）。
  final bool enabled;

  /// 禁用原因（余额不足 / 成长中），仅 [enabled] 为 false 时有值。
  final String? disabledReason;
}

/// 稀有度 UI 文案（玄参 2026-09-27 物种表改版：**只显示两档**）。
///
/// `common → 普通`；其余（`rare` / `legendary`）一律 → `精英`（legendary 暂无物种，
/// 枚举保留不动，此处兜底归并到精英）。作为库级顶层函数，供 `_PlantTile` 等小组件复用。
String _rarityLabel(Rarity r) => r == Rarity.common ? '普通' : '精英';

/// 单个物种的选种卡片：名称 + 稀有度标签 +（持有种子时）种子徽章 + 一排支付方式按钮。
class _PlantTile extends StatelessWidget {
  const _PlantTile({
    required this.species,
    required this.buttons,
    required this.onPay,
    this.hasSeed = false,
  });

  final PlantSpecies species;
  final List<_PlantPaymentButton> buttons;
  final void Function(PlantCostKind kind) onPay;

  /// 是否持有该物种的免费种植券（掉落过种子且已收集）→ 显示种子徽章。
  final bool hasSeed;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.local_florist, color: Color(0xFF7CB342)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(species.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (hasSeed) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1C2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF6C445)),
                    ),
                    // 种子美术图（2026-10-03 玄参提供分档图）：按物种档位选
                    // seed_premium / seed_common；缺失回退 🌰 emoji。
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Image.asset(
                          species.isPremium
                              ? 'assets/rewards/seed_premium.png'
                              : 'assets/rewards/seed_common.png',
                          width: 16,
                          height: 16,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (BuildContext _, Object __, StackTrace? ___) =>
                                  const Text('🌰',
                                      style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 3),
                        const Text('种子',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF8D6E00))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3EBD8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_rarityLabel(species.rarity),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8A5A00))),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: buttons.map((_PlantPaymentButton b) {
                return _PayButtonWidget(
                  label: b.label,
                  enabled: b.enabled,
                  disabledReason: b.disabledReason,
                  onTap: b.enabled ? () => onPay(b.kind) : null,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 大圆角马卡龙风格支付按钮（儿童友好）。
class _PayButtonWidget extends StatelessWidget {
  const _PayButtonWidget({
    required this.label,
    required this.enabled,
    this.disabledReason,
    this.onTap,
  });

  final String label;
  final bool enabled;
  final String? disabledReason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg = enabled ? const Color(0xFF8FCF74) : Colors.grey.shade300;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: enabled ? Colors.white : Colors.grey.shade600,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            textStyle: const TextStyle(fontSize: 15),
          ),
          child: Text(label),
        ),
        if (!enabled && disabledReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(disabledReason!,
                style: const TextStyle(fontSize: 11, color: Colors.red)),
          ),
      ],
    );
  }
}

/// 花园页「精品碎片」入口（玄参 2026-09-27 物种表改版）：只展示碎片余额数字。
///
/// 旧「N/阈值 + 满阈值高亮」已废弃（阈值体系删除）；点击打开只读信息页 [_FragmentSheet]。
class _FragmentEntry extends StatelessWidget {
  const _FragmentEntry({
    required this.balance,
    required this.onTap,
  });

  /// 当前碎片余额。
  final int balance;

  /// 点击回调（打开碎片信息页）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 碎片美术图（2026-10-03 玄参提供）：透明底裸图；缺失回退拼图 Icon。
              Image.asset(
                'assets/rewards/fragment.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    const Icon(
                  Icons.extension,
                  size: 16,
                  color: Color(0xFF9C917C),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '植物碎片 $balance',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B6252),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「精品碎片」信息页（玄参 2026-09-27 物种表改版）：**只读**。
///
/// 展示当前余额 + 各需碎片物种及所需片数，并提示「去空花盆挑选植物兑换」；不含解锁按钮
/// （兑换在物种列表直接进行，见 `_openPlantSheet`）。
class _FragmentSheet extends StatelessWidget {
  const _FragmentSheet({
    required this.balance,
    required this.needs,
  });

  /// 当前碎片余额。
  final int balance;

  /// 各物种（名称 + 可用支付方式），顺序 = 物种表顺序（玄参 2026-09-28 计价模型）。
  final List<({String name, List<PlantPaymentOption> options})> needs;

  /// 单个支付选项的文案（与 `_plantPaymentButtons` 口径一致）。
  ///
  /// 免费 → 「免费」；阳光 → 「N 阳光」；碎片 → 「N 植物碎片」。
  static String _optionLabel(PlantPaymentOption opt) {
    switch (opt.kind) {
      case PlantCostKind.free:
        return '免费';
      case PlantCostKind.sunlight:
        return '${opt.amount} 阳光';
      case PlantCostKind.fragments:
        return '${opt.amount} 植物碎片';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          const Text(
            '植物碎片',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '当前植物碎片：$balance 片',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            '攒够植物碎片，或备好阳光后，去空花盆挑选植物就能兑换种下啦～',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          ...needs.map(
            (({String name, List<PlantPaymentOption> options}) need) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(
                  Icons.local_florist,
                  color: Color(0xFFE8A33D),
                ),
                title: Text(need.name),
                subtitle: Text(
                  need.options.length == 1
                      ? _optionLabel(need.options.first)
                      : need.options.map(_optionLabel).join(' 或 '),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
