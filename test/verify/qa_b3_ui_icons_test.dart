/// 独立复验探针 #6（qa-verify3）：**头顶奖励图标**（`bloom_reward_icons.dart`）。
///
/// 覆盖任务 #31 第 5 条：
///  · 图标数量与类型（阳光 / 碎片 / 种子 / 礼包）与库中三列**严格对应**；
///  · 点击任一图标 → 收下该条 pending 的**全部**奖励（按条收集）→ 该条全部图标消失；
///  · 点击经**真实服务**入账 → 账本**恰入账一次**（重复收集同一 id 不重复入账）；
///  · 窄屏不 overflow。
///
/// 图标用**内置 `Icons` 回退**判定（`availableAssets` 传空集 → `resolveRewardAsset` 恒 null），
/// 故可用 `find.byIcon` 精确断言「类型 ↔ 三列」的一致性。
library qa_b3_ui_icons_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_reward_icons.dart';

// ── 依赖替身 ────────────────────────────────────────────────────────────────

class _NoFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      const <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

final DateTime _past = DateTime(2026, 9, 25, 8);
PendingBloomReward _r(
  String id, {
  int sunlight = 0,
  int fragments = 0,
  String? seed,
  String kind = kBloomRewardKindNormal,
}) =>
    PendingBloomReward(
      id: id,
      plantId: 'p1',
      dueAt: _past,
      rewardKind: kind,
      rewardSunlight: sunlight,
      rewardFragments: fragments,
      rewardSpeciesId: seed,
    );

/// 有界帧推进（图标入场为有限时长动画，≤400ms）。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // A · 派生：三列 ↔ 图标数量/类型
  // ══════════════════════════════════════════════════════════════════════
  group('A · rewardIconSpecsFor 派生（三列 ↔ 图标）', () {
    test('阳光 → sunlight 图标 + 角标 +N', () {
      final List<RewardIconSpec> s = rewardIconSpecsFor(_r('a', sunlight: 10));
      expect(s, hasLength(1));
      expect(s.first.kind, RewardIconKind.sunlight);
      expect(s.first.badge, '+10');
    });

    test('阳光 + 碎片 → 两图标（sunlight + fragment，角标 ×N）', () {
      final List<RewardIconSpec> s =
          rewardIconSpecsFor(_r('a', sunlight: 10, fragments: 1));
      expect(s.map((RewardIconSpec x) => x.kind).toList(),
          <RewardIconKind>[RewardIconKind.sunlight, RewardIconKind.fragment]);
      expect(s[1].badge, '×1');
    });

    test('种子 → seed 图标（携带 speciesId）', () {
      final List<RewardIconSpec> s =
          rewardIconSpecsFor(_r('a', seed: 'species_tomato'));
      expect(s, hasLength(1));
      expect(s.first.kind, RewardIconKind.seed);
      expect(s.first.seedSpeciesId, 'species_tomato');
    });

    test('零值哨兵 0/0/null → 单个 gift 礼包图标', () {
      final List<RewardIconSpec> s = rewardIconSpecsFor(_r('a'));
      expect(s, hasLength(1));
      expect(s.first.kind, RewardIconKind.gift);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // B · 渲染：图标数量/类型与库中三列一致（回退内置 Icons）
  // ══════════════════════════════════════════════════════════════════════
  testWidgets('B · 多条目图标数量/类型严格对应三列', (WidgetTester tester) async {
    final List<PendingBloomReward> rewards = <PendingBloomReward>[
      _r('a', sunlight: 10, fragments: 1), // 2 图标：阳光 + 碎片
      _r('b', seed: 'species_tomato'), // 1 图标：种子
      _r('c'), // 1 图标：礼包
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: BloomRewardIconsBar(
            rewards: rewards,
            availableAssets: const <String>{}, // 空集 → 全回退内置 Icons
            onCollect: (PendingBloomReward _) {},
          ),
        ),
      ),
    ));
    await _settle(tester);

    expect(find.byType(BloomRewardIcon), findsNWidgets(4),
        reason: '2（a）+ 1（b）+ 1（c）= 4');
    expect(find.byIcon(Icons.wb_sunny), findsOneWidget, reason: '阳光图标');
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget, reason: '碎片图标');
    expect(find.byIcon(Icons.eco), findsOneWidget, reason: '种子图标');
    expect(find.byIcon(Icons.card_giftcard), findsOneWidget, reason: '礼包图标');
    // 角标数值来自真实数据，不写死。
    expect(find.text('+10'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════
  // C · 点击按条回收：点任一图标 → 该条全部图标消失
  // ══════════════════════════════════════════════════════════════════════
  testWidgets('C · 点击阳光图标 → 该条（阳光+碎片）两图标一并消失，其它条不受影响',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: _Host(
            initial: <PendingBloomReward>[
              _r('a', sunlight: 10, fragments: 1), // 该条 2 图标
              _r('b'), // 礼包 1 图标
            ],
          ),
        ),
      ),
    ));
    await _settle(tester);

    expect(find.byType(BloomRewardIcon), findsNWidgets(3));

    // 点「阳光」图标（属于条 a，含阳光 + 碎片）。
    await tester.tap(find.byIcon(Icons.wb_sunny));
    await _settle(tester);

    // 条 a 的两个图标（阳光 + 碎片）一并消失。
    expect(find.byIcon(Icons.wb_sunny), findsNothing);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    // 条 b 的礼包仍在。
    expect(find.byIcon(Icons.card_giftcard), findsOneWidget);
    expect(find.byType(BloomRewardIcon), findsNWidgets(1));
  });

  testWidgets('C2 · 点击碎片图标同样收下整条（回调收到该条 pending）',
      (WidgetTester tester) async {
    PendingBloomReward? got;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: BloomRewardIconsBar(
            rewards: <PendingBloomReward>[_r('a', sunlight: 10, fragments: 2)],
            availableAssets: const <String>{},
            onCollect: (PendingBloomReward r) => got = r,
          ),
        ),
      ),
    ));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.auto_awesome));
    await _settle(tester);
    expect(got, isNotNull);
    expect(got!.id, 'a', reason: '点任一图标 → 收下该条全部奖励');
  });

  // ══════════════════════════════════════════════════════════════════════
  // D · 集成：点击图标经真实服务入账 → 账本恰一次；重复收集不重复入账
  // ══════════════════════════════════════════════════════════════════════
  testWidgets('D · 点击图标经真实服务入账恰一次；同一 id 重复收集不重复入账',
      (WidgetTester tester) async {
    // 真实库 + 真实仓储 + 真实服务；只读一次、结算一次。
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
    addTearDown(database.close);

    final PlantLocalRepository plants = PlantLocalRepository(database);
    final SunlightLocalRepository ledger = SunlightLocalRepository(database);
    final SettingsLocalRepository settings = SettingsLocalRepository(database);
    await settings.saveSettings(const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: kDailyFocusCapLow,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: kPoolBudgetDefaultLow,
      gardenPotCapacity: 4,
    ));
    await ledger.append(SunlightEntry(
      id: 'seed',
      ts: DateTime(2026, 1, 1),
      type: SunlightType.earn,
      gross: 1000,
      net: 1000,
      balanceAfter: 1000,
      refType: 'seed',
      dayKey: '2026-01-01',
    ));
    final PlantGrowthService svc = PlantGrowthService(
      plants: plants,
      focus: _NoFocusRepo(),
      ledger: ledger,
      settings: settings,
      bloomRewards: plants,
    );

    final DateTime now = DateTime.now();
    // 已定奖的 pending（阳光 + 碎片）→ 头顶 2 图标。
    await plants.insertPendingBloomReward(PendingBloomReward(
      id: 'rp_ui',
      plantId: 'p1',
      dueAt: now.subtract(const Duration(hours: 1)),
      rewardKind: kBloomRewardPhaseInstant,
      rewardSunlight: 6,
      rewardFragments: 1,
    ));

    Future<void>? pendingCollect;
    final List<PendingBloomReward> seeded =
        await plants.pendingBloomRewardsDue(now);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: _Host(
            initial: seeded,
            onCollect: (PendingBloomReward r) async {
              pendingCollect = svc.collectBloomReward(r.id, now);
              await pendingCollect;
            },
          ),
        ),
      ),
    ));
    await _settle(tester);

    final double balBefore = await ledger.balance();
    final int fragBefore = await plants.premiumFragmentBalance();
    expect(find.byType(BloomRewardIcon), findsNWidgets(2));

    // 点阳光图标 → 收下整条（阳光 + 碎片）。
    await tester.tap(find.byIcon(Icons.wb_sunny));
    await tester.pump();
    await pendingCollect;
    await _settle(tester);

    expect(await ledger.balance() - balBefore, 6, reason: '账本恰入账一次 +6');
    expect(await plants.premiumFragmentBalance() - fragBefore, 1,
        reason: '碎片恰入账一次 +1');
    final int rows = (await database.customSelect(
      "SELECT COUNT(*) AS c FROM sunlight_ledgers WHERE ref_type = '$kBloomRewardRefType';",
    ).getSingle())
        .read<int>('c');
    expect(rows, 1, reason: '保底阳光恰一笔');
    // 图标消失（该条已领）。
    expect(find.byType(BloomRewardIcon), findsNothing);

    // 重复收集同一 id → 抛错、不再入账。
    await expectLater(
      () => svc.collectBloomReward('rp_ui', now),
      throwsA(isA<PlantOperationException>()),
    );
    expect(await ledger.balance() - balBefore, 6, reason: '重复收集不重复入账');
  });

  // ══════════════════════════════════════════════════════════════════════
  // E · 窄屏不 overflow
  // ══════════════════════════════════════════════════════════════════════
  testWidgets('E · 窄屏（60px）多图标不 overflow（FittedBox 缩放）',
      (WidgetTester tester) async {
    final List<PendingBloomReward> rewards = <PendingBloomReward>[
      for (int i = 0; i < 4; i++)
        _r('r$i', sunlight: 10 + i, fragments: 1, seed: 'species_tomato'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 60,
            height: 60,
            child: BloomRewardIconsBar(
              rewards: rewards,
              availableAssets: const <String>{},
              onCollect: (PendingBloomReward _) {},
            ),
          ),
        ),
      ),
    ));
    await _settle(tester);

    // 12 个图标（每条 3 个）仍在；无布局溢出异常。
    expect(find.byType(BloomRewardIcon), findsNWidgets(12));
    expect(tester.takeException(), isNull, reason: '窄屏不得 overflow');
  });
}

/// 有状态宿主：收集后移除该条 pending 并重建（模拟「点击任一图标 → 该条消失」）。
class _Host extends StatefulWidget {
  const _Host({required this.initial, this.onCollect});

  final List<PendingBloomReward> initial;
  final Future<void> Function(PendingBloomReward r)? onCollect;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<PendingBloomReward> _rewards = List<PendingBloomReward>.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return BloomRewardIconsBar(
      rewards: _rewards,
      availableAssets: const <String>{},
      onCollect: (PendingBloomReward r) async {
        await widget.onCollect?.call(r);
        if (mounted) {
          setState(() {
            _rewards =
                _rewards.where((PendingBloomReward x) => x.id != r.id).toList();
          });
        }
      },
    );
  }
}
