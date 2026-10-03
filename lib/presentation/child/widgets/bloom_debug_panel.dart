/// 花园页「花期调试」面板（**仅 `kDebugMode`** · 成株后循环玩法 Batch 1 验收辅助）。
///
/// ## 用途
/// 产品 / 开发在 iOS 模拟器上验收「花开花谢」时，不必等真实天数即可驱动完整链路：
/// 成株 → 开花瞬间奖励 → 盛开 3 / 4.5 天 → 花谢回落 → 复开花 → 开花 48h 掉落气泡 →
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
library bloom_debug_panel;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

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
}) {
  // 面板高度取自**调用方**（花园页）的 MediaQuery（可靠）；面板自身不再依赖
  // sheet 内 MediaQuery，避免底部弹窗上下文中尺寸读取异常导致内容被布局到屏幕外。
  final double maxHeight = MediaQuery.of(context).size.height * 0.85;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext _) =>
        BloomDebugSheet(maxHeight: maxHeight, onChanged: onChanged),
  );
}

/// 「花期调试」面板本体（可滚动）。
///
/// 直接读 / 写 Provider 暴露的仓储与服务；所有动作后都调 [PlantGrowthService.tickAll]
/// 走真实结算，再回调 [onChanged] 让花园页刷新。
class BloomDebugSheet extends ConsumerStatefulWidget {
  const BloomDebugSheet({super.key, this.maxHeight = 560, this.onChanged});

  /// 面板内容高度（由 [showBloomDebugPanel] 依调用方屏幕算出）。
  final double maxHeight;

  /// 动作完成后的回调（花园页据此刷新）。
  final VoidCallback? onChanged;

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  PlantRepository get _repo => ref.read(plantRepositoryProvider);
  BloomRewardRepository get _bloom => ref.read(bloomRewardRepositoryProvider);
  PlantGrowthService get _svc => ref.read(plantGrowthServiceProvider);

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

    // 稳定排序：先按花盆序号。
    plants.sort((Plant a, Plant b) => a.potIndex.compareTo(b.potIndex));

    if (!mounted) return;
    setState(() {
      _plants = plants;
      _species = species;
      _collectibleIds = collectibles.keys.toSet();
      _balance = balance;
      if (_selectedId == null ||
          !plants.any((Plant p) => p.id == _selectedId)) {
        _selectedId = plants.isEmpty ? null : plants.first.id;
      }
      final Plant? cur = _selected;
      if (cur != null) _slider = cur.growthProgress.clamp(0.0, 1.0);
      _loaded = true;
    });
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

  /// 让 48h 第二段奖励「现在可领取」（把该株未领取记录的 `due_at` 改为 `now - 1s`）。
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

  /// 目标档位的花期时长（普通 [kBloomDurationDays] / 精品 [kBloomDurationDaysPremium]）。
  Duration _bloomDurationOf(PlantSpecies? sp) {
    final double days = (sp?.isPremium ?? false)
        ? kBloomDurationDaysPremium
        : kBloomDurationDays.toDouble();
    return Duration(milliseconds: (days * Duration.millisecondsPerDay).round());
  }

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
            else if (_plants.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('花园里还没有植物，先种一株再来调试吧～'),
              )
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
                    child: const Text('让 48h 奖励可领取'),
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
                ],
              ),
            ],
          ],
        ),
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
          _kv('48h 奖励', collectible ? '已可收集（花园页有气泡）' : '未到期 / 无'),
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
