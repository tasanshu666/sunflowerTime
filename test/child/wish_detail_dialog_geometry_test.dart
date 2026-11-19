/// 玄参 v0.3 真机反馈 4：愿望详情改**居中 Dialog** 的真实页面几何护栏。
///
/// 照 `test/child/wish_compose_dialog_test.dart` 的断言范式：真实 WishTreePage
/// + 真 DI + 真点愿望卡开详情；量卡片矩形（Dialog 自身铺满不可量），并对
/// 超高内容断言内部 SingleChildScrollView 真的接管滚动。
library wish_detail_dialog_geometry_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';

class _OfflineIap implements IapAdapter {
  @override
  Stream<IapMessage> get messages => const Stream<IapMessage>.empty();
  @override
  Future<bool> isStoreAvailable() async => false;
  @override
  Future<List<IapProduct>> queryProducts(Set<String> ids) async =>
      <IapProduct>[];
  @override
  Future<void> startLifetimePurchase(String id) async {}
  @override
  Future<void> startRestore() async {}
}

class _QuietSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        soundOn: false,
        bgmOn: false,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

Future<ProviderContainer> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(database),
      accountServiceProvider.overrideWithValue(account),
      iapServiceProvider.overrideWithValue(IapService(adapter: _OfflineIap())),
      settingsRepositoryProvider.overrideWithValue(_QuietSettings()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(database.close);
  return container;
}

Future<Finder> _openDetail(
  WidgetTester tester, {
  required double height,
  required ProviderContainer container,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final Wish wish = await container.read(wishOrchestrationServiceProvider)
      .createWish(
        text: '想要一只小乌龟',
        category: WishCategory.other,
        now: DateTime.now().subtract(const Duration(days: 2)),
        maxTextLength: kWishTextMaxLengthZh,
      );

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: WishTreePage()),
  ));
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  final Finder card = find.byKey(Key('wish_card_${wish.id}'));
  expect(card, findsOneWidget, reason: '真实愿望卡必须出现');
  await tester.tap(card);
  for (int i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  expect(tester.takeException(), isNull);
  return find.byKey(kWishDetailDialogKey);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AudioService.instance.resetForTest());

  testWidgets('① 详情卡居中：中心与屏高中心偏差 ≤24dp；不贴底；≤85% 屏高',
      (WidgetTester tester) async {
    final ProviderContainer c = await _boot();
    final Finder dialog = await _openDetail(tester, height: 844, container: c);
    expect(dialog, findsOneWidget, reason: '详情必须是居中 Dialog 而非 BottomSheet');
    final Rect rect = tester.getRect(dialog);
    expect((rect.center.dy - 844 / 2).abs(), lessThanOrEqualTo(24),
        reason: '详情卡必须居中');
    expect(rect.bottom, lessThanOrEqualTo(844 - 80),
        reason: '详情卡底边距屏幕底 ≥80dp（排除贴底观感）');
    expect(rect.height, lessThanOrEqualTo(844 * 0.85),
        reason: '详情卡最大高度 ≤85% 屏高');
  });

  testWidgets('② 超高内容由内部 SingleChildScrollView 接管（可滚不溢出）',
      (WidgetTester tester) async {
    final ProviderContainer c = await _boot();
    final Finder dialog = await _openDetail(tester, height: 400, container: c);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
      reason: '小屏上超高内容必须有内部滚动容器',
    );
    final Rect rect = tester.getRect(dialog);
    expect(rect.height, lessThanOrEqualTo(400 * 0.85 + 1));
    expect(tester.takeException(), isNull, reason: '不得出现 overflow 异常');
  });
}
