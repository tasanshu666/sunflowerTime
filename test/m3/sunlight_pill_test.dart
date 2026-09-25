/// 阳光胶囊 · 溢出回归测试（2026-09-23 真机 Bug）。
///
/// 真机症状：AppBar `leading` 宽度有限（原 leadingWidth 96，扣掉左边距实际 ≈84px），
/// 余额位数一多（如 1000）文字放不下 → Row 溢出换行，出现竖排数字。
/// 修复：胶囊内容包 `FittedBox(BoxFit.scaleDown)` 自适应缩放 + leadingWidth 96→112。
/// 本用例把胶囊塞进窄约束里渲染 **6 位**余额 —— 一旦溢出，Flutter 的 RenderFlex
/// overflow 会以 FlutterError 上报 → `tester.takeException()` 抓到 → 用例红。
library sunlight_pill_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/presentation/child/widgets/sunlight_pill.dart';

void main() {
  testWidgets('大余额（6 位）在 AppBar leading 窄约束下不溢出（自动缩放）',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sunlightBalanceProvider
              .overrideWith((ref) => Future<double>.value(123456.0)),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              leadingWidth: 112,
              leading: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Center(child: SunlightPill()),
              ),
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: '胶囊在窄约束下溢出（RenderFlex overflow）——真机「阳光数字竖排」回归',
    );
    expect(find.textContaining('123456'), findsOneWidget);
  });

  testWidgets('小余额常规渲染不受影响（缩放不应改变 4 位以内布局）',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sunlightBalanceProvider
              .overrideWith((ref) => Future<double>.value(100.0)),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              leadingWidth: 112,
              leading: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Center(child: SunlightPill()),
              ),
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('100 ☀'), findsOneWidget);
  });
}
