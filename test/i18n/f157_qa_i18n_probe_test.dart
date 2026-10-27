/// F157-BUG-2 + A2（4 处 i18n 漏网）· **QA 独立验收探针**（严过关，2026-10-27）。
///
/// 与工程师自测的分工：工程师的用例主要断言「我改的那行生效」；本文件全部走
/// **真实页面 / 真实弹窗入口**，逐条核对玄参真机看到的四处，并对 en / zh 做
/// **双向**断言（en 必须是英文、zh 必须逐字回到原文）：
///
/// | # | 位置 | en | zh |
/// |---|------|----|----|
/// | ① | 家长赠予到账卡按钮（真 `ChildShellPage` + 真 drift 账本） | `Got it` | 「知道啦」 |
/// | ② | 完美日庆祝卡三句（真 `ChildTaskPage`，点「我做」触发） | 全英 | 三句逐字 |
/// | ③ | 家长入口 tooltip（真 `ParentEntryAction`） | `Parent Hub` | 「家长天地」 |
/// | ④ | 确认卡「取消」（真 `showPlantConfirmDialog` 生产入口） | `Cancel` | 「取消」 |
///
/// 另加两条**纪律守卫**（原为一条，2026-10-27 终验按事实更正）：
///  · 纪律①：**裸宿主**下弹窗内解析落到 zh 兜底；
///  · 纪律②：**生产同构壳**（`MaterialApp` 带 locale + delegates）下弹窗内解析
///    拿的是 **app 壳**语言、而不是页面语言 —— 两条链独立。
/// 合起来才准确：兜底「不等于页面语言」，且「≠ 恒中文」。两者都说明同一件事 ——
/// 文案必须由调用方在页级 scope 内解析后显式传入，兜底只能当「不崩」的保险。
///
/// ⚠️ 外壳 / 任务页均有无限动画 → 全程有界 `pump`，禁 `pumpAndSettle`。
library f157_qa_i18n_probe_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/parent_entry_action.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_confirm_dialog.dart';

// ───────────────────────────── 文案常量（钉死字面量） ─────────────────────────────

const String kZhGotIt = '知道啦';
const String kEnGotIt = 'Got it';
const String kZhParentHub = '家长天地';
const String kEnParentHub = 'Parent Hub';
const String kZhCancel = '取消';
const String kEnCancel = 'Cancel';
const String kZhPerfectTitle = '🌻 今日成长项全部完成！';
const String kZhPerfectFooter = '你今天把全部成长项都做完啦，获得「完美日」标记！';
const String kZhPerfectOk = '太棒啦';
const String kEnPerfectTitle = '🌻 All growth tasks done today!';
const String kEnPerfectOk = 'Awesome!';

// ───────────────────────────── 通用 fake ─────────────────────────────

class _FakeFocusRepository implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

/// 只记录 append 的账本（完美日打卡链用；不触真库）。
class _FakeSunlightRepository implements SunlightRepository {
  final List<SunlightEntry> appended = <SunlightEntry>[];
  @override
  Future<double> append(SunlightEntry entry) async {
    appended.add(entry);
    return 999.0;
  }

  @override
  Future<double> balance() async => 999.0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
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
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(appended);
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.high,
        dailyFocusCap: 60,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 400,
        eyeCareSkipAllowed: true,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

/// 内存任务仓储（1 条非联动任务，打完即「完美日」）。
class _MemTaskRepository implements TaskRepository {
  _MemTaskRepository(this._tasks);
  final List<Task> _tasks;
  final List<CheckIn> checkIns = <CheckIn>[];

  @override
  Future<List<Task>> tasks() async => List<Task>.of(_tasks);
  @override
  Future<void> saveTask(Task task) async {}
  @override
  Future<void> deleteTaskById(String id) async {}
  @override
  Future<void> checkIn(CheckIn c) async => checkIns.add(c);
  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => checkIns
      .where((CheckIn c) =>
          '${c.date.year}-${c.date.month.toString().padLeft(2, '0')}-'
          '${c.date.day.toString().padLeft(2, '0')}' ==
          dayKey)
      .toList();
  @override
  Future<int> totalCheckInCount() async => checkIns.length;
}

// ───────────────────────────── 宿主 ─────────────────────────────

/// 有界帧推进。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 14}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 真 `ChildShellPage`（内存 Drift + mock SP + 真 `AccountService`），
/// 预热时往**真阳光账本**写一条 `parent_gift` 记录 → 走生产同一条赠予卡链路。
Future<void> _pumpShellWithParentGift(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
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
    ],
  );
  addTearDown(container.dispose);

  // 家长赠予（真仓储落库；id 决定「未读」判定，每用例独立 DB 天然未读）。
  final double before =
      await container.read(sunlightRepositoryProvider).balance();
  await container.read(sunlightRepositoryProvider).append(
        SunlightEntry(
          id: 'gift-${DateTime.now().microsecondsSinceEpoch}',
          ts: DateTime.now(),
          type: SunlightType.earn,
          gross: 12,
          net: 12,
          balanceAfter: before + 12,
          refType: 'parent_gift',
          refId: null,
          dayKey: '2026-10-27',
        ),
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChildShellPage()),
    ),
  );
  await _pumpFrames(tester);
}

/// 真 `ChildTaskPage`（1 条任务），点「我做」触发完美日庆祝卡。
Future<void> _pumpTaskPageAndFinishAll(WidgetTester tester) async {
  const Task only = Task(
    id: 't_only',
    name: 'Water the plant', // 数据不是文案，随便给
    subject: TaskSubject.general,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 12,
    isCustom: false,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        taskCheckInServiceProvider.overrideWithValue(TaskCheckInService(
          tasks: _MemTaskRepository(<Task>[only]),
          ledger: _FakeSunlightRepository(),
          focus: _FakeFocusRepository(),
          settings: _FakeSettingsRepository(),
        )),
      ],
      child: const MaterialApp(home: Scaffold(body: ChildTaskPage())),
    ),
  );
  await _pumpFrames(tester, frames: 12);
}

/// `MaterialApp` → 页级 `L10nScope` → `Builder`（生产同构）。
Widget _pageHost(Widget Function(BuildContext ctx) builder) => MaterialApp(
      home: L10nScope(
        child: Builder(
          builder: (BuildContext ctx) => Scaffold(body: builder(ctx)),
        ),
      ),
    );

void _useLocale(AppLanguage lang) {
  AppLocaleController.init(lang);
  addTearDown(() => AppLocaleController.init(AppLanguage.system));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────── ① 家长赠予到账卡按钮（BUG-2 本体，真外壳 + 真账本） ───────────
  group('① 家长赠予到账卡 · 按钮文案', () {
    testWidgets('en：`Got it`，且界面里不许再出现「知道啦」',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.en);
      await _pumpShellWithParentGift(tester);

      expect(find.byType(GoldNoticeDialog), findsOneWidget,
          reason: '未读的家长赠予必须弹金色通知卡（否则本用例没测到东西）');
      expect(find.text(kEnGotIt), findsOneWidget,
          reason: '🔴 BUG-2：英文界面按钮必须是 `Got it`');
      expect(find.text(kZhGotIt), findsNothing,
          reason: '🔴 英文界面绝不能出现硬编码中文「知道啦」');
    });

    testWidgets('zh：按钮仍是「知道啦」（逐字零回归）', (WidgetTester tester) async {
      _useLocale(AppLanguage.zh);
      await _pumpShellWithParentGift(tester);

      expect(find.byType(GoldNoticeDialog), findsOneWidget);
      expect(find.text(kZhGotIt), findsOneWidget,
          reason: 'zh 必须逐字「知道啦」（既有十余条断言依赖它）');
      expect(find.text(kEnGotIt), findsNothing, reason: '中文界面不该串英文');
    });
  });

  // ─────────── ② 完美日庆祝卡三句（真任务页真入口） ───────────
  group('② 完美日庆祝卡 · 三句文案', () {
    testWidgets('en：三句全英（含 emoji 与按钮），一句中文都不许漏',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.en);
      await _pumpTaskPageAndFinishAll(tester);
      // 唯一任务 → 打卡按钮（en = `I did`，zh =「我做」）。
      await tester.tap(find.text('I did'));
      await _pumpFrames(tester, frames: 12);

      expect(find.byType(GoldNoticeDialog), findsOneWidget,
          reason: '打完当日最后一条 → 完美日庆祝卡在场');
      expect(find.text(kEnPerfectTitle), findsOneWidget, reason: 'en 标题');
      expect(find.textContaining('earned a "Perfect Day" badge'), findsOneWidget,
          reason: 'en 正文');
      expect(find.text(kEnPerfectOk), findsOneWidget, reason: 'en 按钮');
      expect(find.text(kZhPerfectTitle), findsNothing,
          reason: '英文界面出现中文标题 = 迁 ARB 没生效');
      expect(find.text(kZhPerfectFooter), findsNothing);
      expect(find.text(kZhPerfectOk), findsNothing);
    });

    testWidgets('zh：三句逐字不变（含 emoji 与「」标点）',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.zh);
      await _pumpTaskPageAndFinishAll(tester);
      await tester.tap(find.text('我做'));
      await _pumpFrames(tester, frames: 12);

      expect(find.byType(GoldNoticeDialog), findsOneWidget);
      expect(find.text(kZhPerfectTitle), findsOneWidget, reason: 'zh 标题逐字');
      expect(find.text(kZhPerfectFooter), findsOneWidget, reason: 'zh 正文逐字');
      expect(find.text(kZhPerfectOk), findsOneWidget, reason: 'zh 按钮逐字');
    });
  });

  // ─────────── ③ 家长入口 tooltip（A2 第 1 处） ───────────
  group('③ 家长入口 tooltip', () {
    testWidgets('en → Parent Hub / zh → 家长天地（同一棵子树内切换）',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.en);
      await tester.pumpWidget(
        _pageHost((_) => const Center(child: ParentEntryAction(immersive: true))),
      );
      expect(
        tester.widget<IconButton>(find.byKey(ParentEntryAction.iconKey)).tooltip,
        kEnParentHub,
        reason: '英文界面 tooltip 必须英文（长按上屏 + 无障碍朗读）',
      );

      _useLocale(AppLanguage.zh);
      await tester.pump();
      expect(
        tester.widget<IconButton>(find.byKey(ParentEntryAction.iconKey)).tooltip,
        kZhParentHub,
        reason: 'zh 必须逐字「家长天地」',
      );
    });
  });

  // ─────────── ④ 确认卡「取消」（A2 第 3/4 处，走生产入口） ───────────
  group('④ 确认卡取消按钮', () {
    Widget host() => _pageHost((BuildContext ctx) {
          return Center(
            child: TextButton(
              onPressed: () => showPlantConfirmDialog(
                context: ctx,
                species: const PlantSpecies(
                  id: 'species_sunflower',
                  name: 'Sunflower',
                  rarity: Rarity.common,
                  baseCostHigh: 40,
                  baseCostLow: 20,
                  growthHoursPerStage: 240,
                ),
                rows: const <PlantConfirmRow>[],
                title: 'Plant this seed?',
                confirmLabel: 'Plant now',
                // 刻意**不传** cancelLabel：正是「调用方忘传」的最坏情形。
              ),
              child: const Text('open'),
            ),
          );
        });

    testWidgets('en：不传 cancelLabel → `Cancel`（不是「取消」）',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.en);
      await tester.pumpWidget(host());
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text(kEnCancel), findsOneWidget,
          reason: '🔴 英文界面取消按钮必须是 `Cancel`');
      expect(find.text(kZhCancel), findsNothing,
          reason: '🔴 硬编码「取消」已退役 —— 英文界面不许再出现');
      expect(find.text('Plant now'), findsOneWidget, reason: '确认按钮按传入值渲染');
    });

    testWidgets('zh：不传 cancelLabel → 「取消」逐字不变',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.zh);
      await tester.pumpWidget(host());
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text(kZhCancel), findsOneWidget,
          reason: 'zh 兜底 = shared_cancel =「取消」，与改前逐字相同');
      expect(find.text(kEnCancel), findsNothing);
    });
  });

  // ─────────── 纪律守卫：弹窗 builder 上下文拿不到「页级」语言 ───────────
  //
  // ⚠️ 2026-10-27 终验更正（工程师指出、我复核后确认他对）：
  // 我上一轮写的是「弹窗里 l10nOf 恒返回 zh」——**这句话只对裸测试宿主成立**。
  // 生产 `lib/app.dart` 是 `MaterialApp.router(locale: AppLocaleController.localeFor(lang),
  // localizationsDelegates: AppLocalizations.localizationsDelegates)`，弹窗的 context
  // 有 app 层 `Localizations` 祖先 → 拿到的是**app 壳语言**，不是中文。
  //
  // 所以准确表述是两句：
  //  ① 弹窗 context **不在页级 L10nScope 之下** → 拿不到「页面」语言（这条不变）；
  //  ② 兜底实际落到「app 壳」那条链（裸宿主 = zh）→ 与页级链是**两条独立链路**
  //     （F154「切语言部分界面不切」正是它俩漂移）→ **不能依赖**，但 ≠「恒中文」。
  // 下面两个用例把这两条分别钉住。
  testWidgets('纪律①（裸宿主）：弹窗内解析落到 zh 兜底 —— 所以必须显式传',
      (WidgetTester tester) async {
    _useLocale(AppLanguage.en);
    await tester.pumpWidget(_pageHost((BuildContext ctx) {
      return Center(
        child: TextButton(
          onPressed: () => showGoldNoticeDialog(
            ctx,
            title: 'x',
            items: const <GoldNoticeItem>[],
            confirmLabel: kEnGotIt, // 显式传 → 渲染不受下面这条事实影响
          ),
          child: const Text('open'),
        ),
      );
    }));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final BuildContext dialogCtx = tester.element(find.text(kEnGotIt));
    expect(
      l10nOf(dialogCtx).localeName,
      startsWith('zh'),
      reason: '裸宿主（MaterialApp 无 locale / 无 delegates）里，弹窗内的 `l10nOf` '
          '回落 `AppLocalizationsZh` → 兜底等同中文。这就是「调用方必须显式传」'
          '在测试与任何无壳宿主下的理由。',
    );
  });

  testWidgets('纪律②（生产同构壳）：兜底拿的是 **app 壳**语言，不是页面语言 —— '
      '两条链独立、不可依赖', (WidgetTester tester) async {
    // 页面语言 zh（L10nScope 跟 AppLocaleController），app 壳语言 en。
    _useLocale(AppLanguage.zh);
    String? pageLocale;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: L10nScope(
          child: Builder(
            builder: (BuildContext ctx) {
              pageLocale = l10nOf(ctx).localeName;
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showGoldNoticeDialog(
                      ctx,
                      title: 'x',
                      items: const <GoldNoticeItem>[],
                      confirmLabel: kEnGotIt,
                    ),
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final BuildContext dialogCtx = tester.element(find.text(kEnGotIt));
    expect(pageLocale, startsWith('zh'),
        reason: '前置：页级 L10nScope 用的是 AppLocaleController.current = zh');
    expect(
      l10nOf(dialogCtx).localeName,
      startsWith('en'),
      reason: '🔴 生产同构壳下弹窗内解析拿到的是 **app 壳** locale（en），'
          '不是页面语言（zh）→ 证明「弹窗兜底 ≠ 恒中文」，同时也证明它'
          '**不等于页面语言**：两条链一旦漂移（F154 前科）兜底就是错的。'
          '→ 结论不变：文案必须由调用方在页级 scope 内解析后显式传入。',
    );
  });
}
