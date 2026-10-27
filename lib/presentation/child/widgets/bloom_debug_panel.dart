/// 花园页「花期调试」面板（**仅 `kDebugMode`** · 成株后循环玩法 Batch 1 验收辅助）。
///
/// ## 用途
/// 产品 / 开发在 iOS 模拟器上验收「花开花谢」时，不必等真实天数即可驱动完整链路：
/// 成株 → 开花瞬间奖励 → 盛开 3 / 4.5 天 → 花谢回落 → 复开花 → 花期每日晨露掉落气泡 →
/// 手动收集 / 花谢前未点自动到账。
///
/// ## 设计纪律（宪法总纪律 #2：单点收口 / 不复制业务判定）
/// 本面板**只负责「写字段 + 触发结算」**——开花、花谢、发奖的判定**仍由
/// [PlantGrowthService]（真实领域逻辑）完成**，面板不复制任何「何时开花 / 何时花谢 /
/// 掉什么奖」的业务分支。概率常量一律引用 [prd_params]（零裸字面量）。
///
/// ## release 安全
/// 入口与面板均由调用点 `if (kDebugMode)` 守卫（见 `garden_page.dart`），release 构建
/// **完全不出现**。测试用源码守卫钉住这条约束（同「DEBUG 加1000阳光」的既有做法）。
///
/// ## 测试陷阱（务必牢记）
/// 花园页木牌是**无限呼吸动画** → 打开本面板的测试**禁止 `pumpAndSettle`**（会永不返回），
/// 必须用有界的 `pump(Duration)` 逐帧推进。本面板自身**不含任何无限动画**。
///
/// ## 🔴 i18n B3 豁免登记（T05）：本面板**不迁 ARB**
/// 面板内按钮 / 标题的中文（「花期调试」「立即开花」等）是**仅 `kDebugMode` 可见的
/// 开发者工具文案**，release 构建整块不出现（上面「release 安全」已由源码守卫钉住）。
/// 把它迁进 ARB 的代价是：每个 key 都要占 2 次翻译 + 永久影响 `en_overflow_probe`
/// 之类的宽松断言，收益为零（最终用户永远看不到）。
///
/// 因此本文件**在 `test/i18n/no_han_in_domain_test.dart` 的扫描范围之外**——
/// 那个守卫只扫 `lib/domain/**`（零豁免），本文件不在其中；此处显式登记豁免理由，
/// 免得后来者看到中文就顺手搬走（搬走也不会变好，只会多 8 个没人看的 key）。
library bloom_debug_panel;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/services/empty_pot_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/shared/consent_page.dart';

/// 花园页右上角「花期调试」浮层入口（**紧凑圆形按钮**）。
///
/// ⚠️ 由调用方用 `Positioned` 摆在根 `Stack` 上——**不占布局高度**，避免改动花盆网格的
/// 可视高度（矮屏用例硬钉该高度）；也不会因超出测试视口把既有用例顶出屏幕。
class BloomDebugEntry extends StatelessWidget {
  const BloomDebugEntry({super.key, required this.onTap});

  /// 点击入口：打开调试面板。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '花期调试',
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.science, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// 打开「花期调试」面板（bottom sheet）。
///
/// [onChanged] 在每次动作后回调（花园页据此静默刷新气泡 / 进度 / 余额展示）。
Future<void> showBloomDebugPanel(
  BuildContext context, {
  VoidCallback? onChanged,
  void Function(GrowTransition transition, String speciesDir)? onPreviewGrowth,
}) {
  // 面板高度取自**调用方**（花园页）的 MediaQuery（可靠）；面板自身不再依赖
  // sheet 内 MediaQuery，避免底部弹窗上下文中尺寸读取异常导致内容被布局到屏幕外。
  final double maxHeight = MediaQuery.of(context).size.height * 0.85;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext _) => BloomDebugSheet(
      maxHeight: maxHeight,
      onChanged: onChanged,
      onPreviewGrowth: onPreviewGrowth,
    ),
  );
}

/// 「花期调试」面板本体（可滚动）。
///
/// 直接读 / 写 Provider 暴露的仓储与服务；所有动作后都调 [PlantGrowthService.tickAll]
/// 走真实结算，再回调 [onChanged] 让花园页刷新。
class BloomDebugSheet extends ConsumerStatefulWidget {
  const BloomDebugSheet({
    super.key,
    this.maxHeight = 560,
    this.onChanged,
    this.onPreviewGrowth,
  });

  /// 面板内容高度（由 [showBloomDebugPanel] 依调用方屏幕算出）。
  final double maxHeight;

  /// 动作完成后的回调（花园页据此刷新）。
  final VoidCallback? onChanged;

  /// 分段成长**演出预览**回调（玄参 2026-10-13）：由花园页真正播该段过渡的
  /// 成长演出 + 该物种音效（口径 C59）；本面板不复制播放/资产逻辑。
  final void Function(GrowTransition transition, String speciesDir)?
      onPreviewGrowth;

  @override
  ConsumerState<BloomDebugSheet> createState() => _BloomDebugSheetState();
}

class _BloomDebugSheetState extends ConsumerState<BloomDebugSheet> {
  List<Plant> _plants = <Plant>[];
  List<PlantSpecies> _species = <PlantSpecies>[];
  Set<String> _collectibleIds = <String>{};
  double _balance = 0;
  String? _selectedId;
  double _slider = 0;
  bool _busy = false;
  bool _loaded = false;

  // ── 空盆干扰物调试（F157-FEAT-3）─────────────────────────────────────────
  //
  // 背景（玄参 2026-10-27 原话）：「我没有调试按钮，建了空盆之后，我不能在空盆上
  // 让它直接长草或长虫，然后再去清除草和虫」。空盆 roll 每天只有 20% / 15%，
  // 且默认首日免疫 → 真机等不到，必须给一个**确定性**入口。

  /// 当前花盆容量（`settings.gardenPotCapacity`，与花园页 `_capacity` 同源）。
  int _capacity = 0;

  /// 当前**空盆**序号（升序；= 容量范围内没有任何植物行占用的盆，含死亡残株占用的
  /// 盆不算空 —— 与花园页 `_occupantOf(i) == null` 同一判据）。
  List<int> _emptyPots = <int>[];

  /// 调试动作的目标空盆（默认 = [_emptyPots] 第一个）。
  int? _emptyPotSel;

  /// 各空盆的当日干扰物状态（做「当前状态」回显，方便对照浮标）。
  Map<int, PotDisturbance> _potStates = <int, PotDisturbance>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  PlantRepository get _repo => ref.read(plantRepositoryProvider);
  BloomRewardRepository get _bloom => ref.read(bloomRewardRepositoryProvider);
  PlantGrowthService get _svc => ref.read(plantGrowthServiceProvider);

  /// 空盆干扰物仓储（**只读**状态回显用；写操作一律走 [EmptyPotService]）。
  PotDisturbanceRepository get _potRepo =>
      ref.read(potDisturbanceRepositoryProvider);

  /// 空盆干扰物服务（生产同一实例：账本入账 / 幂等口径单点）。
  EmptyPotService get _emptyPotSvc => ref.read(emptyPotServiceProvider);

  /// 当前选中的植物（无则为 null）。
  Plant? get _selected {
    for (final Plant p in _plants) {
      if (p.id == _selectedId) return p;
    }
    return _plants.isEmpty ? null : _plants.first;
  }

  /// 按 speciesId 找物种（找不到返回 null）。
  PlantSpecies? _speciesOf(Plant plant) {
    for (final PlantSpecies s in _species) {
      if (s.id == plant.speciesId) return s;
    }
    return null;
  }

  /// 重新读取植物 / 物种 / 可收集奖励 / 阳光余额，并对齐目标选择与滑杆。
  Future<void> _refresh() async {
    final List<Plant> plants = await _repo.plants();
    final List<PlantSpecies> species = await _repo.species();
    final DateTime now = DateTime.now();
    final Map<String, List<PendingBloomReward>> collectibles =
        await _svc.collectibleBloomRewards(now);
    final double balance = await ref.read(sunlightRepositoryProvider).balance();

    // 空盆调试（F157-FEAT-3）：容量 ← 设置（与花园页 `_capacity` 同源）；
    // 空盆 = 容量内无任何植物行占用的盆（死亡残株仍占盆，故不算空，与
    // `garden_page.dart` 的 `_occupantOf(i) == null` 判据逐字一致）。
    final AppSettings settings =
        await ref.read(settingsRepositoryProvider).getSettings();
    final int capacity = settings.gardenPotCapacity;
    final Set<int> occupied =
        <int>{for (final Plant p in plants) p.potIndex};
    final List<int> emptyPots = <int>[
      for (int i = 0; i < capacity; i++)
        if (!occupied.contains(i)) i,
    ];
    // 🔴 空盆**状态**的读库必须**旁路（不 await）**，理由与 `garden_page._refreshEmptyPots`
    // 逐字相同：纯 widget 测试宿主通常没注入 DB（`potDisturbanceRepositoryProvider`
    // 会落到真实 drift 仓储），`disturbances()` 的查询**可能永不返回**（不是抛错，是
    // await 不回来）。一旦在主路径 await，`_loaded` 永远为 false → 整个面板停在加载圈，
    // 存量用例（`bloom_debug_panel_test` / `consent_preview_test` /
    // `qa_independent_round2_ef_test` / `garden_bloom_reward_after_force_adult_test`）
    // 集体变红（本轮实测踩到过）。降级 = 状态回显显示「无记录」，按钮照常可用。
    unawaited(_refreshPotStates());

    // 稳定排序：先按花盆序号。
    plants.sort((Plant a, Plant b) => a.potIndex.compareTo(b.potIndex));

    if (!mounted) return;
    setState(() {
      _plants = plants;
      _species = species;
      _collectibleIds = collectibles.keys.toSet();
      _balance = balance;
      _capacity = capacity;
      _emptyPots = emptyPots;
      // 选中的空盆消失了（已种下 / 扩容取消）→ 回落到第一个空盆。
      if (_emptyPotSel == null || !emptyPots.contains(_emptyPotSel)) {
        _emptyPotSel = emptyPots.isEmpty ? null : emptyPots.first;
      }
      if (_selectedId == null ||
          !plants.any((Plant p) => p.id == _selectedId)) {
        _selectedId = plants.isEmpty ? null : plants.first.id;
      }
      final Plant? cur = _selected;
      if (cur != null) _slider = cur.growthProgress.clamp(0.0, 1.0);
      _loaded = true;
    });
  }

  /// 旁路读取各空盆的干扰物状态（**不 await、独立 try/catch、失败静默降级**）。
  ///
  /// 为什么旁路：见 [_refresh] 里 `unawaited(_refreshPotStates())` 处的注释
  /// （无 DB 的 widget 测试宿主里查询可能永不返回）。
  Future<void> _refreshPotStates() async {
    try {
      final List<PotDisturbance> rows = await _potRepo.disturbances();
      if (!mounted) return;
      setState(() {
        _potStates = <int, PotDisturbance>{
          for (final PotDisturbance d in rows) d.potIndex: d,
        };
      });
    } catch (_) {
      // 降级：状态回显退化为「今天还没 roll 过（无记录）」，三个按钮仍可用
      // （写操作各自走领域服务，错误由 [_run] 统一提示）。
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 包裹一次调试动作：busy 闸门 → 动作 → 异常提示 → 刷新 → 通知花园页。
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack('调试操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
    widget.onChanged?.call();
  }

  /// 写入目标植物字段（走仓储，落库后由 [PlantGrowthService.tickAll] 结算）。
  ///
  /// 同时把 `stageStartedAt` 推进到 `now`：避免 tickAll 用「真实的、长达数小时/天的
  /// `stageStartedAt → now` 区间」把调试写入的进度又累加一遍（保持调试确定性）。
  Future<void> _write(Plant p, {required double progress, DateTime? bloomedAt, bool forceAdult = false}) async {
    final DateTime now = DateTime.now();
    Plant np = p.copyWith(
      growthProgress: progress,
      stageStartedAt: now,
    );
    if (forceAdult) {
      np = np.copyWith(
        stage: PlantStage.adult,
        status: PlantStatus.growing,
        // 顺带把「上次浇水」刷新到 now，隔离出纯粹的开花链路，避免目标株恰好
        // 已 ≥3 天未浇水 → tick 时立刻枯萎、看不到「开花瞬间奖励」。
        lastWaterAt: now,
      );
    }
    if (bloomedAt != null) {
      np = np.copyWith(bloomedAt: bloomedAt);
    }
    await _repo.savePlant(np);
  }

  // ── 动作 ────────────────────────────────────────────────────────────────

  /// 应用滑杆进度并结算。
  Future<void> _applyProgress() => _run(() async {
        final Plant? p = _selected;
        if (p == null) return;
        await _write(p, progress: _slider.clamp(0.0, 1.0));
        await _svc.tickAll(DateTime.now());
      });

  /// 催熟到成株（stage=adult / progress=1.0）→ 应触发**开花瞬间奖励**。
  Future<void> _forceAdult() => _run(() async {
        final Plant? p = _selected;
        if (p == null) return;
        await _write(p, progress: 1.0, forceAdult: true);
        await _svc.tickAll(DateTime.now());
      });

  /// 立即花谢：把花期起点提前到「已超花期」→ 触发**花谢回落**。
  Future<void> _forceBloomEnd() => _run(() async {
        final Plant? p = _selected;
        if (p == null) return;
        if (p.status != PlantStatus.bloomed || p.bloomedAt == null) {
          _snack('该株当前不在花期，先点「催熟到成株」吧～');
          return;
        }
        final PlantSpecies? sp = _speciesOf(p);
        final Duration dur = _bloomDurationOf(sp);
        final DateTime now = DateTime.now();
        await _write(
          p,
          progress: p.growthProgress,
          bloomedAt: now.subtract(dur).subtract(const Duration(seconds: 1)),
        );
        await _svc.tickAll(now);
      });

  /// 让该株待领奖励「现在可领取」（把未领取记录的 `due_at` 改为 `now - 1s`）。
  ///
  /// 需目标株**正盛开**才会出现可收集气泡；否则 tickAll 会按兜底直接结算（不发气泡）。
  Future<void> _makeRewardDueNow() => _run(() async {
        final Plant? p = _selected;
        if (p == null) return;
        if (p.status != PlantStatus.bloomed) {
          _snack('先让该株处于「盛开」状态，花园页才会掉落可收集气泡～');
          return;
        }
        final DateTime now = DateTime.now();
        // 复用既有接口读「该株全部未领取」：pendingBloomRewardsDue(远未来) = 未领取全量
        // （实现按 `!claimed && dueAt <= now` 过滤，传远未来即取回含未到期者），
        // 从而无需为调试新增仓储方法、不动领域接口。
        final List<PendingBloomReward> pending =
            await _bloom.pendingBloomRewardsDue(DateTime(9999));
        final List<PendingBloomReward> mine =
            pending.where((PendingBloomReward r) => r.plantId == p.id).toList();
        if (mine.isEmpty) {
          _snack('该株暂无待收集的第二段奖励，先点「催熟到成株」开一次花～');
          return;
        }
        for (final PendingBloomReward r in mine) {
          // ⚠️ v12「掉落即定奖」：改写 dueAt 时必须**原样保留**奖励内容三列，
          // 否则会把已定好的奖励重置成零值哨兵（真实库会「丢奖」）。
          await _bloom.insertPendingBloomReward(PendingBloomReward(
            id: r.id,
            plantId: r.plantId,
            dueAt: now.subtract(const Duration(seconds: 1)),
            rewardKind: r.rewardKind,
            claimed: r.claimed,
            rewardSunlight: r.rewardSunlight,
            rewardFragments: r.rewardFragments,
            rewardSpeciesId: r.rewardSpeciesId,
          ));
        }
        await _svc.tickAll(now);
      });

  /// 强制长出杂草 / 害虫（调试）。
  ///
  /// 只写字段：`weedAt` / `pestAt` = **今日零点**，并把 `weedPestRollDay` 一并对齐到
  /// 今日（否则下次 `tickAll` 会再 roll 一次，可能把手工写入的状态覆盖掉）。
  /// 清除走花园页真实点击链路（`clearWeed` / `clearPest` 入账），面板不代劳。
  Future<void> _forceWeedPest({required bool weed}) => _run(() async {
        final Plant? p = _selected;
        if (p == null) return;
        if (p.status == PlantStatus.dead) {
          _snack('该株已死亡，不参与干扰物玩法～');
          return;
        }
        final DateTime now = DateTime.now();
        final DateTime day = DateTime(now.year, now.month, now.day);
        Plant np = p.copyWith(weedPestRollDay: day);
        np = weed
            ? np.copyWith(weedAt: day)
            : np.copyWith(pestAt: day);
        await _repo.savePlant(np);
        await _svc.tickAll(now);
      });

  /// 快进 +1 天：按当前档位把复开花自动回填量加到进度上 → 结算。
  ///
  /// 普通 [kRebloomAutoProgressPerDay]，精品 ÷[kRebloomPremiumCycleMultiplier]
  /// （与 `_advanceGrowth` 的复开花速率口径一致）。
  Future<void> _fastForwardOneDay() => _run(() async {
        final Plant? p = _selected;
        if (p == null) return;
        final PlantSpecies? sp = _speciesOf(p);
        final double div =
            (sp?.isPremium ?? false) ? kRebloomPremiumCycleMultiplier : 1.0;
        final double delta = kRebloomAutoProgressPerDay / div;
        final double next = (p.growthProgress + delta).clamp(0.0, 1.0);
        await _write(p, progress: next);
        await _svc.tickAll(DateTime.now());
      });

  // ── 空盆干扰物调试动作（F157-FEAT-3）─────────────────────────────────────

  /// 「空盆长草」/「空盆长虫」：给**选中的空盆**强制写入今天的干扰物。
  ///
  /// 走领域单点 [EmptyPotService.forceDisturbanceForDebug]（不绕过仓储直写数据，
  /// 语义与生产 roll 完全一致：`weedAt/pestAt = rollDay = 今天零点`）。
  Future<void> _forceEmptyPotDisturbance({required bool weed}) =>
      _run(() async {
        final int? idx = _emptyPotSel;
        if (idx == null) {
          _snack('没有空盆可调试：先铲掉一株，或先在花园里加一个盆位～');
          return;
        }
        await _emptyPotSvc.forceDisturbanceForDebug(
          potIndex: idx,
          weed: weed,
          now: DateTime.now(),
        );
      });

  /// 「空盆草虫全清」：对选中的空盆执行**生产同一条链路**的 [EmptyPotService.clearWeed]
  /// / [clearPest]（带前置校验 + 账本入账），草与虫各自独立结算。
  ///
  /// 为什么不在本面板直接改字段：清除要**入账**（与孩子真机点浮标完全一致），
  /// 玄参才能在同一次验收里核对「奖励到账 + 账本行」；面板不复制发奖逻辑
  /// （宪法总纪律 #2 单点收口）。
  ///
  /// 称号加成：调试路径按 [PlantPerk.none] 结算（不读门控 Provider —— 调试面板
  /// 不该依赖「当前孩子称号」这条异步链路；奖励金额差异不影响链路验证）。
  Future<void> _clearEmptyPotDisturbance() => _run(() async {
        final int? idx = _emptyPotSel;
        if (idx == null) {
          _snack('没有空盆可调试：先铲掉一株，或先在花园里加一个盆位～');
          return;
        }
        final DateTime now = DateTime.now();
        // 状态取面板已加载的回显（避免再打一次库）；面板尚未读到（无 DB 的宿主 /
        // 首次刷新未完成）时兜底现查一次。
        final PotDisturbance? d =
            _potStates[idx] ?? await _potRepo.disturbanceOf(idx);
        if (d == null || !d.hasPestOrWeed) {
          _snack('盆 #$idx 现在没有草 / 虫（先点「空盆长草」或「空盆长虫」）');
          return;
        }
        if (d.hasWeed) await _emptyPotSvc.clearWeed(idx, now);
        if (d.hasPest) await _emptyPotSvc.clearPest(idx, now);
      });

  /// 空盆序号 → 一行状态文案（面板「当前空盆」回显用）。
  String _emptyPotStateLabel(int potIndex) {
    final PotDisturbance? d = _potStates[potIndex];
    if (d == null) return '今天还没 roll 过（无记录）';
    if (!d.hasPestOrWeed) return '草 / 虫：无';
    if (d.hasWeed && d.hasPest) return '草 + 虫：都有$kGardenWeedEmoji$kGardenPestEmoji';
    if (d.hasWeed) return '草：有$kGardenWeedEmoji';
    return '虫：有$kGardenPestEmoji';
  }

  /// 分段成长**演出预览**（玄参 2026-10-13 拍板）：只播选定过渡的成长演出 + 该物种
  /// 音效，**不改植物状态**（纯预览，方便逐个物种验收 C59 的 15 段音效）。
  ///
  /// 播放/资产解析单点在花园页（[onPreviewGrowth] 回调），本面板只负责转发选中株的
  /// 物种目录 —— 不复制任何序列帧/音效逻辑。
  void _previewGrowth(GrowTransition t) {
    final Plant? p = _selected;
    if (p == null) return;
    widget.onPreviewGrowth?.call(t, growSpeciesDir(p.speciesId));
  }

  /// 目标档位的花期时长（普通 [kBloomDurationDays] / 精品 [kBloomDurationDaysPremium]）。
  Duration _bloomDurationOf(PlantSpecies? sp) {
    final double days = (sp?.isPremium ?? false)
        ? kBloomDurationDaysPremium
        : kBloomDurationDays.toDouble();
    return Duration(milliseconds: (days * Duration.millisecondsPerDay).round());
  }

  /// 调试：**+1 指定档位种子**（免费种植券）—— 玄参 2026-10-07「增加普通种子和精英
  /// 种子的测试按钮，不然测试无法有效获取」。
  ///
  /// 走领域单点 [PlantGrowthService.grantSeedForDebug]（不绕过仓储直写数据库）；发完
  /// 由 [_run] 统一 `_refresh` + `onChanged` → 花园页左上角种子计数 chip 立即刷新。
  Future<void> _grantSeed({required bool premium}) => _run(() async {
        final String? id = await _svc.grantSeedForDebug(premium: premium);
        if (id == null) {
          _snack(premium
              ? '精英种子已全部持有，无法再 +1（券按物种去重）'
              : '普通种子已全部持有，无法再 +1（券按物种去重）');
        }
      });

  /// 花期剩余文案（不在花期显示「—」）。
  String _bloomRemaining(Plant p) {
    if (p.status != PlantStatus.bloomed || p.bloomedAt == null) return '—';
    final Duration left =
        _bloomDurationOf(_speciesOf(p)) - DateTime.now().difference(p.bloomedAt!);
    if (left.isNegative) return '已过期';
    final int h = left.inHours;
    final int m = left.inMinutes % 60;
    return '${h}h ${m}m';
  }

  String _stageLabel(PlantStage s) {
    switch (s) {
      case PlantStage.seed:
        return '种子';
      case PlantStage.sprout:
        return '幼苗';
      case PlantStage.adult:
        return '成株';
    }
  }

  String _statusLabel(PlantStatus s) {
    switch (s) {
      case PlantStatus.growing:
        return '成长中';
      case PlantStatus.bloomed:
        return '盛开';
      case PlantStatus.wilting:
        return '枯萎';
      case PlantStatus.dead:
        return '死亡';
    }
  }

  /// 下拉项文案：物种名 · 阶段 · 状态 · 进度% · 开花次数 · 花期剩余。
  String _plantSummary(Plant p) {
    final PlantSpecies? sp = _speciesOf(p);
    final String name = sp?.name ?? p.speciesId;
    final String tier = (sp?.isPremium ?? false) ? '精品' : '普通';
    return '$name（$tier）· ${_stageLabel(p.stage)} · ${_statusLabel(p.status)} · '
        '${(p.growthProgress * 100).round()}% · 开花${p.bloomCount} · 花期剩 ${_bloomRemaining(p)}';
  }

  @override
  Widget build(BuildContext context) {
    final Plant? sel = _selected;
    return SizedBox(
      height: widget.maxHeight,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.science, size: 20, color: Colors.deepPurple),
                const SizedBox(width: 8),
                const Text(
                  '花期调试',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新'),
                ),
              ],
            ),
            const Text(
              '仅 debug 可见 · 面板只写字段 + 触发结算，开花/花谢/发奖仍走真实领域逻辑',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_plants.isEmpty) ...<Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('花园里还没有植物，先种一株再来调试吧～'),
              ),
              // 空盆调试与「有没有植物」无关：一株都没种也应该能用
              // （玄参场景 = 只有空盆，正是最需要强制长草的时刻）。
              _emptyPotSection(),
            ]
            else ...<Widget>[
              // ── 植物选择 ──────────────────────────────────────────────
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '目标植物',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedId,
                    isExpanded: true,
                    isDense: true,
                    items: <DropdownMenuItem<String>>[
                      for (final Plant p in _plants)
                        DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(
                            _plantSummary(p),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (String? id) {
                            if (id == null) return;
                            setState(() {
                              _selectedId = id;
                              final Plant? p = _selected;
                              if (p != null) {
                                _slider = p.growthProgress.clamp(0.0, 1.0);
                              }
                            });
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (sel != null) _statusCard(sel),
              const SizedBox(height: 12),
              // ── 进度条 ────────────────────────────────────────────────
              Row(
                children: <Widget>[
                  const Text('阶段进度', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  Text(
                    '${(_slider * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _slider.clamp(0.0, 1.0),
                onChanged: _busy
                    ? null
                    : (double v) => setState(() => _slider = v),
              ),
              const SizedBox(height: 4),
              // ── 动作按钮 ──────────────────────────────────────────────
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: _busy ? null : _applyProgress,
                    child: const Text('应用进度并结算'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _forceAdult,
                    child: const Text('催熟到成株'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _forceBloomEnd,
                    child: const Text('立即花谢'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _makeRewardDueNow,
                    child: const Text('让待领奖励可领取'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _fastForwardOneDay,
                    child: const Text('快进 +1 天'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _forceWeedPest(weed: true),
                    child: const Text('长出杂草$kGardenWeedEmoji'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _forceWeedPest(weed: false),
                    child: const Text('长出害虫$kGardenPestEmoji'),
                  ),
                  // 种子发放（玄参 2026-10-07「增加普通种子和精英种子的测试按钮」）：
                  // 走领域单点发券，发完花园页左上角计数 chip 立即刷新。
                  FilledButton.tonal(
                    onPressed:
                        _busy ? null : () => _grantSeed(premium: false),
                    child: const Text('+1 普通种子'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _grantSeed(premium: true),
                    child: const Text('+1 精英种子'),
                  ),
                  // 预览首启欢迎页（玄参 2026-10-07「打开软件直接进主页，看不到欢迎页，
                  // 无法反馈」）：只读打开 [ConsentPage]（preview:true），**不写同意状态、
                  // 不影响主流程**；先关掉本面板再推入，返回后即回到花园。
                  FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () {
                            final NavigatorState nav = Navigator.of(context);
                            nav.pop(); // 关闭调试面板 → 回到花园
                            nav.push<void>(MaterialPageRoute<void>(
                              builder: (_) => const ConsentPage(preview: true),
                            ));
                          },
                    child: const Text('预览首启欢迎页'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '分段成长演出预览（不改植物状态）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 6),
              // 玄参 2026-10-13：成长音效已按物种（C59），加 3 个纯预览按钮，
              // 点一下即播该段成长演出 + 该物种音效，便于逐个物种验收 15 段音效。
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: (sel == null || _busy)
                        ? null
                        : () => _previewGrowth(GrowTransition.seedToSprout),
                    child: const Text('发芽（种→苗）'),
                  ),
                  FilledButton.tonal(
                    onPressed: (sel == null || _busy)
                        ? null
                        : () => _previewGrowth(GrowTransition.sproutToAdult),
                    child: const Text('长大（苗→株）'),
                  ),
                  FilledButton.tonal(
                    onPressed: (sel == null || _busy)
                        ? null
                        : () => _previewGrowth(GrowTransition.adultToBloomed),
                    child: const Text('开花（株→花）'),
                  ),
                ],
              ),

              // ── 空盆干扰物调试（F157-FEAT-3）─────────────────────────────
              // 🔴 **位置纪律：必须留在列表末尾**（后面不要再往它上面插内容）。
              //    花园页/QA 既有 4 个用例在 360×780 下**不滚动**就 `find.text(...)`
              //    断言面板中段的状态卡与按钮（`bloom_debug_panel_test` /
              //    `qa_independent_round2_ef_test` / `consent_preview_test` /
              //    `garden_bloom_reward_after_force_adult_test`）；本区块插在顶部会把
              //    它们顶出 `ListView` 的懒构建窗口（默认 cacheExtent 250）→ 存量用例
              //    集体变红。放末尾 = 既有条目 offset 逐像素不变（零回归），
              //    新入口多滚一屏即可见（面板本来就是可滚动列表）。
              _emptyPotSection(),
            ],
          ],
        ),
      ),
    );
  }

  /// 空盆干扰物调试区块（F157-FEAT-3；玄参 2026-10-27「空盆验证不了」）。
  ///
  /// 三个动作都作用于**当前选中的空盆**（默认 = 第一个空盆，可在下拉里切换）：
  ///  · 「空盆长草」/「空盆长虫」→ [EmptyPotService.forceDisturbanceForDebug]；
  ///  · 「空盆草虫全清」→ [EmptyPotService.clearWeed] + [clearPest]（生产同链路、带入账）。
  ///
  /// 没有空盆时三个按钮**全部禁用**并给出可操作的提示文案（不静默、不空转）。
  Widget _emptyPotSection() {
    final int? sel = _emptyPotSel;
    final bool noEmptyPot = _emptyPots.isEmpty;
    final bool disabled = _busy || sel == null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8C79A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '空盆干扰（草 / 虫）',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          if (noEmptyPot)
            Text(
              '当前没有空盆（容量 $_capacity 盆全被占用）→ 先在花园里铲掉一株，'
              '或用「加盆」增加一个盆位',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            )
          else ...<Widget>[
            // 选中盆切换（多于一个空盆时才需要下拉，单盆时只显示文案）。
            if (_emptyPots.length > 1)
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: sel,
                  isExpanded: true,
                  isDense: true,
                  items: <DropdownMenuItem<int>>[
                    for (final int i in _emptyPots)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text(
                          '盆 #$i · ${_emptyPotStateLabel(i)}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (int? v) {
                          if (v == null) return;
                          setState(() => _emptyPotSel = v);
                        },
                ),
              ),
            Text(
              '目标：盆 #$sel · 容量 $_capacity 盆 · 空盆 ${_emptyPots.length} 个 · '
              '当前状态：${_emptyPotStateLabel(sel ?? -1)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: disabled
                    ? null
                    : () => _forceEmptyPotDisturbance(weed: true),
                child: const Text('空盆长草$kGardenWeedEmoji'),
              ),
              FilledButton.tonal(
                onPressed: disabled
                    ? null
                    : () => _forceEmptyPotDisturbance(weed: false),
                child: const Text('空盆长虫$kGardenPestEmoji'),
              ),
              FilledButton.tonal(
                onPressed: disabled ? null : _clearEmptyPotDisturbance,
                child: const Text('空盆草虫全清'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 状态回显卡：stage / status / growthProgress% / bloomCount / 花期剩余 /
  /// pending 是否可收集 / 阳光余额。
  Widget _statusCard(Plant p) {
    final PlantSpecies? sp = _speciesOf(p);
    final bool collectible = _collectibleIds.contains(p.id);
    final bool premium = sp?.isPremium ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6CCF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${sp?.name ?? p.speciesId}（${premium ? '精品' : '普通'}档）',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          _kv('阶段', _stageLabel(p.stage)),
          _kv('状态', _statusLabel(p.status)),
          _kv('阶段进度', '${(p.growthProgress * 100).round()}%'),
          _kv('累计开花', '${p.bloomCount} 次'),
          _kv('花期剩余', _bloomRemaining(p)),
          _kv('干扰物', _weedPestLabel(p)),
          _kv('待领奖励', collectible ? '已可收集（花园页有气泡）' : '未到期 / 无'),
          _kv('阳光余额', '${_balance.toInt()} ☀'),
        ],
      ),
    );
  }

  /// 干扰物状态文案（C26）：无 / 仅杂草 / 仅害虫 / 双双存在。
  String _weedPestLabel(Plant p) {
    if (!p.hasPestOrWeed) return '无';
    if (p.hasWeed && p.hasPest) return '杂草 + 害虫（成长暂停）';
    if (p.hasWeed) return '杂草（成长暂停）';
    return '害虫（成长暂停）';
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 72,
              child: Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            Expanded(
              child: Text(v, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
}
