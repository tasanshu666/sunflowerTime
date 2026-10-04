/// 结算页护眼接线测试（玄参 2026-10-04 口径）。
///
/// 覆盖三件事：
///  ① **文案**：结算页「收到阳光」改为「收集阳光」；「护眼奖励」行恒显示
///     （未触发 / 跳过 → `0 ☀️`）。
///  ② **C28 §1 场末插入点接线**（修复交付遗漏：`eyeCarePending` 此前从未被
///     结算页消费）——带 `eyeCarePending: true` 进场时护眼卡压在结算页之上，
///     结算数字以「···」占位不抢先露出；护眼**完成**后显示 `+2 ☀️` 且账本
///     恰有一条 `eye_care_break`（唯一真源，护眼卡内部写入）。
///  ③ **跳过**：二次确认后回结算页，「护眼奖励」显示 `0 ☀️`，账本零写入。
///
/// ⚠️ 护眼页内嵌 SunflowerCanvas 无限呼吸动画 → **禁用 pumpAndSettle**，
/// 一律有界 pump（与 eye_care_page_test 同纪律）。
library settle_eye_care_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/eye_care_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';

/// 记录 append 的假账本（与 eye_care_page_test 同款）。
class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository(this.startBalance);

  final double startBalance;
  final List<SunlightEntry> appended = <SunlightEntry>[];

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(appended);

  @override
  Future<double> balance() async => startBalance;

  @override
  Future<double> append(SunlightEntry entry) async {
    appended.add(entry);
    return startBalance + entry.net;
  }

  @override
  Future<double> dayNet(String dayKey) async => 0;

  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;

  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this.settings);
  final AppSettings settings;
  @override
  Future<AppSettings> getSettings() async => settings;
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

/// 默认设置（护眼三项取实体默认：开 / 20 分钟 / 允许跳过；[skipAllowed] 可关）。
AppSettings _defaultSettings({bool skipAllowed = true}) => AppSettings(
      ageTier: AgeTier.high,
      dailyFocusCap: 60,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 400,
      eyeCareSkipAllowed: skipAllowed,
    );

/// 固定手机尺寸（默认 800×600 画布会把「跳过」等出口按钮顶到屏幕外 → tap 落空，
/// 与 eye_care_page_test 同坑同解）。
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 有界收敛（护眼页呼吸动画 → 禁 pumpAndSettle）。
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _pumpSettlePage(
  WidgetTester tester, {
  required _FakeSunlightRepository ledger,
  required AppSettings settings,
  required bool eyeCarePending,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(ledger),
      settingsRepositoryProvider.overrideWithValue(
        _FakeSettingsRepository(settings),
      ),
      audioServiceProvider.overrideWithValue(
        AudioService(playerFactory: () => null), // headless 无音频后端
      ),
    ],
    child: MaterialApp(
      home: SettlePage(
        args: SettleArgs(eyeCarePending: eyeCarePending),
      ),
    ),
  ));
}

/// 「护眼奖励」行的值文本（按行定位：值可能与「今日累计 0 ☀️」撞文案，
/// 直接 find.text 会误判多条）。
String _eyeCareRowValue(WidgetTester tester) {
  final Iterable<Element> rows = find
      .ancestor(of: find.text('护眼奖励'), matching: find.byType(Row))
      .evaluate();
  for (final Element e in rows) {
    final Row row = e.widget as Row;
    if (row.children.length == 2 && row.children.last is Text) {
      return (row.children.last as Text).data ?? '<no data>';
    }
  }
  return '<row not found>';
}

void main() {
  testWidgets('文案：显示「收集阳光」（不再「收到阳光」）+ 护眼奖励行恒显示 0', (tester) async {
    final _FakeSunlightRepository ledger = _FakeSunlightRepository(100);
    _usePhoneScreen(tester);
    await _pumpSettlePage(
      tester,
      ledger: ledger,
      settings: _defaultSettings(),
      eyeCarePending: false,
    );
    await _settle(tester);

    expect(find.text('收集阳光'), findsOneWidget);
    expect(find.text('收到阳光'), findsNothing);
    expect(find.text('护眼奖励'), findsOneWidget);
    expect(_eyeCareRowValue(tester), '0 ☀️'); // 未触发护眼 → 0
    expect(ledger.appended, isEmpty);
  });

  testWidgets('eyeCarePending：先护眼后领奖励——占位「···」→ 完成 → +2 ☀️ 且账本一条', (tester) async {
    final _FakeSunlightRepository ledger = _FakeSunlightRepository(100);
    _usePhoneScreen(tester);
    await _pumpSettlePage(
      tester,
      ledger: ledger,
      settings: _defaultSettings(),
      eyeCarePending: true,
    );
    await _settle(tester);

    // 护眼卡压在结算页之上：占位生效、护眼卡「完成休息」按钮可见。
    // ⚠️ 全屏不透明路由入场后，下方结算页被 Navigator 标记 offstage，
    // find.text 默认 skipOffstage:true 会漏掉 → 必须显式 skipOffstage:false。
    expect(
      find.text('···', skipOffstage: false),
      findsWidgets,
      reason: '护眼未收口时结算数字不抢先露出',
    );
    expect(find.text('完成休息'), findsOneWidget);

    // 快进 61 秒 → 护眼卡自然完成（内部写账本 +2）并回结果。
    await tester.pump(const Duration(seconds: 61));
    await _settle(tester);

    expect(find.text('···'), findsNothing, reason: '护眼收口后占位应解除');
    expect(_eyeCareRowValue(tester), '+2 ☀️');
    expect(ledger.appended.length, 1, reason: '完成护眼恰写一条账本');
    expect(ledger.appended.single.refType, kEyeCareRefType);
    expect(ledger.appended.single.net, kEyeCareRewardSunlight.toDouble());
  });

  testWidgets('eyeCarePending + 允许跳过：二次确认跳过 → 0 ☀️ 且账本零写入', (tester) async {
    final _FakeSunlightRepository ledger = _FakeSunlightRepository(100);
    _usePhoneScreen(tester);
    await _pumpSettlePage(
      tester,
      ledger: ledger,
      settings: _defaultSettings(), // 默认允许跳过
      eyeCarePending: true,
    );
    await _settle(tester);

    await tester.tap(find.text('跳过'));
    await _settle(tester);
    await tester.tap(find.text('确定跳过')); // 二次确认
    await _settle(tester);

    expect(find.text('···'), findsNothing);
    expect(_eyeCareRowValue(tester), '0 ☀️', reason: '跳过护眼 → 护眼奖励显示 0');
    expect(ledger.appended, isEmpty, reason: '跳过不写账本');
  });
}
