/// 天气系统 A6 期 · **盛开态卡片的文案分支与进度区折叠边界** 守卫。
///
/// ## 为什么需要这份文件（A6 盘点结论 + 一次自我纠错）
/// A6 盘点时我把「`card_hint_bloomed` / `card_hint_bloom_left` 全仓 0 例」写进了报告，
/// 其中**后半句是误报**：`test/verify/qa_b2_ui_probes_test.dart:210-250` 有一整个
/// `group('F2 · PlantCard 花期剩余 X 天')`，普通 3 天 / 精品 4.5 天 / growing 不出现 /
/// `bloomedAt` 缺失不编造 —— 4 条都在。
///
/// 🔴 **教训（已写进 A6 复盘）**：那个文件断的是**中文原文**（`find.text('花期剩余 3 天')`），
/// 而我 grep 的是 l10n 的 **key 名**（`card_hint_bloom_left`）⇒ 零命中。本仓测试大量
/// 用「中文原文」断言，所以判「某文案有没有被测」必须**同时** grep `app_zh.arb`
/// 里的中文原文，只 grep key 名会误报。
///
/// 剥掉那 4 条之后，`plant_card` 的盛开态真正空白的只剩两件：
///
/// ### ① `card_hint_bloomed` 这条**分支**没测
/// `_nextStageHint`（`plant_card.dart:164-207`）是**顺序敏感**的：
/// ```
/// dead → null ;  bloomed → card_hint_bloomed ;  remaining<=1e-3 → next_soon ;  ...
/// ```
/// 盛开的植物 `growthProgress == 1.0` ⇒ `remaining == 0`。若有人把 `bloomed` 那一支
/// 挪到 `remaining` 判断**之后**，盛开卡就会显示「即将进入下一阶段…」——一句
/// 永远不会发生的话（它已经在终点了）。现有用例一条都抓不住。
///
/// ### ② F182 的折叠条件可能被写宽
/// A5-a 的 F182 把整块成长区折叠成 `if (!isDead)`（`:448`）。若有人想当然改成
/// 「只有还在长的才需要进度区」（`&& status == growing`），**盛开态的进度条 +
/// 「花期剩余」两行会一起消失**，而那 4 条 B2 用例断的正是这两行里的文字 ⇒
/// 它们会红 —— 所以这条其实**已经被间接覆盖**。本文件只补一条**直接**断言，
/// 让「F182 误伤盛开态」这个归因一步到位，而不是从「花期剩余不见了」反推。
///
/// ## 一条被砍掉的用例（A6 自查，附硬证据）
/// 原计划还有一条「`N > 999` 时天数文案必须是 999」。实测**不可达**：
/// `dailyEstimateProgress` = 自然项 + 养护项 + 雨水代劳，而养护项至少是
/// `1 次施肥 × kPlantFertilizeProgressGain × f`（施肥额度 9 种日型恒 1，永不为 0）⇒
/// 遍历「全部真实物种 × 首花/复花 × 9 日型」的 `daily` 最小值 = **0.0322**，
/// 对应最大天数 `ceil(1 / 0.0322)` = **32 天**（最坏组合：月光兰 · 复花 · 暴雨）。
/// 要凑出 `N > 999` 必须伪造一个 `waterQuota == 0 && fertilizeQuota == 0` 的
/// `WeatherDay` —— 那是生产永不出现的输入，测它等于给死代码写护栏。
/// **故本条不写**（宁缺不凑）。
library weather_a6_card_hint_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_card.dart';

/// 向日葵（`growthHoursPerStage` 从种子表口径取，不在测试里另编一个）。
const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: 'Sunflower',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 盛开时刻（固定值，让「花期剩余」可复现）。
final DateTime _bloomedAt = DateTime(2026, 5, 12, 9);

/// 一张**盛开**的卡：进度已满、`bloomCount == 1`。
Plant _bloomedPlant() => Plant(
      id: 'plant-bloomed',
      speciesId: _sunflower.id,
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: _bloomedAt,
      growthProgress: 1.0,
      growthFactor: 1.0,
      status: PlantStatus.bloomed,
      plantedAt: _bloomedAt,
      bloomedAt: _bloomedAt,
      bloomCount: 1,
    );

/// 与盛开态同一瞬间的额度快照（`observedAt == bloomedAt` ⇒ 花期剩余取满值）。
PlantCareQuota _quotaAt(DateTime at, WeatherDay day) => PlantCareQuota(
      waterUsedToday: 0,
      fertilizeUsedToday: 0,
      minutesUntilNextWater: 0,
      waterBlockReason: null,
      fertilizeBlockReason: null,
      waterQuota: 3,
      weather: day,
      observedAt: at,
    );

Future<void> _pumpCard(
  WidgetTester tester, {
  required Plant plant,
  required PlantSpecies species,
  required PlantCareQuota quota,
}) async {
  tester.view.physicalSize = const Size(392 * 3, 1000 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  AppLocaleController.init(AppLanguage.zh);
  addTearDown(() => AppLocaleController.init(AppLanguage.system));

  await tester.pumpWidget(
    MaterialApp(
      home: L10nScope(
        child: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: PlantCard(
                  plant: plant,
                  species: species,
                  quota: quota,
                  onWater: () {},
                  onFertilize: () {},
                  onClear: () {},
                  onShovel: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // 有界 pump（禁用 pumpAndSettle：卡片内有动画基线）。
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  final AppLocalizations zh = AppLocalizationsZh();

  group('C1 · 盛开态走的是 `bloomed` 分支（不是「即将进入下一阶段」）', () {
    testWidgets('盛开的卡显示「已开花…」而不是 next_soon / grow_days', (WidgetTester tester) async {
      final Plant plant = _bloomedPlant();
      // 前提：盛开的判定依据就是进度已满 —— 这正是「remaining == 0」的来源。
      expect(plant.growthProgress, 1.0, reason: '前置：盛开态进度必须是 1.0');

      await _pumpCard(
        tester,
        plant: plant,
        species: _sunflower,
        quota: _quotaAt(_bloomedAt, WeatherSystem.ofDay(_bloomedAt)),
      );

      expect(
        find.text(zh.card_hint_bloomed),
        findsOneWidget,
        reason: '盛开卡必须走 `card_hint_bloomed`（「已开花 🌻 每天养护，明天晨露阳光满额」）',
      );
      // 🔴 这两条才是本条的真价值：`_nextStageHint` 的分支是**顺序敏感**的，
      //    `bloomed` 必须排在 `remaining <= 1e-3` **之前**。若顺序颠倒，
      //    盛开的卡会显示一句永远不会发生的话（它已经在终点，不可能再进下一阶段）。
      expect(
        find.text(zh.card_hint_next_soon),
        findsNothing,
        reason: '盛开态不得显示「即将进入下一阶段…」—— 它已经在终点，'
            '这句话永远为假。若 `bloomed` 分支被挪到 `remaining <= 1e-3` 之后，这里会红',
      );
      expect(
        find.textContaining('还需约'),
        findsNothing,
        reason: '盛开态不得出现任何「还需约 N 天长成」的天数文案',
      );
    });
  });

  group('C2 · F182 的折叠条件不得误伤盛开态', () {
    testWidgets('盛开的卡仍渲染进度条与百分比（只有死亡态才整块折叠）', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        plant: _bloomedPlant(),
        species: _sunflower,
        quota: _quotaAt(_bloomedAt, WeatherSystem.ofDay(_bloomedAt)),
      );

      // `plant_card.dart:448` 的折叠条件是 `if (!isDead)`。若被写宽成
      // `if (!isDead && status == growing)`（「只有还在长的才需要进度区」这种想法很自然），
      // 盛开态的进度区会整块消失 —— 而「花期剩余」那一行就在同一块里。
      expect(
        find.byType(LinearProgressIndicator),
        findsOneWidget,
        reason: '盛开态必须仍有进度条（F182 只折叠死亡态，不是「非成长中」都折叠）',
      );
      expect(
        find.text('100%'),
        findsOneWidget,
        reason: '盛开态进度是 100%，必须照常显示百分比',
      );
      // 同屏还应有花期剩余（B2 期已覆盖其文案内容，这里只证它没被折叠带走）。
      expect(
        find.textContaining('花期剩余'),
        findsOneWidget,
        reason: '「花期剩余」与进度条同属被折叠的那一块，必须同存同亡',
      );
    });
  });
}
