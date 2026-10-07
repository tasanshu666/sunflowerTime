/// 首启欢迎 / 同意页 · 矮屏无溢出回归（玄参 2026-10-07 美化改版）。
///
/// 覆盖：
///  · 360×640（矮屏）与 402×874（iPhone）两档均**无 RenderFlex 溢出**；
///  · 向日葵吉祥物图（[kConsentSunflowerKey]）已加入；
///  · 合规文案（一个字不改）仍在；
///  · 「同意并开始」按钮仍在。
library consent_page_layout_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/presentation/shared/consent_page.dart';

Future<Widget> _host() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: <Override>[
      settingsStoreProvider.overrideWithValue(SettingsStore(sp)),
    ],
    child: const MaterialApp(home: ConsentPage()),
  );
}

Future<void> _pumpAt(WidgetTester tester, Size logical) async {
  tester.view.physicalSize = Size(logical.width * 3, logical.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await _host());
  // 有界 pump（图片资源在测试环境可能缺失 → errorBuilder 回退；不 pumpAndSettle）。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  for (final Size size in <Size>[const Size(360, 640), const Size(402, 874)]) {
    testWidgets(
        '${size.width.toInt()}×${size.height.toInt()}：无溢出 + 吉祥物 + 合规文案',
        (WidgetTester tester) async {
      await _pumpAt(tester, size);

      // 无溢出（debug 下溢出经 FlutterError.reportError → takeException 非空即红）。
      expect(tester.takeException(), isNull,
          reason: '${size.width.toInt()}×${size.height.toInt()} 首启页不得溢出');

      expect(find.text('欢迎使用向日葵专注'), findsOneWidget);
      // 合规文案一字不改（抽查首尾行）。
      expect(find.textContaining('我们只收集专注时长、打卡等必要数据'),
          findsOneWidget);
      expect(find.textContaining('不采集通讯录与位置'), findsOneWidget);
      // 吉祥物 + 主按钮。
      expect(find.byKey(kConsentSunflowerKey), findsOneWidget,
          reason: '首启页应加入向日葵盛开吉祥物图');
      // 向日葵尺寸（玄参 2026-10-07 真机反馈「美术太大、缩小一些」）：外框宽 ≈ 屏宽 42%
      // （钳位 120–190）。两档测试尺寸（360 / 402）均在钳位区间内 → 恰为屏宽×0.42；
      // 用外框 [kConsentSunflowerBoxKey] 度量（图缺失时 Image 回退 errorBuilder，尺寸不等外框）。
      final double boxW =
          tester.getSize(find.byKey(kConsentSunflowerBoxKey)).width;
      expect(boxW, moreOrLessEquals(size.width * 0.42, epsilon: 1.0),
          reason: '向日葵外框宽应≈屏宽 42%×${size.width.toInt()}（钉住缩小后的新口径）实测 $boxW');
      expect(boxW, inInclusiveRange(120.0, 190.0),
          reason: '向日葵外框宽应落在钳位区间 [120,190]，实测 $boxW');
      expect(find.text('同意并开始'), findsOneWidget);
    });
  }
}
