/// 🔴 C128（玄参 2026-11-22 真机：iPad13 英文系统花园右上角溢出）：
/// 「Windy」错位、「Wish Tr…」被截断。
///
/// 根因：`WishTopEntryCluster` 文字框是**固定 `maxWidth: 96`** —— 英文长词
/// 在 Ahem / 系统字号放大下自然宽 > 96 ⇒ `ellipsis` 截断；且 96 与图标宽
/// （`kWishTreeWeatherEntrySize × uiScaleOf`，834 屏 = 72.8）不同源，簇内
/// 排版观感随语言漂移。
///
/// 修复（`wish_top_entry_cluster.dart`）：文字框宽度收紧为**图标宽**
/// `kWishTreeWeatherEntrySize × uiScaleOf(context)`，内层套
/// `FittedBox(BoxFit.scaleDown)` —— 长词**整串缩放**（绝不 ellipsis 截半）、
/// 恒精确居中于图标正下方；中文短词走直通分支（未被缩放）⇒ 中文观感不变。
/// 🔴 英文文案未删一字、图标尺寸常量（`kWishTreeWeatherEntrySize` /
/// `kWishTreeWeatherEntryIconSize`）一个未动。
///
/// 本文件三层钉住（期望值独立手算）：
///  ① 真实花园页 en + iPad 834：uiScale = 1.3 ⇒ 图标宽 = 56 × 1.3 = **72.8**；
///     两簇文字框宽 ≤ 72.8、文字与图标中心对齐（≤2px）、图标↔文字 4dp、
///     零 overflow 异常；
///  ② 真实花园页 zh + 390 回归：中文短词（「许愿树」）**未被缩放**
///     （Text 自然宽 < 框宽 ⇒ FittedBox scale == 1 直通；C129 框宽改定宽后
///     判据从「渲染宽 < 56」改为「自然宽 < 56 + 框内居中」）；
///  ③ 簇单元 en + textScaler 1.3 + iPad 834：`scaleDown` 分支精确生效 ——
///     长词缩放后**恰好填满**图标宽（closeTo 72.8）且完整居中（旧实现此场景
///     必然 ellipsis 截半）。
///  ④ C129 任务 A：天气簇罩显示时文字框中心 == 图标本体中心 ≤1px（en/zh 双
///     locale），罩盒位置零改动（间距 9.1 / 垂直居中 / 在图标左侧）。
///
/// ⚠️ 花园页有无限动画：全程有界 `pump`，禁止 `pumpAndSettle`。
library garden_top_entry_locale_overflow_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/weather_banner_logic.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_top_entry_cluster.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_weather_entry.dart';
import 'package:sunflower_time/shared/responsive.dart';

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

/// 真实 DI 宿主（内存库 + 真实服务图；与 garden_top_entry_layout_test 同款）。
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

/// 切语言（L10nScope 消费 [AppLocaleController.current]，revision 触发重建）。
void _setLocale(Locale locale) {
  AppLocaleController.current = locale;
  AppLocaleController.revision.value++;
}

/// 🔴 静态单点必须复原：本文件的 locale 改写不得泄漏给同进程其他测试。
void _restoreLocaleZh() => _setLocale(const Locale('zh'));

Future<void> _frames(WidgetTester tester, {int n = 12}) async {
  for (int i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

double _iconSideOf(BuildContext context) =>
    kWishTreeWeatherEntrySize * uiScaleOf(context);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AudioService.instance.resetForTest());
  tearDown(_restoreLocaleZh);

  group('C128 ① 真实花园页 en + iPad 834：右上角文字完整、正位、零溢出', () {
    testWidgets('en + 834×1194：uiScale=1.3 ⇒ 两簇文字框 ≤ 72.8、居中、gap 4dp',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _setLocale(const Locale('en'));

      final ProviderContainer c = await _boot();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: GardenPage()),
      ));
      await _frames(tester);

      // 前置：本档 uiScale 真是 1.3（图标宽 = 56 × 1.3 = 72.8，独立手算）。
      final BuildContext ctx = tester.element(find.byType(GardenPage));
      expect(uiScaleOf(ctx), closeTo(1.3, 0.001), reason: 'iPad 834 ⇒ uiScale 1.3');
      final double iconSide = _iconSideOf(ctx);
      expect(iconSide, closeTo(72.8, 0.01), reason: '56 × 1.3 = 72.8（手算期望值）');

      final Finder entryIcon = find.byKey(kWishTreeWeatherEntryKey);
      final Finder entryLabel = find.byKey(kWishTreeWeatherEntryLabelKey);
      final Finder weatherIcon = find.byKey(kGardenWeatherBadgeIconKey);
      final Finder weatherLabel = find.byKey(kGardenWeatherLabelKey);
      expect(entryIcon, findsOneWidget);
      expect(entryLabel, findsOneWidget);
      expect(weatherIcon, findsOneWidget);
      expect(weatherLabel, findsOneWidget);

      // 🔴 文案未删一字：en ARB 独立期望值。
      final Text entryText = tester.widget<Text>(entryLabel);
      expect(entryText.data, 'Wish Tree', reason: '英文文案必须原样保留（不许删除）');

      final Rect entryIconRect = tester.getRect(entryIcon);
      // 🔴 量 FittedBox 的渲染盒而非 Text：FittedBox 的缩放是 paint transform，
      //    Text 自身 RenderBox 的 size 仍是自然宽（getRect 的 size 分量不含缩放）。
      //    FittedBox 盒 = 缩放后的真实视觉盒，且上下文唯一（每簇一个）。
      final Rect entryLabelRect = tester.getRect(
        find.ancestor(
          of: entryLabel,
          matching: find.byType(FittedBox),
        ).first,
      );
      final Rect weatherIconRect = tester.getRect(weatherIcon);
      final Rect weatherLabelRect = tester.getRect(
        find.ancestor(
          of: weatherLabel,
          matching: find.byType(FittedBox),
        ).first,
      );

      // 完整可见：文字框宽 ≤ 图标宽（FittedBox scaleDown 上限 = 图标宽）。
      // 旧实现（固定 96 框 + ellipsis）此场景必然截半「Wish Tr…」。
      expect(entryLabelRect.width, lessThanOrEqualTo(iconSide + 0.5),
          reason: '「Wish Tree」渲染宽必须收进图标宽 72.8 内（整词完整、绝不 ellipsis）');
      expect(weatherLabelRect.width, lessThanOrEqualTo(iconSide + 0.5),
          reason: 'en 天气名（如 Windy / Light rain）同样收进图标宽内，不再错位');
      expect(entryLabelRect.height, greaterThanOrEqualTo(8),
          reason: '文字必须有可见渲染高度（非零占位）');
      expect(weatherLabelRect.height, greaterThanOrEqualTo(8));

      // 正确定位：文字精确居中于图标正下方、间距 4dp（结构折叠语义不变）。
      expect((entryLabelRect.center.dx - entryIconRect.center.dx).abs(),
          lessThanOrEqualTo(2.0),
          reason: '「Wish Tree」中心 x 与图标中心 x 偏差 ≤2px（缩放后仍居中）');
      expect((weatherLabelRect.center.dx - weatherIconRect.center.dx).abs(),
          lessThanOrEqualTo(2.0),
          reason: 'en 天气名同样居中（修复前「Windy」错位）');
      expect(entryLabelRect.top - entryIconRect.bottom,
          closeTo(kGardenTopLabelGap, 2.0),
          reason: '图标↔文字间距 = 4dp（R3-P0-11② 不回归）');
      expect(weatherLabelRect.top - weatherIconRect.bottom,
          closeTo(kGardenTopLabelGap, 2.0));

      expect(tester.takeException(), isNull,
          reason: 'en + iPad 834 全页零 overflow / 零布局异常');
    });
  });

  group('C128 ② zh 回归：中文观感逐位不变', () {
    testWidgets('zh + 390×844：「许愿树」不被缩放（宽 < 图标宽 56 = 直通）、居中',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _restoreLocaleZh();

      final ProviderContainer c = await _boot();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: GardenPage()),
      ));
      await _frames(tester);

      final BuildContext ctx = tester.element(find.byType(GardenPage));
      expect(uiScaleOf(ctx), closeTo(1.0, 0.001), reason: '手机 390 ⇒ uiScale 1.0');

      final Rect entryIconRect =
          tester.getRect(find.byKey(kWishTreeWeatherEntryKey));
      final Rect entryLabelRect = tester.getRect(
        find.ancestor(
          of: find.byKey(kWishTreeWeatherEntryLabelKey),
          matching: find.byType(FittedBox),
        ).first,
      );

      expect(tester.widget<Text>(
        find.byKey(kWishTreeWeatherEntryLabelKey),
      ).data, '许愿树', reason: '中文文案不变');

      // 🔴 FittedBox 直通判据（C129 框宽改定宽 56 后的等价形式）：FittedBox
      //    scaleDown 只缩不放 —— Text 自然宽（getRect 的 size 分量 = 未变换
      //    自然宽）< 56 ⇒ scale 恒 = 1 ⇒ 视觉 = 自然（中文观感逐位不变）。
      //    「许愿树」12px 自然宽 ≈36 < 56。
      final Rect entryTextRect =
          tester.getRect(find.byKey(kWishTreeWeatherEntryLabelKey));
      expect(entryTextRect.width, lessThan(56.0),
          reason: '中文短词自然宽 < 框宽 ⇒ FittedBox scale == 1（直通、未被缩放）');
      expect(entryTextRect.width, greaterThan(20.0),
          reason: '中文标签有正常渲染宽度');
      // 定宽框（= 图标本体宽 56）与框内文字都精确居中于图标中心。
      expect((entryLabelRect.center.dx - entryIconRect.center.dx).abs(),
          lessThanOrEqualTo(2.0), reason: '中文标签仍精确居中');
      expect((entryTextRect.center.dx - entryIconRect.center.dx).abs(),
          lessThanOrEqualTo(2.0), reason: '框内文字同样居中（scale == 1 判据闭合）');
      expect(entryLabelRect.top - entryIconRect.bottom,
          closeTo(kGardenTopLabelGap, 2.0), reason: '4dp 间距不变');

      expect(tester.takeException(), isNull, reason: '中文 390 零异常');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // C129 任务 A：天气文字对齐锚 = **图标本体**（保护罩不参与）
  // ══════════════════════════════════════════════════════════════════════
  group('C129 ①天气簇：罩显示时文字中心 x == 图标本体中心 x（≤1px）', () {
    /// 罩显示夹具：badge = Row[罩72 + gap7 + 图标56]（簇宽 135×s）。
    /// 修复前：center 把文字对到 135 中心（左偏 39.5×s）；修复后 end+定宽框
    /// 恒对齐图标本体。期望值独立手算：s=1.3 ⇒ 图标 72.8 / 罩盒 93.6 /
    /// 视觉间距 7×1.3 = 9.1 / 罩盒垂直居中溢出 ±8×1.3。
    Future<void> pumpShelterCluster(
      WidgetTester tester, {
      required bool english,
    }) async {
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(834, 1194),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Localizations(
            locale: english ? const Locale('en') : const Locale('zh'),
            delegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Material(
                color: Colors.white,
                child: Center(
                  child: WishTopEntryCluster(
                    icon: const GardenWeatherBadge(
                      kind: WeatherKind.cold,
                      banner: WeatherBannerState(
                        mood: WeatherBannerMood.todo,
                        kind: WeatherKind.cold,
                        shelterRefType: kWeatherShelterRefTypeWarm,
                      ),
                      shelterBought: true,
                    ),
                    label: english ? 'Heavy rain' : '大雪',
                    labelKey: kGardenWeatherLabelKey,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _frames(tester, n: 4);
    }

    for (final (bool english, String tag) in const <(bool, String)>[
      (true, 'en'),
      (false, 'zh'),
    ]) {
      testWidgets('$tag + textScaler 1.3 + 834：文字对齐图标本体、罩位零改动',
          (WidgetTester tester) async {
        await pumpShelterCluster(tester, english: english);

        final Rect iconRect =
            tester.getRect(find.byKey(kGardenWeatherBadgeIconKey));
        final Rect shelterRect =
            tester.getRect(find.byKey(kGardenWeatherBadgeShelterKey));
        final Rect badgeRect =
            tester.getRect(find.byKey(kGardenWeatherBadgeKey));
        final Rect labelRect = tester.getRect(
          find.ancestor(
            of: find.byKey(kGardenWeatherLabelKey),
            matching: find.byType(FittedBox),
          ).first,
        );

        // 独立期望（手算，s = 1.3）：图标本体 72.8；罩盒 93.6。
        expect(badgeRect.width, closeTo(72.8, 0.01),
            reason: '图标本体 = 56 × 1.3 = 72.8');
        expect(shelterRect.width, closeTo(93.6, 0.01),
            reason: '罩盒 = 72 × 1.3 = 93.6');

        // 🔴 C129 核心判据：文字框中心 x == 图标本体中心 x（≤1px）。
        // 修复前文字对齐到 135×s 簇宽中心，左偏 (72+7)/2×1.3 = 51.35px。
        expect((labelRect.center.dx - badgeRect.center.dx).abs(),
            lessThanOrEqualTo(1.0),
            reason: '🔴 天气文字必须正对图标本体中心（保护罩不参与对齐锚）');

        // 罩位零改动（C129 硬约束）：罩盒右缘 = 图标左缘 − 视觉间距 9.1；
        // 罩盒垂直中心 == 图标垂直中心（OverflowBox ±8 溢出语义不变）。
        expect(iconRect.left - shelterRect.right, closeTo(9.1, 0.1),
            reason: '罩与图标的视觉间距 = 7 × 1.3 = 9.1（位置零改动）');
        expect(shelterRect.center.dy, closeTo(iconRect.center.dy, 0.5),
            reason: '罩盒与图标垂直居中（原 Row 语义不变）');
        // 罩在图标**左侧**（生长方向不回潮）。
        expect(shelterRect.right, lessThan(iconRect.left));

        // 文字框定宽 = 图标本体宽（C129 对齐锚的载体）。
        expect(labelRect.width, closeTo(72.8, 0.6),
            reason: '文字框定宽 = kWishTreeWeatherEntrySize × 1.3 = 72.8');
        expect(labelRect.top - iconRect.bottom,
            closeTo(kGardenTopLabelGap, 2.0), reason: '4dp 间距不变');

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('C128 ③ 簇单元：scaleDown 分支精确生效（旧实现必截半的场景）', () {
    testWidgets('en + textScaler 1.3 + iPad 834：长词整体缩放至恰好图标宽且居中',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(834, 1194),
            textScaler: TextScaler.linear(1.3),
          ),
          // 🔴 不经 MaterialApp（它会用 tester.view 重建 MediaQuery，把
          //    textScaler 覆盖回 1.0）：直接挂 Localizations + Material。
          child: Localizations(
            locale: const Locale('en'),
            delegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: Material(
                color: Colors.white,
                child: Center(
                  child: WishTopEntryCluster(
                    icon: WishTreeWeatherEntry(label: 'Wish Tree'),
                    label: 'Wish Tree',
                    labelKey: kWishTreeWeatherEntryLabelKey,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _frames(tester, n: 4);

      final Rect iconRect =
          tester.getRect(find.byKey(kWishTreeWeatherEntryKey));
      final Rect labelRect = tester.getRect(find.byType(FittedBox));
      // 独立期望：图标宽 = 56 × 1.3 = 72.8；textScaler 1.3 下长词自然宽必超框
      // ⇒ scaleDown 把整串缩到**恰好**框宽（既不截断也不留白溢出）。
      expect(iconRect.width, closeTo(72.8, 0.01));
      expect(labelRect.width, closeTo(72.8, 0.6),
          reason: '🔴 scaleDown 分支：超宽长词缩放到恰好图标宽（完整可见，'
              '旧实现固定 96 框 + ellipsis 在此场景必然渲染成「Wish Tr…」）');
      expect((labelRect.center.dx - iconRect.center.dx).abs(),
          lessThanOrEqualTo(2.0), reason: '缩放后仍精确居中于图标正下方');
      expect(labelRect.top - iconRect.bottom, closeTo(kGardenTopLabelGap, 2.0));
      expect(tester.takeException(), isNull);
    });
  });
}
