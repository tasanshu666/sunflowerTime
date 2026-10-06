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
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/species_lore.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/bloom_reward_outcome.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_reward_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_artwork.dart';
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

  /// 动画播放完成后的业务收尾回调（2026-10-03 除草 / 除虫用）：在叠加层被移除前
  /// 执行（如「干扰物渐变消失 → 刷新草地 → 弹飘字」）。null = 只移除叠加层。
  final VoidCallback? onFinished;

  _CareEffectSpec({
    required this.type,
    required this.offset,
    required this.size,
    required this.frames,
    required this.durationMs,
    this.plant,
    this.species,
    this.onFinished,
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

  /// 花盆上方刚清除掉的干扰物提示（口径 C26 + 2026-10-03 飘字口径）：
  /// `potIndex` 指明浮在哪一格；`label` = 「除草成功」/「除虫成功」；
  /// `sunlight` = 奖励阳光数（**渲染成阳光图标 + 「+N」**，玄参 2026-10-03 口径：
  /// 「阳光+1」的阳光二字要用图标不是文字，「就像之前那样显示」= 与头顶奖励
  /// 图标同源 `assets/rewards/sunlight.png`，缺失回退内置 `Icons.wb_sunny`）。
  /// 由 [_RisingHint] 自下而上飘动淡出（约 1.6s），走完经 onComplete 自清；
  /// 只保留**最后一条**（同格连点时后一条覆盖前一条）。
  ({int potIndex, String label, int sunlight})? _clearHint;

  /// 除草 / 除虫收尾序列计时器：效果帧播完 → 等 [kPestFadeOutMs] 淡出 → 刷新 + 弹飘字。
  /// dispose 里必须取消（不碰 ref，纯 Timer）。
  Timer? _clearSeqTimer;

  /// 正在「渐变消失」的干扰物（2026-10-03 玄参口径：播完动画先淡出浮标再刷新草地）：
  /// `plantId` 定位植株、`weed` 区分杂草 / 蝗虫。淡出结束置 null。
  ({String plantId, bool weed})? _fadingClear;

  // ── 一键操作（口径 C29，玄参 2026-10-05 拍板）────────────────────────────

  /// 一键操作汇总飘字：完成后**页面顶部居中**飘出「一键XX成功 ×N」+ 阳光增减
  /// （扣费为负数，显示「-N」）。由 [_RisingHint] 走完自清。
  ({String label, int sunlight})? _batchHint;

  /// 一键操作的每盆**轻量反馈**（不做 4s 完整动效）：potIndex → 动效类型，
  /// 短暂显示约 1.1s 后整批清除。
  final Map<int, CareEffectType> _batchPulse = <int, CareEffectType>{};

  /// 每盆轻量反馈的整批清除计时器（dispose 必须取消）。
  Timer? _batchPulseTimer;

  /// 收集奖励的「向上飘走」幽灵动效（玄参 2026-10-05「用户点击之后，向上飘动，
  /// 慢慢消失」）。
  ///
  /// ⚠️ 实现口径（2026-10-05 二次修订）：**根 Overlay 浮层**，不再挂在花盆格
  /// Stack 里 —— 收集成功后的 `_reload` 会重建格子子树（无 key 子节点整体重挂），
  /// 格内 [CollectGhost] 的动画元素被销毁重建导致动效被打断（玄参实测「点阳光
  /// 直接消失」的根因）；根 Overlay 完全脱离页面重建树、且不受格内裁剪影响。
  /// 约 0.9s 走完自清 + 950ms 定时器兜底双保险。
  OverlayEntry? _collectGhostEntry;

  /// 幽灵兜底清除计时器（dispose 必须取消）。
  Timer? _collectGhostTimer;

  /// 刷新抑制闸门（2026-10-03 除草/除虫动效回归修复）：清除干扰物**已写库但动画
  /// 未播完**期间置 true，挡住 [_run] 内部的 `_reload(silent)` 与
  /// `economyRevisionProvider` 监听触发的静默刷新 —— 否则草/虫在动画播完前就
  /// 从草地消失（玄参真机反馈「点击草之后，草直接消失了」的根因）。
  /// 动画收尾（[_onClearAnimated]）复位并统一补一次刷新。
  bool _suppressReload = false;

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
    _clearSeqTimer?.cancel();
    _batchPulseTimer?.cancel();
    _collectGhostTimer?.cancel();
    _collectGhostEntry?.remove(); // 根 Overlay 浮层不随本页卸载，必须显式移除。
    _collectGhostEntry = null;
    unawaited(AudioService.instance.stopGardenAmbient());
    _gridScroll.dispose();
    super.dispose();
  }

  /// 扩容一只花盆的阳光价（按年段，§4.6）：供按钮文案与确认卡使用，避免裸字面量。
  int get _expandCost =>
      _tier == AgeTier.low ? kPlantPotExpandCostLow : kPlantPotExpandCostHigh;

  /// [silent] = true 时不整页转圈（养护动作后静默刷新），避免每次浇水都闪一次
  /// 全屏 loading，孩子看着像「页面重载」而不是「浇完了」。
  ///
  /// ⚠️ [_suppressReload] = true 期间一律跳过（除草/除虫动画播放中：数据已写库但
  /// 界面要等「播完 → 淡出」才更新，见 [_clearPest]）。
  Future<void> _reload({bool silent = false}) async {
    if (_suppressReload) return;
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
  /// 面板返回结果（C29 扩展）：浇水/施肥动效类型 → 在该花盆位置播放一次性动效；
  /// 铲除返还额 → 分因 SnackBar「铲除成功，返还 N ☀」（植物已删，飘字无格可挂）。
  Future<void> _openCareSheet(String plantId, int potIndex) async {
    final PlantCareResult result = await showPlantCareCard(context, plantId);
    if (!mounted) return;
    // 养护成功 → 在该花盆位置播放一次性动效（动效结束自动移除自身）。
    if (result.effect != null) _playCareEffect(potIndex, result.effect!);
    if (result.shovelRefund != null) {
      final int refund = result.shovelRefund!;
      _snack(refund > 0 ? '铲除成功，返还 $refund ☀' : '铲除成功');
    }
    await _reload(silent: true);
  }

  /// 点击头顶奖励图标（玄参 2026-10-05 动效口径）：先捕获本条图标规格并**就地起
  /// 「向上飘动 + 淡出」幽灵**（约 0.9s，纯视觉、不挡数据），随后**立即**走既有
  /// 收集流程（[_collectReward]：写库 → 刷新 → 分因提示）。
  ///
  /// 2026-10-06 玄参加收集音效（**统一一个**，不按图标分类——阳光 / 碎片 / 种子
  /// 共用 `collect_reward.mp3`，素材待交付缺失时静默跳过）；点击仍收下整条 pending。
  void _onCollectIconTap(int potIndex, PendingBloomReward reward, RewardIconSpec spec) {
    if (_busy) return; // 收集流程自带 _busy 闸门；动效期防重复点。
    AudioService.instance.playSfx(AudioCue.collectReward);
    _showCollectGhost(potIndex, rewardIconSpecsFor(reward, isPremiumOf: _isPremiumSpecies));
    unawaited(_collectReward(reward));
  }

  /// 在指定花盆格位置起「收集幽灵」根 Overlay 浮层（见 [_collectGhostEntry] 注释）。
  ///
  /// 位置用 [_potKey] 的 RenderBox 全局矩形（与养护动效同一定位源）；花盆尚未布局
  /// （极端情况）则静默跳过。资源缺失（测试环境）时 [CollectGhost] 无图可画 →
  /// 不可见，不产生 findable 节点。`IgnorePointer`：幽灵不挡任何命中。
  void _showCollectGhost(int potIndex, List<RewardIconSpec> specs) {
    _removeCollectGhost();
    final BuildContext? cellCtx = _potKey(potIndex).currentContext;
    if (cellCtx == null || !mounted) return;
    final RenderBox? rb = cellCtx.findRenderObject() as RenderBox?;
    if (rb == null || !rb.attached) return;
    final Rect rect = rb.localToGlobal(Offset.zero) & rb.size;
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext _) => Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: Center(
            child: CollectGhost(
              specs: specs,
              availableAssets: _rewardAssets,
              onComplete: _removeCollectGhost,
            ),
          ),
        ),
      ),
    );
    _collectGhostEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    // 兜底：动画 onEnd 因任何原因未触发（如页面被卸载重建）也保证浮层被清走。
    _collectGhostTimer = Timer(
      const Duration(milliseconds: 950),
      _removeCollectGhost,
    );
  }

  /// 移除收集幽灵浮层（幂等）。
  void _removeCollectGhost() {
    _collectGhostTimer?.cancel();
    _collectGhostTimer = null;
    _collectGhostEntry?.remove();
    _collectGhostEntry = null;
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

  /// 拔草 / 除虫（花园干扰物玩法，口径 C26 + 2026-10-03 动效口径）：
  /// 点图标 → 写库 → **播效果帧 + 音效**（期间 [_busy] 锁整页，防连点重复写账本）→
  /// 播完干扰物**渐变消失**（[kPestFadeOutMs] 淡出）→ 刷新草地 + 花盆上方弹
  /// 「XX成功，阳光+N」飘字（[_RisingHint]，自下而上飘动淡出）。数值全部取自常量。
  ///
  /// 走 [_run]：异常 → SnackBar 分因提示；成功后 → 经济修订号自增。
  ///
  /// ⚠️ [_busy] 闸门在这里同样必要：浮标与整格是**嵌套热区**，若手势穿透导致
  /// 同一帧触发两次，第二次会被 [_run] 挡掉，不会写出两条阳光账本行。
  Future<void> _clearPest(String plantId, int potIndex, {required bool weed}) async {
    // 先上抑制闸门再写库：[_run] 内部的 `_reload(silent)` 与 economyRevision 监听
    // 触发的刷新都必须被挡住，否则动画还没播草/虫就没了（玄参真机实证）。
    _suppressReload = true;
    final bool ok = await _run(() {
      final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
      final DateTime now = DateTime.now();
      return weed ? svc.clearWeed(plantId, now) : svc.clearPest(plantId, now);
    });
    if (!ok) {
      _suppressReload = false; // 写库失败（无草可除等）：恢复刷新，SnackBar 已给分因。
      return;
    }
    if (!mounted) return;
    // [_run] 的 finally 已解锁，这里重新锁上：动画播放期间（约 4.1s）整页不可再操作，
    // 防止动画中途再次点干扰物 / 养护（数据已写库但草地未刷新，界面与库不一致）。
    setState(() => _busy = true);
    _playCareEffect(
      potIndex,
      weed ? CareEffectType.weed : CareEffectType.pest,
      onFinished: () => _onClearAnimated(plantId, potIndex, weed: weed),
    );
  }

  /// 除草 / 除虫动画播完的业务收尾（玄参 2026-10-03 口径）：
  /// 1) 干扰物渐变消失：置 [_fadingClear] → 浮标透明度动画淡出（数据尚未刷新）；
  /// 2) 淡出结束 → 刷新草地（干扰物从数据层移除）+ 解锁整页；
  /// 3) 花盆上方弹「XX成功，阳光+N」飘字（[_RisingHint] 自下而上飘动淡出，走完自清）。
  void _onClearAnimated(String plantId, int potIndex, {required bool weed}) {
    if (!mounted) return;
    setState(() {
      _fadingClear = (plantId: plantId, weed: weed);
      _busy = false;
    });
    _clearSeqTimer?.cancel();
    _clearSeqTimer = Timer(const Duration(milliseconds: kPestFadeOutMs), () {
      if (!mounted) return;
      // 淡出结束：复位抑制闸门 → 刷新草地（草/虫此时才从数据层消失）→ 弹飘字。
      _suppressReload = false;
      setState(() {
        _fadingClear = null;
        _clearHint = (
          potIndex: potIndex,
          label: weed ? '除草成功' : '除虫成功',
          sunlight: (weed ? kGardenWeedReward : kGardenPestReward).toInt(),
        );
      });
      unawaited(_reload(silent: true));
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
  /// 打开「碎片与种子说明」卡（玄参 2026-10-06 口径修订：**屏幕中间弹出** +
  /// 内容**只讲三类资源的用途与获得方法**，不再逐物种列碎片价目；
  /// 入口 = 碎片 chip **与两个种子 chip**，点哪个都能打开）。
  Future<void> _openFragmentSheet() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (BuildContext ctx) => const _RewardCurrencyDialog(),
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
  /// 2026-10-03 扩展除草 / 除虫（`{weed|pest}`，27 帧），并支持 [onFinished] 业务收尾。
  void _playCareEffect(
    int potIndex,
    CareEffectType type, {
    VoidCallback? onFinished,
  }) {
    final BuildContext? potCtx = _potKey(potIndex).currentContext;
    final BuildContext? stackCtx = _pageStackKey.currentContext;
    if (potCtx == null || stackCtx == null || !mounted) {
      // 拿不到坐标（极端情况）也要保证业务收尾不丢：直接执行并退出。
      onFinished?.call();
      return;
    }
    final RenderBox? potBox = potCtx.findRenderObject() as RenderBox?;
    final RenderBox? stackBox = stackCtx.findRenderObject() as RenderBox?;
    if (potBox == null || stackBox == null) {
      onFinished?.call();
      return;
    }
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
      case CareEffectType.weed:
        frames = fxFrameAssets(kCareWeedFxDir, kCareWeedFrameCount);
        durationMs = kCareWeedDurationMs;
        cue = AudioCue.careWeed;
      case CareEffectType.pest:
        frames = fxFrameAssets(kCarePestFxDir, kCarePestFrameCount);
        durationMs = kCarePestDurationMs;
        cue = AudioCue.carePest;
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
          onFinished: onFinished,
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

  // ── 一键操作（口径 C29，玄参 2026-10-05 拍板）────────────────────────────

  /// 悬浮按钮出现条件：**存活株 ≥ [kOneClickMinPlants]**（「花园植物大于 3 盆」；
  /// 死亡残株不算）。订阅门控后补（当前所有孩子可用，玄参拍板）。
  bool get _showOneClickFab =>
      _plants.where((Plant p) => p.status != PlantStatus.dead).length >=
      kOneClickMinPlants;

  /// 一键操作入口（悬浮按钮下拉菜单选中后）：
  ///  1. [PlantGrowthService.oneClickPlan] 纯读计划（跳过已达上限 / 间隔中的株）；
  ///  2. 空计划 → 分因提示（「没有需要护理的植物」等）；
  ///  3. 阳光不足 → **整体拦截**（一株都不执行）+ 提示还差多少；
  ///  4. 确认卡（**明示合计价**）→ 确认才执行；
  ///  5. 逐株执行既有单株方法（各自再校验一次额度，幂等安全）→ 每盆轻量反馈 +
  ///     顶部汇总飘字「一键XX成功 ×N ☀-M」（护理为 ☀+M）。
  Future<void> _onOneClick(PlantOneClickKind kind) async {
    if (_busy) return;
    final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
    final DateTime now = DateTime.now();
    final OneClickPlan plan = await svc.oneClickPlan(kind, now);
    if (!mounted) return;
    switch (kind) {
      case PlantOneClickKind.water:
        if (plan.isEmpty) return _snack('今天没有可浇水的植物');
      case PlantOneClickKind.fertilize:
        if (plan.isEmpty) return _snack('今天没有可施肥的植物');
      case PlantOneClickKind.care:
        if (plan.isEmpty) return _snack('没有需要护理的植物');
    }
    // 阳光不足 → 整体拦截（玄参拍板：一株都不执行，避免「浇一半没阳光」的挫败）。
    if (kind != PlantOneClickKind.care && _balance < plan.totalCost) {
      _snack('阳光不足，还差 ${(plan.totalCost - _balance).ceil()} ☀ —— 去专注赚阳光吧');
      return;
    }
    // 确认卡：明示合计价 / 奖励口径。
    final String content = switch (kind) {
      PlantOneClickKind.water =>
        '将对 ${plan.plantIds.length} 盆植物各浇 1 次水\n'
            '合计扣除：${plan.totalCost} ☀（每盆 $kPlantWaterCost ☀）\n'
            '当前阳光：${_balance.toInt()} ☀',
      PlantOneClickKind.fertilize =>
        '将对 ${plan.plantIds.length} 盆植物各施 1 次肥\n'
            '合计扣除：${plan.totalCost} ☀（每盆 $kPlantFertilizeCost ☀）\n'
            '当前阳光：${_balance.toInt()} ☀',
      PlantOneClickKind.care =>
        '将清除 ${plan.actionCount} 处杂草 / 害虫\n'
            '奖励照常发放：除草 +${kGardenWeedReward.toInt()} ☀ / 除虫 +${kGardenPestReward.toInt()} ☀',
    };
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(switch (kind) {
          PlantOneClickKind.water => '要一键浇水吗？',
          PlantOneClickKind.fertilize => '要一键施肥吗？',
          PlantOneClickKind.care => '要一键护理吗？',
        }),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return; // 取消 → 分毫不扣
    // 一键浇水 / 施肥各播**一次**对应养护音效（玄参 2026-10-06「对应着播放一次音效」；
    // 不逐株连播——N 盆 N 声会糊成一片）。一键护理的除草/除虫音效逐株照旧。
    switch (kind) {
      case PlantOneClickKind.water:
        AudioService.instance.playSfx(AudioCue.careWater);
      case PlantOneClickKind.fertilize:
        AudioService.instance.playSfx(AudioCue.careFertilize);
      case PlantOneClickKind.care:
        break;
    }
    // 执行前先抓「plantId → potIndex」映射（_run 末尾会刷新 _plants）。
    final Map<String, int> potOf = <String, int>{
      for (final Plant p in _plants) p.id: p.potIndex,
    };
    await _run(() async {
      switch (kind) {
        case PlantOneClickKind.water:
          for (final String id in plan.plantIds) {
            await svc.water(id, now);
          }
        case PlantOneClickKind.fertilize:
          for (final String id in plan.plantIds) {
            await svc.fertilize(id, now);
          }
        case PlantOneClickKind.care:
          for (final ({String plantId, bool weed}) t in plan.careTargets) {
            t.weed
                ? await svc.clearWeed(t.plantId, now)
                : await svc.clearPest(t.plantId, now);
          }
      }
    });
    if (!mounted) return;
    // 成功收尾：每盆轻量反馈 + 顶部汇总飘字。
    final Map<int, CareEffectType> pulse = <int, CareEffectType>{};
    switch (kind) {
      case PlantOneClickKind.water:
      case PlantOneClickKind.fertilize:
        final CareEffectType t = kind == PlantOneClickKind.water
            ? CareEffectType.water
            : CareEffectType.fertilize;
        for (final String id in plan.plantIds) {
          final int? pot = potOf[id];
          if (pot != null) pulse[pot] = t;
        }
      case PlantOneClickKind.care:
        for (final ({String plantId, bool weed}) t in plan.careTargets) {
          final int? pot = potOf[t.plantId];
          if (pot != null) {
            pulse[pot] = t.weed ? CareEffectType.weed : CareEffectType.pest;
          }
        }
    }
    final int careEarned = plan.careTargets.fold<int>(
      0,
      (int sum, ({String plantId, bool weed}) t) =>
          sum + (t.weed ? kGardenWeedReward : kGardenPestReward).toInt(),
    );
    setState(() {
      _batchPulse
        ..clear()
        ..addAll(pulse);
      _batchHint = switch (kind) {
        PlantOneClickKind.water => (
            label: '一键浇水成功 ×${plan.plantIds.length}',
            sunlight: -plan.totalCost,
          ),
        PlantOneClickKind.fertilize => (
            label: '一键施肥成功 ×${plan.plantIds.length}',
            sunlight: -plan.totalCost,
          ),
        PlantOneClickKind.care => (
            label: '一键护理成功 ×${plan.actionCount}',
            sunlight: careEarned,
          ),
      };
    });
    _batchPulseTimer?.cancel();
    // 清场定时器 = 本类脉冲显示时长 + 150ms 余量（浇水/施肥与音效等长，
    // 玄参 2026-10-06；一键护理维持旧 1s 轻脉冲 + 100ms）。
    final int pulseClearMs = switch (kind) {
      PlantOneClickKind.water => kCareWaterDurationMs + 150,
      PlantOneClickKind.fertilize => kCareFertilizeDurationMs + 150,
      PlantOneClickKind.care => 1100,
    };
    _batchPulseTimer = Timer(Duration(milliseconds: pulseClearMs), () {
      if (!mounted) return;
      setState(() => _batchPulse.clear());
    });
  }

  /// 打开「选择要种的植物」弹窗（玄参 2026-09-28 计价模型 + C29 可重复种植；
  /// 2026-10-05 玄参口径修订：**屏幕中间弹出**（不再是底部抽屉）+ 卡片美化）。
  ///
  /// 列表顺序 = 物种表顺序（向日葵第一、月光兰第二…）。每张卡（[_PlantTile]）展示：
  ///  · 物种**成株/开花美术图**（[SpeciesPreviewArt]，缺失回退内置花卉图标）；
  ///  · 名称 + 稀有度徽章（普通绿 / 精英紫，卡片描边同色区分）；
  ///  · 支付方式按钮：**阳光/碎片用素材图标 + 数字**（不再写「N 阳光」文字）。
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
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF4E4), // 暖奶油底（与养护卡同层语言）
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFFE3B0), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Center(
                  child: Text('选择要种的植物',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                // 余额行：阳光 / 碎片均用素材图标（玄参「阳光和植物碎片使用素材替换」）。
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _AssetGlyph(
                      asset: _rewardAssets
                              .contains('assets/rewards/sunlight.png')
                          ? 'assets/rewards/sunlight.png'
                          : null,
                      fallbackIcon: Icons.wb_sunny,
                      fallbackColor: const Color(0xFFE8A33D),
                    ),
                    Text(' ${_balance.toInt()}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 16),
                    _AssetGlyph(
                      asset: _rewardAssets
                              .contains('assets/rewards/fragment.png')
                          ? 'assets/rewards/fragment.png'
                          : null,
                      fallbackIcon: Icons.extension,
                      fallbackColor: const Color(0xFF7E57C2),
                    ),
                    Text(' $_fragmentBalance',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  // SingleChildScrollView + Column（非 ListView）：全部卡片**常驻
                  // 构建树**（懒加载列表的屏外项不构建，会漏 find 断言/丢种子徽章）。
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // 卡片间留 10px 空隙（玄参 2026-10-05「卡片与卡片之间要留点
                        // 空隙，现在看起来太拥挤了」）。
                        for (int i = 0; i < rows.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(height: 10),
                          _PlantTile(
                            species: rows[i].sp,
                            buttons: rows[i].buttons,
                            rewardAssets: _rewardAssets,
                            // 种子徽章（玄参 2026-09-29）：持有该物种免费种植券（掉落过种子且已收集）→ 卡片打「🌰 种子」标。
                            hasSeed: _unlockedSpecies.contains(rows[i].sp.id),
                            onPay: (PlantCostKind kind) async {
                              Navigator.of(ctx).pop();
                              await _confirmAndPlant(
                                  rows[i].sp, kind, potIndex);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 计算某物种在「选择要种的植物」弹窗里的可用支付方式按钮（可用性 + 文案 + 禁用原因）。
  ///
  /// 计价口径与领域层 [PlantGrowthService.plantPaymentOptions] **一致**（单点真源）；
  /// 依赖账本与余额 → 异步，UI 不得自行重算价格。
  /// C29：植物**可重复种植**，不再按「已有存活植株」禁用（同物种可多株并存）；
  /// 禁用只看余额（阳光不足 / 碎片不足并写明当前片数）。
  ///  · free → 「免费」/「用种子种（免费）」；sunlight → 「N 阳光」（阳光不足禁用）；
  ///    fragments → 「N 植物碎片」（碎片不足禁用）。
  Future<List<_PlantPaymentButton>> _plantPaymentButtons(
    PlantSpecies sp,
    PlantGrowthService svc,
  ) async {
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
          enabled = true;
        case PlantCostKind.sunlight:
          label = '${opt.amount} 阳光';
          if (_balance < opt.amount) {
            enabled = false;
            reason = '阳光不足';
          } else {
            enabled = true;
          }
        case PlantCostKind.fragments:
          label = '${opt.amount} 植物碎片';
          if (_fragmentBalance < opt.amount) {
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

  /// 种植**二次确认**（玄参 2026-10-05 反馈「点阳光 / 植物碎片 / 种子都需二次确认，
  /// 防止误操作」）：选种弹窗点任一支付按钮 → 关闭选种弹窗 → 再弹一张确认卡
  /// （明示本次消耗与当前余额）→ 点「确定种植」才真正 `plant(...)`；
  /// 点「取消」/ 关闭 → 分毫不扣、种子券不消耗（领域层未触达）。
  ///
  /// 金额与 [PlantGrowthService.plantPaymentOptions] 同源重查（口径单点，不读
  /// 选种弹窗的快照）；余额在弹窗间隙变化的兜底由 `plant()` 内部再校验——
  /// 抛错走 [_run] 的分因 SnackBar，绝不静默扣费。
  Future<void> _confirmAndPlant(
    PlantSpecies sp,
    PlantCostKind kind,
    int potIndex,
  ) async {
    if (_busy) return;
    final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
    PlantPaymentOption? opt;
    for (final PlantPaymentOption o in await svc.plantPaymentOptions(sp)) {
      if (o.kind == kind) {
        opt = o;
        break;
      }
    }
    if (opt == null || !mounted) return;
    final String costLine = switch (kind) {
      PlantCostKind.free =>
        sp.id == kStarterSpeciesId ? '本次种植：免费' : '将使用 1 张${sp.name}种子（免费）',
      PlantCostKind.sunlight =>
        '本次种植将扣除：${opt.amount} ☀\n当前阳光：${_balance.toInt()} ☀',
      PlantCostKind.fragments =>
        '本次将使用：${opt.amount} 片植物碎片\n当前碎片：$_fragmentBalance 片',
    };
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('要种下${sp.name}吗？'),
        content: Text(costLine),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定种植'),
          ),
        ],
      ),
    );
    if (ok != true) return; // 取消 / 关闭 → 不扣任何资源
    await _run(() => svc.plant(sp.id, potIndex, DateTime.now(), payWith: kind));
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

  /// 当前持有的**普通档**种子（免费种植券）个数（花园左上角种子计数，玄参 2026-10-05
  /// 「在植物碎片的右边，并列显示普通种子和精英种子的个数」）。
  int get _commonSeedCount {
    int n = 0;
    for (final PlantSpecies s in _species) {
      if (!s.isPremium && _unlockedSpecies.contains(s.id)) n++;
    }
    return n;
  }

  /// 当前持有的**精英档**种子个数（口径同 [_commonSeedCount]）。
  int get _premiumSeedCount {
    int n = 0;
    for (final PlantSpecies s in _species) {
      if (s.isPremium && _unlockedSpecies.contains(s.id)) n++;
    }
    return n;
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
          weedFading: _fadingClear != null &&
              _fadingClear!.plantId == occupant.id &&
              _fadingClear!.weed,
          pestFading: _fadingClear != null &&
              _fadingClear!.plantId == occupant.id &&
              !_fadingClear!.weed,
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
              // 头顶奖励图标（玄参 2026-10-05 口径修订）：**叠在植物中间**（原「格顶
              // 一排」上移感太强）、整排**上下轻漂浮**（bob，±3px，有界 pump 纪律见
              // 组件注释）；`Positioned.fill` 叠加**不占布局高度**，其余区域命中穿透
              // 到花盆（只有图标 42×42 是 opaque 热区）。
              Positioned.fill(
                child: Center(
                  child: BloomRewardIconsBar(
                    rewards: rewards,
                    availableAssets: _rewardAssets,
                    onCollect: (PendingBloomReward r, RewardIconSpec spec) =>
                        _onCollectIconTap(i, r, spec),
                    isPremiumOf: _isPremiumSpecies,
                    bob: true,
                  ),
                ),
              ),
            if (_clearHint?.potIndex == i)
              // 除草 / 除虫成功飘字（2026-10-03 玄参口径）：起始位置 = **格子垂直中心**
              // （≈花盆口上方一点 / 花的中部，玄参反馈「格顶太靠上」后下移），自下而
              // 上飘动 + 淡出（约 1.6s），走完经 onComplete 自行移除；文案数值取常量。
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: _RisingHint(
                    label: _clearHint!.label,
                    sunlight: _clearHint!.sunlight,
                    // 阳光图标与头顶奖励图标同源（玄参口径「就像之前那样显示」）；
                    // 资源缺失时 _RisingHint 内部回退内置 Icons.wb_sunny。
                    sunIconAsset:
                        _rewardAssets.contains('assets/rewards/sunlight.png')
                            ? 'assets/rewards/sunlight.png'
                            : null,
                    onComplete: () {
                      if (mounted) setState(() => _clearHint = null);
                    },
                  ),
                ),
              ),
            if (_batchPulse.containsKey(i))
              // 一键操作的每盆轻量反馈（C29）：小图标短暂浮现淡出（约 1.1s 整批清除），
              // 不播 4s 完整动效（逐盆播完整动画 5 盆要 20s+，玄参拍板「每盆只加轻量反馈」）。
              Positioned.fill(
                child: Center(
                  child: _PotPulse(type: _batchPulse[i]!),
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

    // 花园氛围音可见性（玄参 2026-09-28；F71 2026-10-05 修订）。
    // ⚠️ 原实现按 TickerMode 依赖重建判可见性，但 IndexedStack 更新隐藏子树的
    // 时机不保证本页立即重建 → 切 tab 后氛围音继续播完整曲（玄参实测）。
    // 现改 **watch 外壳 tab 索引 provider**（外壳 _onSelectTab 同步写入），
    // 确定性推导：本 provider 变化必然触发本页重建 → 必然启停。
    final bool gardenVisible = !widget.embedded ||
        ref.watch(childShellTabIndexProvider) == kChildTabIndexOfGarden;
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
            // 精品碎片入口（变更 B；2026-10-05 玄参口径修订：**移到花园背景图左上角**，
            // 原右下角与一键操作按钮挤在一起）。根 Stack 浮层——**不占布局高度**，避免
            // 改动花盆网格的可视高度（矮屏用例硬钉该高度）。内嵌 tab 时左上角无阳光胶囊
            // （在 shell AppBar）；独立路由 /garden 左上角有胶囊 → 下移到胶囊之下。
            if (!_loading && _error == null)
              Positioned(
                left: 12,
                top: widget.embedded ? 12 : 60,
                child: Row(
                  children: <Widget>[
                    _FragmentEntry(
                      balance: _fragmentBalance,
                      onTap: _openFragmentSheet,
                    ),
                    const SizedBox(width: 8),
                    // 种子计数（2026-10-05 玄参「碎片右边并列显示普通/精英种子个数」）：
                    // 分档种子素材图 + ×N；素材缺失回退 🌰。2026-10-06：点击也打开
                    // 「碎片与种子」说明卡（玄参「点击种子就不会弹出来，都需要弹出」）。
                    _SeedCountChip(
                      count: _commonSeedCount,
                      asset: 'assets/rewards/seed_common.png',
                      onTap: _openFragmentSheet,
                    ),
                    const SizedBox(width: 6),
                    _SeedCountChip(
                      count: _premiumSeedCount,
                      asset: 'assets/rewards/seed_premium.png',
                      onTap: _openFragmentSheet,
                    ),
                  ],
                ),
              ),
            // 一键操作悬浮按钮（C29；2026-10-05 玄参口径修订：移到右下角贴底——
            // 原上方碎片入口已移走）+ 点开/再点收拢的展开卡（宽度与胶囊一致）。
            // 存活株 ≥ kOneClickMinPlants 才出现（「花园植物大于 3 盆」，死亡残株不算）。
            if (!_loading && _error == null && _showOneClickFab)
              Positioned(
                right: 12,
                bottom: 12,
                child: _OneClickFab(onSelected: _onOneClick),
              ),
            // 一键操作汇总飘字（C29）：页面顶部居中，「一键XX成功 ×N」+ 阳光增减
            // （扣费显示 -N / 护理奖励显示 +N），由 _RisingHint 走完自清。
            if (_batchHint != null)
              Positioned(
                top: 96,
                left: 0,
                right: 0,
                child: Center(
                  child: _RisingHint(
                    label: _batchHint!.label,
                    sunlight: _batchHint!.sunlight,
                    sunIconAsset:
                        _rewardAssets.contains('assets/rewards/sunlight.png')
                            ? 'assets/rewards/sunlight.png'
                            : null,
                    onComplete: () {
                      if (mounted) setState(() => _batchHint = null);
                    },
                  ),
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
                    // 先取业务收尾回调（除草 / 除虫：渐变消失 → 刷新 → 飘字），
                    // 再移除叠加层 —— 置 null 后 spec 就取不到了。
                    final VoidCallback? finished = _activeEffect?.onFinished;
                    if (mounted) setState(() => _activeEffect = null);
                    finished?.call();
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

/// 除草 / 除虫成功飘字（2026-10-03 玄参口径）：半透明白胶囊，**自下而上飘动 +
/// 淡出**（总时长 [kClearHintRiseMs]）。前 10% 淡入、中段平稳上飘、后 30% 淡出，
/// 走完经 [onComplete] 通知花园页移除。有限时长动画（可被 pumpAndSettle 结束）。
///
/// 内容 = `[label] [阳光图标] [+N]`（玄参：「阳光+1」的阳光要用**图标**不是文字，
/// 与头顶奖励图标同源 `assets/rewards/sunlight.png`，缺失回退内置 `Icons.wb_sunny`）。
/// 胶囊外套 [FittedBox]：窄格里内容超宽时**等比缩小**而不是省略号截断
/// （玄参反馈「除草成功，阳光+1 显示不全」的修复，与头顶图标条同口径）。
class _RisingHint extends StatefulWidget {
  /// 「除草成功」/「除虫成功」。
  final String label;

  /// 奖励阳光数（渲染成「+N」跟在阳光图标后）。
  final int sunlight;

  /// 阳光图标 asset（null 或加载失败 → 回退内置 `Icons.wb_sunny`）。
  final String? sunIconAsset;

  /// 动画走完回调（花园页在此清掉 [_clearHint] 移除本组件）。
  final VoidCallback? onComplete;

  const _RisingHint({
    required this.label,
    required this.sunlight,
    this.sunIconAsset,
    this.onComplete,
  });

  @override
  State<_RisingHint> createState() => _RisingHintState();
}

class _RisingHintState extends State<_RisingHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kClearHintRiseMs),
  );

  /// 上飘位移：0 → -[kClearHintRiseDistance]（easeOut，起快后缓）。
  late final Animation<double> _rise = Tween<double>(
    begin: 0,
    end: -kClearHintRiseDistance,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener(_onStatus);
    _ctrl.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onComplete?.call();
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? _) {
        final double t = _ctrl.value;
        // 透明度包络：前 10% 淡入 → 中段 1.0 → 后 30% 淡出（端点齐平不跳变）。
        final double alpha = t < 0.10
            ? t / 0.10
            : t > 0.70
                ? (1 - (t - 0.70) / 0.30).clamp(0.0, 1.0)
                : 1.0;
        return Transform.translate(
          offset: Offset(0, _rise.value),
          child: Opacity(
            opacity: alpha,
            // FittedBox：内容超宽时等比缩小（不截断）——窄格不再「显示不全」。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xEFFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.label,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF8D6E00),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _sunIcon(),
                    const SizedBox(width: 2),
                    Text(
                      // C29：一键操作汇总飘字带负数（扣费）→ 显示「-N」而非「+-N」。
                      widget.sunlight >= 0
                          ? '+${widget.sunlight}'
                          : '${widget.sunlight}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE8A33D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 阳光图标：美术图（16×16，显式宽高）优先，缺失/失败回退内置 `Icons.wb_sunny`。
  Widget _sunIcon() {
    final String? path = widget.sunIconAsset;
    if (path != null) {
      return Image.asset(
        path,
        width: 16,
        height: 16,
        fit: BoxFit.contain,
        errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
            const Icon(Icons.wb_sunny, size: 16, color: Color(0xFFE8A33D)),
      );
    }
    return const Icon(Icons.wb_sunny, size: 16, color: Color(0xFFE8A33D));
  }
}

/// 一键操作的每盆**轻量反馈**（C29）：小图标短暂浮现 → 停留 → 淡出（总时长约
/// 1s，`TweenAnimationBuilder` 自驱、无外部控制器）。类型与养护动效共用
/// [CareEffectType]（water / fertilize / weed / pest），颜色按类型区分。
class _PotPulse extends StatelessWidget {
  const _PotPulse({required this.type});

  final CareEffectType type;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (type) {
      CareEffectType.water => (Icons.water_drop, const Color(0xFF4FA3D9)),
      CareEffectType.fertilize => (Icons.eco, const Color(0xFF5FA854)),
      CareEffectType.weed => (Icons.grass, const Color(0xFF8BC34A)),
      CareEffectType.pest => (Icons.pest_control, const Color(0xFFE8A33D)),
    };
    // 显示时长与同播音效**等长**（玄参 2026-10-06「浇水的音效明显比统一显示的
    // 图标时间要长，图标显示时间需要增长」）：浇水 = care_water.mp3 2.90s、
    // 施肥 = care_fertilize.mp3 3.06s（常量单点 prd_params，与效果帧共用）；
    // 除草/除虫（一键护理逐株另有完整效果帧）维持 1s 轻脉冲。
    final int pulseMs = switch (type) {
      CareEffectType.water => kCareWaterDurationMs,
      CareEffectType.fertilize => kCareFertilizeDurationMs,
      CareEffectType.weed || CareEffectType.pest => 1000,
    };
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: pulseMs),
      builder: (BuildContext context, double t, Widget? child) {
        // 前 25% 淡入放大 → 中段停留 → 后 35% 淡出缩小。
        final double alpha = t < 0.25
            ? t / 0.25
            : t > 0.65
                ? (1 - (t - 0.65) / 0.35).clamp(0.0, 1.0)
                : 1.0;
        final double scale = 0.7 + 0.3 * (t < 0.25 ? t / 0.25 : 1.0);
        return Opacity(
          opacity: alpha,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: color),
      ),
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

/// 素材图标 + 兜底内置 Icon（玄参 2026-10-05「阳光和植物碎片使用素材替换，不要写文字」）。
class _AssetGlyph extends StatelessWidget {
  const _AssetGlyph({
    required this.asset,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.size = 20,
  });

  /// 素材路径（null = 缺失，走内置 Icon 兜底）。
  final String? asset;

  final IconData fallbackIcon;
  final Color fallbackColor;

  /// 视觉边长。
  final double size;

  @override
  Widget build(BuildContext context) {
    if (asset == null) {
      return Icon(fallbackIcon, size: size, color: fallbackColor);
    }
    return Image.asset(
      asset!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
          Icon(fallbackIcon, size: size, color: fallbackColor),
    );
  }
}

/// 选种卡固定高度（玄参 2026-10-05「植物卡片的高度最好是统一一个固定的高度」）。
const double kPlantCardHeight = 116;

/// 单个物种的选种卡片（2026-10-05 三修，玄参口径）：
///  · **固定高度**（[kPlantCardHeight]），所有卡片等高不跳动；
///  · 左侧**放大版成株/开花美术图**（[SpeciesPreviewArt]，80）；
///  · 价格按钮**一行排布**（阳光 + 碎片并列，FittedBox 兜底缩放，不再折两行）；
///  · **点击卡片空白处翻面**：背面显示该物种的简短介绍 + 小故事（[speciesLoreOf]）。
class _PlantTile extends StatefulWidget {
  const _PlantTile({
    required this.species,
    required this.buttons,
    required this.onPay,
    required this.rewardAssets,
    this.hasSeed = false,
  });

  final PlantSpecies species;
  final List<_PlantPaymentButton> buttons;
  final void Function(PlantCostKind kind) onPay;

  /// 可用美术资源集合（阳光/碎片/种子按钮图标用；空集 → 内置 Icon 兜底）。
  final Set<String> rewardAssets;

  /// 是否持有该物种的免费种植券（掉落过种子且已收集）→ 显示种子徽章。
  final bool hasSeed;

  @override
  State<_PlantTile> createState() => _PlantTileState();
}

class _PlantTileState extends State<_PlantTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// 当前是否翻到背面。
  bool _showBack = false;

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  /// 点击卡片空白处 → 翻到背面 / 翻回正面（支付按钮各自吃掉点击，不触发翻面）。
  void _toggleFlip() {
    setState(() {
      _showBack = !_showBack;
      if (_showBack) {
        _flipCtrl.forward();
      } else {
        _flipCtrl.reverse();
      }
    });
  }

  /// 档位强调色（普通绿 / 精英紫，卡片描边同色区分）。
  Color get _accent => widget.species.isPremium
      ? const Color(0xFF7E57C2)
      : const Color(0xFF5FA854);

  BoxDecoration _faceDecoration({required Color fill}) => BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.45), width: 1.5),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flipCtrl,
      builder: (BuildContext context, Widget? _) {
        final double angle = math.pi * _flipCtrl.value;
        final bool backSide = angle > math.pi / 2;
        Widget face = backSide ? _backFace() : _frontFace();
        if (backSide) {
          // 背面镜像：把 π 角转回去，文字才可读。
          face = Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: face,
          );
        }
        return GestureDetector(
          onTap: _toggleFlip,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: face,
          ),
        );
      },
    );
  }

  /// 正面：放大植物图 + 名称/稀有度/种子徽章 + **一行**价格按钮。
  Widget _frontFace() {
    final PlantSpecies species = widget.species;
    final bool premium = species.isPremium;
    final String seedAsset = premium
        ? 'assets/rewards/seed_premium.png'
        : 'assets/rewards/seed_common.png';
    final String? sunlightAsset =
        widget.rewardAssets.contains('assets/rewards/sunlight.png')
            ? 'assets/rewards/sunlight.png'
            : null;
    final String? fragmentAsset =
        widget.rewardAssets.contains('assets/rewards/fragment.png')
            ? 'assets/rewards/fragment.png'
            : null;
    // 禁用原因（如「植物碎片不足（当前 4 片）」）合并为一行小字，不撑高卡片。
    final String? disableReason = widget.buttons
        .where((_PlantPaymentButton b) => !b.enabled && b.disabledReason != null)
        .map((_PlantPaymentButton b) => b.disabledReason!)
        .join(' · ');
    return Container(
      height: kPlantCardHeight,
      padding: const EdgeInsets.all(10),
      decoration: _faceDecoration(fill: Colors.white),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 物种成株/开花美术图（玄参「左边植物放大一些」→ 60 → 80）。
          SpeciesPreviewArt(species: species, size: 80),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(species.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    // 稀有度徽章：普通绿 / 精英紫（一眼区分档位）。
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: premium
                            ? const Color(0xFFF3E5F5)
                            : const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_rarityLabel(species.rarity),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _accent)),
                    ),
                    if (widget.hasSeed) ...<Widget>[
                      const SizedBox(width: 6),
                      // 种子徽章（玄参「掉落了种子也要显示种子图标」）：分档种子图，
                      // 缺失回退 🌰 emoji。
                      Image.asset(
                        seedAsset,
                        width: 16,
                        height: 16,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (BuildContext _, Object __, StackTrace? ___) =>
                                const Text('🌰',
                                    style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // 价格一行（玄参「阳光和植物碎片，在1行就行」）：Row + FittedBox
                // 兜底缩放，绝不折两行。
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int i = 0; i < widget.buttons.length; i++) ...<Widget>[
                        _PayButtonWidget(
                          button: widget.buttons[i],
                          sunlightAsset: sunlightAsset,
                          fragmentAsset: fragmentAsset,
                          seedAsset: seedAsset,
                          onTap: widget.buttons[i].enabled
                              ? () => widget.onPay(widget.buttons[i].kind)
                              : null,
                        ),
                        if (i < widget.buttons.length - 1)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                if (disableReason != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    disableReason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 背面：物种简短介绍 + 小故事（玄参 2026-10-05「背面写着这个植物的简短介绍
  /// 和一个小故事」）。文案单点 [speciesLoreOf]，UI 不写死。
  Widget _backFace() {
    final PlantSpecies species = widget.species;
    final SpeciesLore lore = speciesLoreOf(species.id);
    return Container(
      height: kPlantCardHeight,
      padding: const EdgeInsets.all(12),
      decoration: _faceDecoration(fill: const Color(0xFFFFF9EC)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_stories, size: 14, color: _accent),
              const SizedBox(width: 4),
              Text(species.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              const Text('点此翻回正面',
                  style: TextStyle(fontSize: 10, color: Color(0xFFB9AE97))),
            ],
          ),
          const SizedBox(height: 4),
          Text(lore.intro,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _accent)),
          const SizedBox(height: 3),
          Expanded(
            child: Text(
              lore.story,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, height: 1.3, color: Color(0xFF6B6252)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 大圆角马卡龙风格支付按钮（儿童友好；素材图标 + 数字，不再写「N 阳光」文字；
/// 种子券按钮前置分档种子图；2026-10-05 起价格在卡片内**一行**排布，按钮更紧凑）。
class _PayButtonWidget extends StatelessWidget {
  const _PayButtonWidget({
    required this.button,
    required this.sunlightAsset,
    required this.fragmentAsset,
    required this.seedAsset,
    this.onTap,
  });

  final _PlantPaymentButton button;

  /// 阳光 / 碎片 / 种子素材路径（null = 缺失，内置 Icon 兜底）。
  final String? sunlightAsset;
  final String? fragmentAsset;
  final String? seedAsset;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final _PlantPaymentButton b = button;
    final Color bg = b.enabled ? const Color(0xFF8FCF74) : Colors.grey.shade300;
    final Widget child = switch (b.kind) {
      // 免费类保留文字（测试口径）：向日葵首株「免费」；种子券按钮前置分档种子图。
      PlantCostKind.free => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (b.label.contains('种子')) ...<Widget>[
              Image.asset(
                seedAsset ?? 'assets/rewards/seed_common.png',
                width: 16,
                height: 16,
                fit: BoxFit.contain,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    const Text('🌰', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
            ],
            Text(b.label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: b.enabled ? Colors.white : Colors.grey.shade600)),
          ],
        ),
      PlantCostKind.sunlight => _iconAmount(sunlightAsset, Icons.wb_sunny,
          const Color(0xFFE8A33D), b.amount, b.enabled),
      PlantCostKind.fragments => _iconAmount(fragmentAsset, Icons.extension,
          const Color(0xFF7E57C2), b.amount, b.enabled),
    };
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: b.enabled ? Colors.white : Colors.grey.shade600,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: child,
    );
  }

  /// 「素材图标 + 数字」内芯（显式尺寸，防 loose 约束原图尺寸布局）。
  Widget _iconAmount(String? asset, IconData fallback, Color fallbackColor,
      int amount, bool enabled) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _AssetGlyph(
          asset: asset,
          fallbackIcon: fallback,
          fallbackColor: enabled ? Colors.white : fallbackColor,
          size: 18,
        ),
        const SizedBox(width: 4),
        Text(
          '$amount',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: enabled ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
/// 一键操作悬浮按钮（C29；玄参 2026-10-05 交互修订）：
///
/// · **收拢态**：胶囊「✋ 一键操作」；**展开态**：其上方一张三行操作卡（浇水/施肥/护理）。
/// · **宽度恒定**：胶囊与展开卡共用固定宽度（[_width]），展开/收拢**不左右变形**
///   （玄参「宽度要一致，不要来回变化」）。
/// · **点击切换**：点胶囊展开 → 再点胶囊收拢（toggle，不再是系统下拉菜单）；
///   点某操作行 → 收拢并回调 [onSelected]。
class _OneClickFab extends StatefulWidget {
  const _OneClickFab({required this.onSelected});

  /// 选中某项一键操作（选中即收拢）。
  final ValueChanged<PlantOneClickKind> onSelected;

  @override
  State<_OneClickFab> createState() => _OneClickFabState();
}

class _OneClickFabState extends State<_OneClickFab> {
  /// 胶囊与展开卡共用的固定宽度（两者严格等宽，玄参口径）。
  static const double _width = 108;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (_expanded) ...<Widget>[
          _buildActionCard(),
          const SizedBox(height: 6),
        ],
        _buildCapsule(),
      ],
    );
  }

  /// 展开卡：三行操作项，与胶囊同宽（[_width]）。
  Widget _buildActionCard() {
    return SizedBox(
      width: _width,
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const <_OneClickItem>[
            _OneClickItem(
              kind: PlantOneClickKind.water,
              icon: Icons.water_drop,
              color: Color(0xFF4FA3D9),
              label: '一键浇水',
            ),
            _OneClickItem(
              kind: PlantOneClickKind.fertilize,
              icon: Icons.eco,
              color: Color(0xFF5FA854),
              label: '一键施肥',
            ),
            _OneClickItem(
              kind: PlantOneClickKind.care,
              icon: Icons.pest_control,
              color: Color(0xFFE8A33D),
              label: '一键护理',
            ),
          ].map(_buildActionRow).toList(),
        ),
      ),
    );
  }

  /// 单行操作项。
  Widget _buildActionRow(_OneClickItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() => _expanded = false);
        widget.onSelected(item.kind);
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: <Widget>[
            Icon(item.icon, size: 16, color: item.color),
            const SizedBox(width: 6),
            Text(
              item.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B6252),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 收拢态胶囊（固定宽 [_width]）。
  Widget _buildCapsule() {
    return SizedBox(
      width: _width,
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                Icon(Icons.touch_app, size: 16, color: Color(0xFF7CB342)),
                SizedBox(width: 4),
                Text(
                  '一键操作',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B6252),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一键操作项的静态展示模型（图标 + 文案 + 主色 + 对应枚举）。
class _OneClickItem {
  const _OneClickItem({
    required this.kind,
    required this.icon,
    required this.color,
    required this.label,
  });

  final PlantOneClickKind kind;
  final IconData icon;
  final Color color;
  final String label;
}

/// 收集奖励的「向上飘动 + 淡出」幽灵（玄参 2026-10-05「用户点击之后，向上飘动，
/// 慢慢消失」）：复用 [BloomRewardIcon] 纯展示渲染（`onTap: null`），有限时长
/// （约 0.9s）自下而上飘 ~56px 并淡出，走完经 [onComplete] 自清。
///
/// ⚠️ 资源缺失（测试环境 AssetManifest 读不到）→ 图标无图可画 → 整体不渲染，
/// 不产生任何 findable 节点（不干扰既有收集断言）。
class CollectGhost extends StatelessWidget {
  const CollectGhost({
    super.key,
    required this.specs,
    required this.availableAssets,
    required this.onComplete,
  });

  /// 点击时捕获的图标规格（该条 pending 的全部图标一起飘走）。
  final List<RewardIconSpec> specs;

  /// 可用美术资源集合（空集 → 无图可画 → 不渲染）。
  final Set<String> availableAssets;

  /// 动画走完回调（调用方清状态）。
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    // 幽灵渲染规则：
    //  · 素材清单**完全不可用**（测试环境，availableAssets 空）→ 无图可画 →
    //    整体不渲染，不产生任何 findable 节点（不干扰既有收集断言）；
    //  · 清单可用但**个别素材缺失**（如 `sunlight.png` 未交付，F73）→ 该项用
    //    内置 Icons 兜底照样飘（否则纯阳光奖励的幽灵整个为空 =「点击直接消失」，
    //    玄参 2026-10-05 复测复现；真素材到位后自动替换，无需改码）。
    final bool manifestUsable = availableAssets.isNotEmpty;
    final List<BloomRewardIcon> icons = <BloomRewardIcon>[];
    for (final RewardIconSpec spec in specs) {
      final String? asset = resolveRewardAsset(spec, availableAssets);
      if (asset == null && !manifestUsable) continue; // 测试环境：全部跳过
      icons.add(BloomRewardIcon(
        spec: spec,
        assetPath: asset, // null → BloomRewardIcon 内置 Icon 兜底
        onTap: null, // 纯展示：幽灵不响应点击
      ));
    }
    if (icons.isEmpty) {
      return const SizedBox.shrink();
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      onEnd: onComplete,
      builder: (BuildContext context, double t, Widget? child) {
        return Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -56 * t),
            child: child,
          ),
        );
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: icons),
    );
  }
}


/// 花园左上角「种子计数」小 chip（2026-10-05 玄参需求：碎片入口右边并列显示
/// 普通 / 精英种子个数）。分档种子素材图 + 「×N」；素材缺失回退 🌰 emoji。
/// 2026-10-06：加 [onTap]（与碎片 chip 一样点开「碎片与种子」说明卡）。
class _SeedCountChip extends StatelessWidget {
  const _SeedCountChip({required this.count, required this.asset, this.onTap});

  /// 持有的该档种子数。
  final int count;

  /// 分档种子素材路径（seed_common / seed_premium）。
  final String asset;

  /// 点击回调（null = 纯展示不响应）。
  final VoidCallback? onTap;

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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Image.asset(
                asset,
                width: 16,
                height: 16,
                fit: BoxFit.contain,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    const Text('🌰', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 3),
              Text(
                '×$count',
                style: const TextStyle(
                  fontSize: 12,
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

/// 花园页「精品碎片」入口（玄参 2026-09-27 物种表改版）。
///
/// 旧「N/阈值 + 满阈值高亮」已废弃（阈值体系删除）；点击打开只读信息页 [_FragmentSheet]。
/// 2026-10-05 玄参「3 个 chip 要保持一样」：去掉「植物碎片」文字，改与 [_SeedCountChip]
/// 同款「图标 ×N」白胶囊（仅多一层点击进说明页）。
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 碎片美术图（2026-10-03 玄参提供）；缺失回退拼图 Icon。
              Image.asset(
                'assets/rewards/fragment.png',
                width: 16,
                height: 16,
                fit: BoxFit.contain,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    const Icon(
                  Icons.extension,
                  size: 16,
                  color: Color(0xFF9C917C),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '×$balance',
                style: const TextStyle(
                  fontSize: 12,
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

/// 「碎片与种子」说明卡（玄参 2026-10-06 口径修订：**屏幕中间 Dialog** + 内容**只讲
/// 植物碎片 / 普通种子 / 精英种子**三类资源的用途与获得方法，**不再逐物种列碎片
/// 价目**——价目在选种弹窗里本来就有，说明卡不重复）。入口 = 碎片 chip 与两个
/// 种子 chip。图标缺失回退内置 Icon。
class _RewardCurrencyDialog extends StatelessWidget {
  const _RewardCurrencyDialog();

  /// 单条说明（图标路径 + 兜底 Icon + 标题 + 用途 + 获得方法）。
  static const List<({String? asset, IconData fallbackIcon, Color color, String title, String use, String how})> _items =
      <({String? asset, IconData fallbackIcon, Color color, String title, String use, String how})>[
    (
      asset: 'assets/rewards/fragment.png',
      fallbackIcon: Icons.extension,
      color: Color(0xFF7E57C2),
      title: '植物碎片',
      use: '种植植物时可以代替阳光支付（精英植物要用碎片兑换）。',
      how: '植物开花时的奖励里随机掉落。',
    ),
    (
      asset: 'assets/rewards/seed_common.png',
      fallbackIcon: Icons.eco,
      color: Color(0xFF43A047),
      title: '普通植物种子',
      use: '免费种下一株普通植物，种下时优先使用（不用扣阳光）。',
      how: '普通植物开花后小概率掉落；重复的种子会自动变成碎片。',
    ),
    (
      asset: 'assets/rewards/seed_premium.png',
      fallbackIcon: Icons.eco,
      color: Color(0xFF7E57C2),
      title: '精英植物种子',
      use: '免费种下一株精英植物，种下时优先使用（不用扣碎片）。',
      how: '精英植物开花后小概率掉落；重复的种子会自动变成碎片。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF4E4), // 暖奶油底（与选种/养护卡同层语言）
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFFE3B0), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Center(
              child: Text('碎片与种子',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < _items.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: _items[i].asset != null
                          ? Image.asset(
                              _items[i].asset!,
                              width: 24,
                              height: 24,
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (BuildContext _, Object __, StackTrace? ___) =>
                                      Icon(_items[i].fallbackIcon,
                                          size: 22, color: _items[i].color),
                            )
                          : Icon(_items[i].fallbackIcon,
                              size: 22, color: _items[i].color),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(_items[i].title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _items[i].color)),
                        const SizedBox(height: 2),
                        Text('用途：${_items[i].use}',
                            style: const TextStyle(
                                fontSize: 12, height: 1.35,
                                color: Color(0xFF4A4436))),
                        const SizedBox(height: 2),
                        Text('获得：${_items[i].how}',
                            style: const TextStyle(
                                fontSize: 12, height: 1.35,
                                color: Color(0xFF6B6252))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道啦'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
