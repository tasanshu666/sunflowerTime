/// 首株植物守卫说明卡（B13.15）的判定 + 弹卡测试。
///
/// 覆盖三条分支（K26~K28：期望值写字面量，不引实现常量反推）：
/// ① 花园有存活植物 && 未看过 ⇒ 弹卡；点「知道了」关闭并置位；
/// ② 已看过（flag 已置）⇒ 永不弹；
/// ③ 花园无植物 / 只有 dead 株 ⇒ 不弹且**不置位**（等真种了再讲）。
library guard_first_plant_dialog_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_first_plant_dialog.dart';

/// 内存桩仓储：返回固定列表。
class _StubPlants implements PlantRepository {
  final List<Plant> seed;
  _StubPlants(this.seed);

  @override
  Future<List<Plant>> plants() async => seed;

  @override
  Future<Plant?> plant(String id) async =>
      seed.where((Plant p) => p.id == id).firstOrNull;

  @override
  Future<void> savePlant(Plant plant) async {}

  @override
  Future<void> deletePlant(String id) async {}

  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[];
}

Plant _plant(String id, PlantStatus status) {
  final DateTime now = DateTime(2026, 11, 12);
  return Plant(
    id: id,
    speciesId: 'species_sunflower',
    potIndex: 0,
    stage: PlantStage.seed,
    stageStartedAt: now,
    growthFactor: 1.0,
    status: status,
    plantedAt: now,
  );
}

Future<SharedPreferences> _prefs({bool seen = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (seen) kGuardFirstPlantIntroSeenPrefKey: true,
  });
  return SharedPreferences.getInstance();
}

Widget _host(
  SharedPreferences sp,
  PlantRepository plants,
) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (BuildContext context) => Center(
        child: FilledButton(
          onPressed: () => maybeShowGuardFirstPlantIntro(
            context: context,
            l10n: AppLocalizations.of(context),
            sp: sp,
            plants: plants,
          ),
          child: const Text('go'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('① 有存活植物 && 未看过：弹卡；点「知道了」关闭并置位',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _prefs();
    await tester.pumpWidget(_host(
      sp,
      _StubPlants(<Plant>[
        _plant('p1', PlantStatus.growing),
        _plant('p2', PlantStatus.dead), // dead 不影响「有存活」判定
      ]),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guardFirstPlantIntro')), findsOneWidget,
        reason: '有存活植物 && 未看过 ⇒ 必须弹卡');
    expect(find.text('花园守卫来啦！'), findsOneWidget, reason: '标题文案（zh ARB）');
    expect(
        find.text(
            '花园里有了新的植物，听说会有小动物想来偷吃。不过别担心——向日葵战士会帮你守护花园的！'),
        findsOneWidget,
        reason: '正文文案（zh ARB，玄参 B13.15 第 5 条口径）');
    expect(find.byKey(const Key('guardFirstPlantOk')), findsOneWidget);

    await tester.tap(find.byKey(const Key('guardFirstPlantOk')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guardFirstPlantIntro')), findsNothing,
        reason: '点击「知道了」后关闭');
    expect(sp.getBool(kGuardFirstPlantIntroSeenPrefKey), isTrue,
        reason: '关闭后置位（一辈子一次）');
  });

  testWidgets('② 已看过：永不弹', (WidgetTester tester) async {
    final SharedPreferences sp = await _prefs(seen: true);
    await tester.pumpWidget(_host(
      sp,
      _StubPlants(<Plant>[_plant('p1', PlantStatus.growing)]),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.byKey(const Key('guardFirstPlantIntro')), findsNothing,
        reason: 'flag 已置 ⇒ 幂等跳过');
  });

  testWidgets('③ 花园无植物 / 只有 dead 株：不弹且不置位（等真种了再讲）',
      (WidgetTester tester) async {
    for (final List<Plant> garden in <List<Plant>>[
      <Plant>[],
      <Plant>[_plant('p1', PlantStatus.dead)],
    ]) {
      final SharedPreferences sp = await _prefs();
      await tester.pumpWidget(_host(
        sp,
        _StubPlants(garden),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.byKey(const Key('guardFirstPlantIntro')), findsNothing,
          reason: '没存活植物不弹（garden=${garden.length} 株）');
      expect(sp.getBool(kGuardFirstPlantIntroSeenPrefKey), isNull,
          reason: '不置位：下次种下真植物后仍要讲');
    }
  });
}
