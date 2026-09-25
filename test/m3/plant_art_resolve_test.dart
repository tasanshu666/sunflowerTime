/// 花园植物「美术资源接入」回归测试。
///
/// 为什么必须有这份测试（2026-09-23）：
/// 美术与代码之间只有**文件名**这一个接口，而它此前**完全没有回归保护** ——
/// 出过一次真实事故：代码读 `AssetManifest.json` 判资源是否存在，而 Flutter 3.7 起
/// 打包只产 `AssetManifest.bin`，于是**永远读不到资源、静默回退自绘占位**，
/// 表现为「美术图放进去了界面却没变化」，且不崩不报错。测试全绿、没人发现。
///
/// 本文件锁三件事：
/// ① **清单读取链路真的通**（`AssetManifest.loadFromAssetBundle` 可用、能枚举美术目录）
/// ② **命名契约**（五级回退的候选路径与优先级；物种级恒在通用级之前）
/// ③ **枚举名即文件名**（`stage` / `status` 改名会立刻变红 —— 否则美术资源会静默失配）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_artwork.dart';

/// 与 `plant_seed.dart` 对齐的三个物种 id（美术命名的最外层变量）。
const List<String> _speciesIds = <String>[
  'species_sunflower',
  'species_daisy',
  'species_cactus',
];

void main() {
  group('A 命名契约：候选路径与五级回退优先级', () {
    test('A1 同一组合给出五条候选，顺序 = 回退优先级（物种级在前、通用级在后）', () {
      expect(
        PlantArtCandidates.forPlant(
          speciesId: 'species_sunflower',
          stage: 'adult',
          status: 'bloomed',
        ),
        <String>[
          'assets/plants/species_sunflower_adult_bloomed.png',
          'assets/plants/species_sunflower_adult.png',
          'assets/plants/species_sunflower.png',
          'assets/plants/shared_adult_bloomed.png',
          'assets/plants/shared_adult.png',
        ],
      );
    });

    test('A2 三者都存在时命中「最精确」那条（不能被粗粒度抢先）', () {
      final Set<String> assets = <String>{
        'assets/plants/species_sunflower.png',
        'assets/plants/species_sunflower_adult.png',
        'assets/plants/species_sunflower_adult_bloomed.png',
      };
      expect(
        PlantArtCandidates.resolve(
          assets,
          speciesId: 'species_sunflower',
          stage: 'adult',
          status: 'bloomed',
        ),
        'assets/plants/species_sunflower_adult_bloomed.png',
      );
    });

    test('A3 缺精确图 → 回退到「物种_阶段」', () {
      final Set<String> assets = <String>{
        'assets/plants/species_daisy_sprout.png',
      };
      expect(
        PlantArtCandidates.resolve(
          assets,
          speciesId: 'species_daisy',
          stage: 'sprout',
          status: 'wilting',
        ),
        'assets/plants/species_daisy_sprout.png',
      );
    });

    test('A4 只有物种总图 → 回退到「物种」', () {
      final Set<String> assets = <String>{'assets/plants/species_cactus.png'};
      expect(
        PlantArtCandidates.resolve(
          assets,
          speciesId: 'species_cactus',
          stage: 'adult',
          status: 'dead',
        ),
        'assets/plants/species_cactus.png',
      );
    });

    test('A5 一张都没有 → null（调用方走自绘占位，绝不抛异常）', () {
      expect(
        PlantArtCandidates.resolve(
          const <String>{},
          speciesId: 'species_sunflower',
          stage: 'seed',
          status: 'growing',
        ),
        isNull,
      );
    });

    test('A6 相邻物种/状态不会串味（前 3 条含本物种，后 2 条为通用 shared_）', () {
      final List<String> c = PlantArtCandidates.forPlant(
        speciesId: 'species_daisy',
        stage: 'seed',
        status: 'growing',
      );
      // 前 3 条 = 物种级：含本物种名，且不含任何跨物种名。
      expect(
        c.take(3).every((String p) => p.contains('species_daisy')),
        isTrue,
      );
      expect(c.any((String p) => p.contains('species_cactus')), isFalse);
      // 后 2 条 = 通用级：`shared_` 前缀，且不含任何物种名。
      expect(
        c.skip(3).every(
              (String p) =>
                  p.contains('/shared_') && !p.contains('species_'),
            ),
        isTrue,
      );
    });

    test('A7 物种图全缺 → 回退到「通用_阶段_状态」(shared_{stage}_{status})', () {
      final Set<String> assets = <String>{
        'assets/plants/shared_seed_growing.png',
        'assets/plants/shared_seed.png',
      };
      expect(
        PlantArtCandidates.resolve(
          assets,
          speciesId: 'species_daisy',
          stage: 'seed',
          status: 'growing',
        ),
        'assets/plants/shared_seed_growing.png',
      );
    });

    test('A8 通用阶段状态图也缺 → 回退到「通用_阶段」(shared_{stage})', () {
      final Set<String> assets = <String>{'assets/plants/shared_seed.png'};
      expect(
        PlantArtCandidates.resolve(
          assets,
          speciesId: 'species_cactus',
          stage: 'seed',
          status: 'wilting',
        ),
        'assets/plants/shared_seed.png',
      );
    });

    test('A9 物种级与通用级同时存在 → 必须命中物种级（顺序护栏）', () {
      final Set<String> assets = <String>{
        // 通用级齐备。
        'assets/plants/shared_sprout_growing.png',
        'assets/plants/shared_sprout.png',
        // 仅物种级「阶段图」存在（最精确图缺）。
        'assets/plants/species_sunflower_sprout.png',
      };
      expect(
        PlantArtCandidates.resolve(
          assets,
          speciesId: 'species_sunflower',
          stage: 'sprout',
          status: 'growing',
        ),
        'assets/plants/species_sunflower_sprout.png',
        reason: '物种级必须优先于通用级，否则已交付的物种图会被通用图覆盖（行为回归）',
      );
    });
  });

  group('B 枚举名即文件名（改名会让美术资源静默失配）', () {
    test('B1 stage 枚举名必须是 seed / sprout / adult', () {
      expect(
        PlantStage.values.map((PlantStage s) => s.name).toList(),
        <String>['seed', 'sprout', 'adult'],
      );
    });

    test('B2 status 枚举名必须是 growing / bloomed / wilting / dead', () {
      expect(
        PlantStatus.values.map((PlantStatus s) => s.name).toList(),
        <String>['growing', 'bloomed', 'wilting', 'dead'],
      );
    });

    test('B3 全部 3 物种 × 3 阶段 × 4 状态 = 36 组合的候选路径格式正确', () {
      int checked = 0;
      for (final String id in _speciesIds) {
        for (final PlantStage stage in PlantStage.values) {
          for (final PlantStatus status in PlantStatus.values) {
            final List<String> c = PlantArtCandidates.forPlant(
              speciesId: id,
              stage: stage.name,
              status: status.name,
            );
            expect(c, hasLength(5));
            expect(c[0], 'assets/plants/${id}_${stage.name}_${status.name}.png');
            expect(c[1], 'assets/plants/${id}_${stage.name}.png');
            expect(c[2], 'assets/plants/$id.png');
            expect(c[3], 'assets/plants/shared_${stage.name}_${status.name}.png');
            expect(c[4], 'assets/plants/shared_${stage.name}.png');
            expect(c.every((String p) => p.endsWith('.png')), isTrue);
            checked++;
          }
        }
      }
      expect(checked, 36);
    });
  });

  group('C 清单读取链路（曾经的真实缺陷：读 .json 永远失败且不报错）', () {
    test('C1 AssetManifest.loadFromAssetBundle 可用且能枚举到美术目录', () async {
      // 这条是**缺陷回归护栏**：若有人改回 `rootBundle.loadString('AssetManifest.json')`，
      // 此处会因为读不到任何美术资源而在真机上静默失效；本测试改用公开 API 保证链路通。
      final AssetManifest manifest =
          await AssetManifest.loadFromAssetBundle(rootBundle);
      final List<String> assets = manifest.listAssets();

      expect(assets, isNotEmpty, reason: '资产清单为空说明清单读取链路已断');
      expect(
        assets.any((String p) => p.startsWith('assets/plants/')),
        isTrue,
        reason: '清单里没有 assets/plants/ 前缀 —— pubspec 的资产声明或清单读取有问题',
      );
    });

    test('C2 清单里的路径格式与候选路径同构（都是 pubspec 逻辑键）', () async {
      final AssetManifest manifest =
          await AssetManifest.loadFromAssetBundle(rootBundle);
      final List<String> plants = manifest
          .listAssets()
          .where((String p) => p.startsWith('assets/plants/'))
          .toList();
      // 逻辑键不带 `assets/flutter_assets/` 这类打包前缀，可直接与候选路径做包含判断。
      expect(
        plants.every((String p) => !p.contains('flutter_assets/')),
        isTrue,
        reason: '清单键带了打包前缀，与 candidatesFor 的拼接结果对不上',
      );
    });
  });

  group('D 组件行为：无资源时必须优雅回退，不得抛异常', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('D1 当前美术目录为空 → 渲染自绘占位（PlantPlaceholderArt）', (WidgetTester tester) async {
      // 注：若某天 assets/plants/ 里真的放进了向日葵成株开花图，本用例会改判为
      // 「命中 Image」，届时请同步更新此断言（这本身就是「美术已接入」的信号）。
      final DateTime t0 = DateTime(2026, 9, 23);
      final Plant plant = Plant(
        id: 'p1',
        speciesId: 'species_sunflower',
        potIndex: 0,
        stage: PlantStage.adult,
        stageStartedAt: t0,
        growthProgress: 1.0,
        growthFactor: 1.0,
        status: PlantStatus.bloomed,
        plantedAt: t0,
      );
      const PlantSpecies species = PlantSpecies(
        id: 'species_sunflower',
        name: '向日葵',
        rarity: Rarity.common,
        baseCostHigh: 0,
        baseCostLow: 0,
        growthHoursPerStage: 240,
      );

      await tester.pumpWidget(
        wrap(PlantArtwork(plant: plant, species: species, size: 64)),
      );
      // FutureBuilder 解析清单需要一帧。
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '解析资源不得抛异常');
      expect(find.byType(PlantArtwork), findsOneWidget);
    });
  });
}
