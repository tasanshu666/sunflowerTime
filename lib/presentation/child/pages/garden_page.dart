/// 孩子端花园页（M3 T02 / M3 修订）：植物列表 + 种植 / 浇水 / 施肥 / 救回 / 扩容。
///
/// 进页即跑一次 [PlantGrowthService.tickAll] 推进成长与枯萎计时；任意养护操作后
/// 重新 tick 并刷新。扣减经同账本，余额变化后自增 [economyRevisionProvider] 使孩子端
/// 阳光商店同步。
///
/// M3 修订（玄参大人真机反馈）：
///  · 页首常驻**阳光余额**——原先页面没有任何余额展示，扣了阳光也看不出来，
///    看起来像「浇水/施肥不消耗阳光」；
///  · 每株按 [PlantCareQuota] 渲染剩余次数（浇水 5 阳光/次、每日 3 次、间隔 30 分钟；
///    施肥 10 阳光/次、每日 1 次）；
///  · 动作期间置 [_busy] 闸门，避免连点绕过「不能连续浇水」。
library garden_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_card.dart';

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

class _GardenPageState extends ConsumerState<GardenPage> {
  List<Plant> _plants = <Plant>[];
  List<PlantSpecies> _species = <PlantSpecies>[];
  Map<String, PlantCareQuota> _quotas = <String, PlantCareQuota>{};
  AgeTier _tier = AgeTier.low;
  int _capacity = kGardenPotCapacityDefault;
  double _balance = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  int _price(PlantSpecies sp) =>
      _tier == AgeTier.low ? sp.baseCostLow : sp.baseCostHigh;

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
      _plants = await svc.tickAll(now);
      final AppSettings settings =
          await ref.read(settingsRepositoryProvider).getSettings();
      _tier = settings.ageTier;
      _capacity = settings.gardenPotCapacity;
      _species = await ref.read(plantRepositoryProvider).species();
      _quotas = await svc.careQuotas(_plants, now);
      _balance = await ref.read(sunlightRepositoryProvider).balance();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 执行养护动作：包裹异常 → SnackBar → 刷新 + 同步孩子端经济。
  ///
  /// [_busy] 期间直接忽略后续点击：浇水额度靠账本判定，但连点会在两次异步扣账
  /// 完成前同时通过校验，故必须在 UI 侧加串行闸门。
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.read(economyRevisionProvider.notifier).state++;
      await _reload(silent: true);
    } on PlantOperationException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// 扩容确认：先弹卡写明「当前阳光 / 将扣除多少 / 容量 N → N+1」，
  /// **只有点「确定，扣除」才真正调 `expandPot`**；点「取消」什么都不做、一分不扣。
  ///
  /// 仍经 [_run] 执行（异常 SnackBar + 经济修订号自增 + 静默刷新）。
  Future<void> _confirmAndExpand() async {
    if (_capacity >= kGardenPotCapacityMax || _busy) return;
    final int cost = _expandCost;
    // 兜底：横幅已把不足态渲染为禁用提示，此处再拦一次，避免任何路径下扣了才报错。
    if (_balance < cost) {
      _snack('阳光不足，还差 ${(cost - _balance).ceil()} ☀');
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

  void _openPlantSheet(int potIndex) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('选择要种的植物',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Text('当前阳光：${_balance.toInt()} ☀',
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          ..._species.map((PlantSpecies sp) {
            final int price = _price(sp);
            final bool affordable = _balance >= price;
            return ListTile(
              leading: const Icon(Icons.local_florist),
              title: Text(sp.name),
              subtitle: Text(_rarityLabel(sp.rarity)),
              trailing: Text(
                '$price 阳光',
                style: TextStyle(
                  color: affordable ? null : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _run(() => ref
                    .read(plantGrowthServiceProvider)
                    .plant(sp.id, potIndex, DateTime.now()));
              },
            );
          }),
        ],
      ),
    );
  }

  String _rarityLabel(Rarity r) =>
      r == Rarity.legendary ? '优良' : r == Rarity.rare ? '稀有' : '普通';

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = <Widget>[];
    for (int i = 0; i < _capacity; i++) {
      final Plant? occupant = _plants.cast<Plant?>().firstWhere(
            (Plant? p) => p != null && p.potIndex == i,
            orElse: () => null,
          );
      if (occupant == null) {
        tiles.add(_EmptyPotCard(
          potIndex: i,
          onPlant: () => _openPlantSheet(i),
        ));
      } else {
        final PlantSpecies sp = _species.cast<PlantSpecies?>().firstWhere(
              (PlantSpecies? s) => s?.id == occupant.speciesId,
              orElse: () => null,
            ) ??
            PlantSpecies(
              id: occupant.speciesId,
              name: '未知植物',
              rarity: Rarity.common,
              baseCostHigh: 0,
              baseCostLow: 0,
              growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
            );
        tiles.add(PlantCard(
          plant: occupant,
          species: sp,
          quota: _quotas[occupant.id],
          onWater: () => _run(() => ref
              .read(plantGrowthServiceProvider)
              .water(occupant.id, DateTime.now())),
          onFertilize: () => _run(() => ref
              .read(plantGrowthServiceProvider)
              .fertilize(occupant.id, DateTime.now())),
          onRevive: () => _run(() => ref
              .read(plantGrowthServiceProvider)
              .revive(occupant.id, DateTime.now())),
          onClear: () => _run(() async {
            await ref.read(plantRepositoryProvider).deletePlant(occupant.id);
          }),
        ));
      }
    }

    final Widget content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text('加载失败：$_error'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: <Widget>[
                  // 阳光余额横幅：养护扣费的可见性来源，内嵌下同样保留。
                  _SunlightBanner(balance: _balance),
                  const SizedBox(height: 8),
                  // 培养节奏说明（V2 数值，用户 2026-09-22：每次推进多少 + 每天能做几次）。
                  // 全部取自 prd_params 常量，数值随底层常量自动跟随，无裸字面量。
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.info_outline, size: 18, color: Colors.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '浇水 +${(kPlantWaterProgressGain * 100).round()}%'
                            '（每天最多 $kPlantWaterMaxPerDay 次）、'
                            '施肥 +${(kPlantFertilizeProgressGain * 100).round()}%'
                            '（每天 $kPlantFertilizeMaxPerDay 次）推进成长；'
                            '植物也会随时间慢慢生长，坚持养护才能开花 🌻',
                            style: const TextStyle(fontSize: 12, color: Colors.teal),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _CapacityBanner(
                    capacity: _capacity,
                    cost: _expandCost,
                    balance: _balance,
                    atMax: _capacity >= kGardenPotCapacityMax,
                    busy: _busy,
                    // 点击先弹确认卡（含价格与容量变化），确认后才真正扣费。
                    onExpand: _confirmAndExpand,
                  ),
                  const SizedBox(height: 8),
                  ...tiles,
                ],
              );

    // 内嵌（花园 tab）时不叠加第二层 Scaffold/AppBar，直接返回内容。
    if (widget.embedded) {
      return SafeArea(child: content);
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
      body: content,
    );
  }
}

/// 阳光余额横幅（养护消耗的可见性来源）。
class _SunlightBanner extends StatelessWidget {
  final double balance;
  const _SunlightBanner({required this.balance});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6DC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.wb_sunny, color: Color(0xFFE8A600)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('我的阳光',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              '${balance.toInt()} ☀',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD98F00)),
            ),
          ],
        ),
      );
}

/// 空花盆卡片（点击进入种植选择）。
class _EmptyPotCard extends StatelessWidget {
  final int potIndex;
  final VoidCallback onPlant;

  const _EmptyPotCard({required this.potIndex, required this.onPlant});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: InkWell(
          onTap: onPlant,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                const Icon(Icons.add_circle_outline, size: 28, color: Colors.grey),
                const SizedBox(width: 12),
                Text('花盆 #$potIndex · 点击种植',
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
}

/// 容量横幅 + 扩容入口。
///
/// 三态互斥（同一时刻只渲染其一，不会同时出现可点按钮与不可点提示）：
///  · 已达上限 → 灰字「已达上限」；
///  · 阳光不足 → 灰字「阳光不足（还差 N ☀）」，**不给可点按钮**——
///    避免孩子点了才发现扣不了（原先 `onExpand == null` 一律显示「已达上限」，会误导）；
///  · 可扩容 → 按钮带价格「扩容 +1 · N☀」，点击先走确认卡。
class _CapacityBanner extends StatelessWidget {
  final int capacity;
  final int cost;
  final double balance;
  final bool atMax;
  final bool busy;
  final VoidCallback? onExpand;

  const _CapacityBanner({
    required this.capacity,
    required this.cost,
    required this.balance,
    required this.atMax,
    required this.busy,
    this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final bool affordable = balance >= cost;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.yard, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '花园容量：$capacity / $kGardenPotCapacityMax 盆',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (atMax)
            const Text('已达上限', style: TextStyle(color: Colors.grey))
          else if (!affordable)
            Text(
              '阳光不足（还差 ${(cost - balance).ceil()} ☀）',
              style: const TextStyle(color: Colors.grey),
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : onExpand,
              icon: const Icon(Icons.add),
              label: Text('扩容 +1 · $cost☀'),
            ),
        ],
      ),
    );
  }
}
