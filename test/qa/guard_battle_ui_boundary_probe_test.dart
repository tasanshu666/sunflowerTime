/// 守卫战 v2 独立验收 · **W5 UI 边界探针**。
///
/// | # | 探针 | 判据 |
/// |---|---|---|
/// | 1 | 320×568 + en + 1.3×：场景卡待机态与战斗态（怪在车道上）零 overflow、卡高恒 160 | |
/// | 2 | iPad 宽槽（1024pt 屏 / 1000pt 卡槽）：战斗坐标缩放不越界、怪不侵入卡顶信息区、怪底不压卡底倒计时细线（B7 翻转） | |
/// | 3 | absent 态零占位（差值 = 卡高 + gap 口径：171pt，一个都不进树） | |
/// | 4 | ❌ B7 已删：能量点亮数 == energyAvailable（能量点整组删除，见文件尾注释） | |
library;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

GuardTodayView _view(GuardPillMode mode, int energy) {
  return GuardTodayView(
    mode: mode,
    state: GuardDayState(
      dayKey: '2026-11-09',
      status: mode == GuardPillMode.fighting
          ? GuardDayStatus.fighting
          : GuardDayStatus.pending,
      thiefKind: GuardThiefKind.sunRat,
      winSun: 2,
    ),
    energyAvailable: energy,
    balance: 20,
  );
}

Widget _host({
  required Widget child,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  Size size = const Size(320, 568),
}) {
  return MaterialApp(
    locale: locale,
    builder: (BuildContext context, Widget? inner) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: inner!,
    ),
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
    home: Scaffold(body: Center(child: child)),
  );
}

/// 页面级夹具（absent 探针用；与工程师测试同款接线、独立实现）。
Future<ProviderContainer> _pumpTodayPage(
  WidgetTester tester, {
  required SharedPreferences sp,
  required db.AppDatabase database,
  required AccountService account,
}) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(database),
      accountServiceProvider.overrideWithValue(account),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChildTodayPage()),
    ),
  );
  for (int i = 0; i < 26; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

void main() {
  group('W5-1 320×568 + en + 1.3×：待机态与战斗态零 overflow', () {
    testWidgets('待机态（pendingFree）', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
        textScale: 1.3,
        child: SizedBox(
          width: 288,
          child: GuardSceneCard(
            view: _view(GuardPillMode.pendingFree, 2),
            dayKey: '2026-11-09',
            childId: 'qa-ui-idle',
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '🔴 待机态 en 1.3× 不得溢出');
      expect(tester.getRect(find.byKey(GuardSceneCard.cardKey)).height,
          closeTo(kGuardSceneCardHeight, 0.5), reason: '卡高恒 160');
    });

    for (final int probeAtSec in <int>[2, 15, 26]) {
      testWidgets('战斗态：怪在车道上（$probeAtSec s 采样点）',
          (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(
          textScale: 1.3,
          child: SizedBox(
            width: 288,
            child: GuardSceneCard(
              view: _view(GuardPillMode.fighting, 1),
              dayKey: '2026-11-09',
              childId: 'qa-ui-battle',
            ),
          ),
        ));
        // 挂载帧不推进 sim 时间。
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(Duration(seconds: probeAtSec));
        expect(tester.takeException(), isNull,
            reason: '🔴 战斗态 t=${probeAtSec}s en 1.3× 不得溢出');
        expect(tester.getRect(find.byKey(GuardSceneCard.cardKey)).height,
            closeTo(kGuardSceneCardHeight, 0.5));
      });
    }
  });

  group('W5-2 iPad 宽槽（1024pt 屏 / 1000pt 卡槽）', () {
    testWidgets('战斗坐标等比缩放不越界、怪不低于能量点行', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
        size: const Size(1024, 768),
        child: SizedBox(
          width: 1000,
          child: GuardSceneCard(
            view: _view(GuardPillMode.fighting, 1),
            dayKey: '2026-11-09',
            childId: 'qa-ipad',
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1));
      // 推 20s：首怪（spawn 0）走到接近门口的位置（x 最大 330 → 等比放大）。
      await tester.pump(const Duration(seconds: 20));
      expect(tester.takeException(), isNull, reason: 'iPad 宽槽不得溢出');

      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      final double dotsBottom =
          tester.getRect(find.byKey(GuardSceneCard.energyDotKey(1))).bottom;
      final List<Rect> monsters = <Rect>[
        for (int i = 0; i < 5; i++)
          if (find.byKey(GuardBattleField.monsterKey(i)).evaluate().isNotEmpty)
            tester.getRect(find.byKey(GuardBattleField.monsterKey(i))),
      ];
      expect(monsters, isNotEmpty, reason: '20s 时应有怪在车道上（或刚到门口冻结）');
      for (final Rect m in monsters) {
        expect(m.left, greaterThanOrEqualTo(card.left - 0.5),
            reason: '🔴 怪左缘 $m 不得越过卡左缘 $card');
        expect(m.right, lessThanOrEqualTo(card.right + 0.5),
            reason: '🔴 怪右缘 $m 不得越过卡右缘 $card（_mapX 越界）');
        // B8：卡顶信息区 = 能量点（y 4..22）⇒ 怪不得与之重叠（旧口径的
        // 35.5pt 安全带是 v3 卡高 160 时的经验值，v4 卡高 108 后以能量点
        // 的实际下缘为准，更严格也更语义化）。
        expect(m.top, greaterThanOrEqualTo(dotsBottom - 0.5),
            reason: '🔴 怪顶 $m 不得侵入能量点区（dot.bottom=$dotsBottom）');
        expect(m.bottom, lessThanOrEqualTo(card.bottom + 0.5),
            reason: '🔴 怪底不得越出卡底');
      }
      // 🔴 B7：倒计时从「顶部条」搬到**卡底细线**（4pt）⇒ 不变量方向翻转：
      // 怪必须整体待在细线**之上**（旧口径是「怪顶不得高于顶部条底」）。
      final Rect countdown = tester.getRect(find.byKey(GuardSceneCard.countdownKey));
      for (final Rect m in monsters) {
        expect(m.bottom, lessThanOrEqualTo(countdown.top + 0.5),
            reason: '🔴 怪底 ${m.bottom} 不得压到卡底倒计时细线 ${countdown.top}');
      }
    });
  });

  group('W5-3 absent 态零占位', () {
    testWidgets('全园无存活株 ⇒ 今日页不渲染场景卡（150pt 差值一个不占）',
        (WidgetTester tester) async {
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
      await _pumpTodayPage(tester, sp: sp, database: database, account: account);
      expect(find.byKey(GuardSceneCard.cardKey), findsNothing,
          reason: '🔴 absent ⇒ 场景卡整个 widget 不进树（零占位 = 卡高 160 + gap 10（171pt））');
      expect(tester.takeException(), isNull, reason: 'absent 链路不得抛错');
    });
  });

  // ── W5-4（❌ B7 已删）─────────────────────────────────────────────────────
  //
  // 原探针：`能量点渲染值 == energyAvailable`（0/1/2 三态逐态核对点亮数）。
  // **删除理由**：B7 玄参裁定「卡内减法」—— 左上两个能量点连同点按气泡 C
  // 整组删除（真机截图：两个空圈占掉了上半张卡），卡面已**零文本零控件**；
  // 被测对象不在树里，探针没有可断言的载体（不是把阈值放宽）。
  // 能量语义本身仍在 `GuardTodayView.energyAvailable` 上，由领域层
  // `guard_today_state` / `guard_service` 的既有单测覆盖。
}
