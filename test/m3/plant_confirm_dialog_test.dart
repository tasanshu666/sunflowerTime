/// F134 种植确认卡单测（玄参 2026-10-19：「这个是种植确认卡片，可以帮我优化的
/// 漂亮一些吗？」）。
///
/// 覆盖三件事：
///  ① **文案红线**：标题 `要种下{物种名}吗？` + 按钮 `取消` / `确定种植` 一个字都不能变
///     （`plant_species_pricing_test` / `qa_independent_p0_care_sfx_behavior_test`
///     用 `find.text` 钉死，改了会让既有用例红）；
///  ② **返回语义**：确认 → `true`；取消 → `false`（调用方据此判定「分毫不扣」）；
///  ③ **不溢出**：小屏 320×568 + 1.3 倍字号（F126/F127 的老坑位）下零 overflow。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_confirm_dialog.dart';

const PlantSpecies _tomato = PlantSpecies(
  id: 'species_tomato',
  name: '番茄',
  rarity: Rarity.common,
  baseCostHigh: 300,
  baseCostLow: 300,
  growthHoursPerStage: 8,
);

const List<PlantConfirmRow> _sunlightRows = <PlantConfirmRow>[
  PlantConfirmRow(icon: Icons.wb_sunny, name: '本次种植', value: '−300 ☀'),
  PlantConfirmRow(
    icon: Icons.account_balance_wallet_outlined,
    name: '当前阳光',
    value: '1042 ☀',
    muted: true,
  ),
];

/// 弹卡宿主：点「open」→ 弹确认卡，把 `showDialog` 的返回值写进 [captured]。
///
/// 之所以不直接在用例里 `showDialog`：需要拿到**真实返回值**才能验证「取消不扣费」
/// 这条调用方契约（`_confirmAndPlant` 只看 `ok != true` 就 return）。
class _Host {
  bool? captured;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(390 * 3, 844 * 3),
    required Widget Function(BuildContext) build,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDialog<bool>(
                    context: context,
                    builder: build,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('① 文案红线：标题 / 明细 / 按钮与改前逐字一致', (WidgetTester tester) async {
    final _Host host = _Host();
    await host.pump(
      tester,
      build: (BuildContext _) => const PlantConfirmDialog(
        species: _tomato,
        rows: _sunlightRows,
        remainingText: '种下后剩余 742 ☀',
      ),
    );

    expect(find.text('要种下番茄吗？'), findsOneWidget);
    expect(find.text('确定种植'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    // 明细：本次动作 + 当前值 + 种下后剩余（新增的可读性信息）。
    expect(find.text('本次种植'), findsOneWidget);
    expect(find.text('−300 ☀'), findsOneWidget);
    expect(find.text('当前阳光'), findsOneWidget);
    expect(find.text('1042 ☀'), findsOneWidget);
    expect(find.text('种下后剩余 742 ☀'), findsOneWidget);
  });

  testWidgets('② 返回语义：确定种植 → true；取消 → false', (WidgetTester tester) async {
    final _Host confirm = _Host();
    await confirm.pump(
      tester,
      build: (BuildContext _) =>
          const PlantConfirmDialog(species: _tomato, rows: _sunlightRows),
    );
    await tester.tap(find.text('确定种植'));
    await tester.pumpAndSettle();
    expect(confirm.captured, isTrue, reason: '确认 → 调用方才允许扣费');
    expect(find.text('要种下番茄吗？'), findsNothing, reason: '点完必须关卡');

    final _Host cancel = _Host();
    await cancel.pump(
      tester,
      build: (BuildContext _) =>
          const PlantConfirmDialog(species: _tomato, rows: _sunlightRows),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(cancel.captured, isFalse, reason: '取消 → 分毫不扣（领域层未触达）');
    expect(find.text('要种下番茄吗？'), findsNothing);
  });

  testWidgets('③ 小屏 320×568 + 1.3 倍字号：零 overflow', (WidgetTester tester) async {
    // 1.3 倍字号模拟（F127 的溢出场就是这一档）。
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final _Host host = _Host();
    await host.pump(
      tester,
      size: const Size(320 * 3, 568 * 3),
      build: (BuildContext context) => const PlantConfirmDialog(
        species: _tomato,
        rows: <PlantConfirmRow>[
          PlantConfirmRow(
            icon: Icons.extension_outlined,
            name: '使用植物碎片',
            value: '−120 片',
          ),
          PlantConfirmRow(
            icon: Icons.inventory_2_outlined,
            name: '当前碎片',
            value: '12 片',
            muted: true,
          ),
        ],
        remainingText: '种下后剩余 0 片',
      ),
    );

    expect(find.text('要种下番茄吗？'), findsOneWidget);
    expect(find.text('确定种植'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '小屏 + 1.3 倍字号不得溢出');
  });
}
