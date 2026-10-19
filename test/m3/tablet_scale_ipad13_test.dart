/// F129（2026-10-19 玄参 iPad Pro 13″ 实测）：**平板放大倍率随屏短边派生**的回归守卫。
///
/// ## 缺陷现象
/// `iPad Pro 11″（834×1194）` 上「1.3 倍」字号正常，`iPad Pro 13″（1032×1376）` 上
/// 「字体和内容都很小」。根因：原 `uiScaleOf` / `tabletTextScaler` 的平板分支返回
/// **固定常量 1.3**，判据只按 `shortestSide >= 600` 二分 —— 两台 iPad 拿到相同的
/// **绝对**字号，13″ 物理屏更大，视觉上就更小。
///
/// ## 修法
/// 倍率改为 `tabletUiScaleFor(shortestSide)`：以
/// [kTabletUiScaleBaseShortestSide]（834 = iPad 11″，倍率恰 1.3，**零回归**）为锚点
/// 线性外推，`max(1.3, …)` 只放不缩、`min(…, kTabletTextScaleMax)` 封顶 1.6。
/// 玄参红线：「任何尺寸的平板都自动按比例放大，不能换一台平板就重新配置一次」。
///
/// ## 本文件锁三件事
///  ① 1032×1376 真实注入 `applyTabletTextScaling` → `textScaler.scale(1.0) == 1.6`；
///  ② **同视口挂真实 `ChildShellPage`**，5 个 tab（含「今日」「我的」）逐页
///     `takeException()` 全为 null —— 1.3 → 1.6 是 +23%，必须证明没撑破既有布局；
///  ③ 834×1194 对照仍有 1.3（iPad 11″ 零回归）。
///
/// ⚠️ 全程禁用 `pumpAndSettle`：花园页木牌呼吸 / 今日页阳光气泡是无限动画，
/// `pumpAndSettle` 会永不返回（同 `child_shell_page.dart` 的 `_tabs` 注释）。
/// ⚠️ `textScaler` 只能从 `MaterialApp.builder` 注入（F126/F127 探针踩过的坑）：
/// 包在 `home` 上的 MediaQuery 覆盖不到 Dialog 路由与覆盖层。
library tablet_scale_ipad13_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// iPad Pro 13″（M5）竖屏逻辑尺寸 —— 本次缺陷的实测机型。
const Size _kIpad13 = Size(1032, 1376);

/// iPad Pro 11″ 竖屏逻辑尺寸 —— 已被玄参确认为「1.3 倍正常」的锚点机型。
const Size _kIpad11 = Size(834, 1194);

/// 一个「今日必做」成长项（`repeatRule == null` ⇒ isDaily）。
Task _dailyTask(String id, String name) => Task(
      id: id,
      name: name,
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 15,
      sunlightReward: 12,
      isCustom: true,
    );

/// 今天**已提交（待家长核销）**的打卡 —— 让「今日成长」卡走「全部完成」这条
/// 最宽的分支，而不是空态（空态会掩盖最宽内容的溢出风险）。
///
/// ⚠️ 用 pending 而非 verified：`verified` 会触发外壳的金色确认卡，弹层会换掉
/// 被测渲染树，与布局断言无关（同 `shell_narrow_large_text_test` 口径）。
CheckIn _pendingCheckIn(String id, String taskId) {
  final DateTime now = DateTime.now();
  return CheckIn(
    id: id,
    taskId: taskId,
    date: now,
    completedAt: now.subtract(const Duration(minutes: 5)),
    isPerfectDay: false,
    status: CheckInStatus.pending,
    sunlightGross: 12,
    sunlightGranted: 0,
  );
}

/// 种一株向日葵（避免花园页 / 我的页走空态分支）。
Future<void> _seedPlant(db.AppDatabase database, AccountService account) async {
  final DateTime now = DateTime.now();
  await PlantLocalRepository(database, account: account).savePlant(
    Plant(
      id: 'plant_f129',
      speciesId: 'sunflower',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: now,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
    ),
  );
}

/// 「app.dart 同款注入壳」：调用的正是唯一注入点 [applyTabletTextScaling]。
///
/// 不自己写死 1.6 —— 让真实链路（视口 → MediaQueryData → 注入点 → 倍率）跑通，
/// 否则测的只是「我在测试里写了个 1.6」。
Widget _injectedApp(Widget home, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (BuildContext ctx, Widget? child) {
          final Widget content = child ?? const SizedBox.shrink();
          final MediaQueryData mq =
              MediaQuery.maybeOf(ctx) ?? const MediaQueryData();
          final MediaQueryData scaled = applyTabletTextScaling(mq);
          if (identical(scaled, mq)) return content; // 手机：不引入 MediaQuery
          return MediaQuery(data: scaled, child: content);
        },
        home: home,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late db.AppDatabase database;

  /// 建库 + 造数据 + 设视口（逻辑尺寸 [size]），返回可直接挂载的容器。
  Future<void> boot(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();

    final TaskLocalRepository tasks =
        TaskLocalRepository(database, account: account);
    await tasks.saveTask(_dailyTask('t_read', '朗读英语'));
    // 第二条任务：让「成长」tab 有非空列表（空列表不参与宽度压力）。
    await tasks.saveTask(_dailyTask('t_math', '数学口算练习十道题'));
    await tasks.checkIn(_pendingCheckIn('c_read', 't_read'));
    await _seedPlant(database, account);

    container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(database),
        accountServiceProvider.overrideWithValue(account),
      ],
    );
    addTearDown(container.dispose);
  }

  /// 有界 pump（见文件头「禁用 pumpAndSettle」）。
  Future<void> pumpFrames(WidgetTester tester, {int frames = 12}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 抽干本帧期间的**全部**异常（`takeException` 一次只取一条）。
  ///
  /// RenderFlex overflow 以 `FlutterError` 形式进入这里；有多处溢出时若不抽干，
  /// 只有第一条会被看到，其余会在测试收尾时冒成「unexpected exception」。
  List<Object> drainExceptions(WidgetTester tester) {
    final List<Object> all = <Object>[];
    for (int i = 0; i < 20; i++) {
      final Object? e = tester.takeException();
      if (e == null) break;
      all.add(e);
    }
    return all;
  }

  group('F129 ① 倍率真值：随屏短边派生（锚点 834 = 1.3，上限 1.6）', () {
    test('1032（iPad Pro 13″）→ 1.6', () {
      expect(tabletUiScaleFor(_kIpad13.shortestSide), kTabletTextScaleMax,
          reason: '本次缺陷机型：外推 1.609 被钳到 1.6（+23%）');
    });

    test('834（iPad Pro 11″）→ 1.3（**零回归**）', () {
      expect(tabletUiScaleFor(_kIpad11.shortestSide), kTabletUiScale,
          reason: '锚点屏：必须逐位等于修前的 1.3，否则 iPad 11″ 会变样');
    });

    testWidgets('1032×1376 + 真实注入 → textScaler.scale(1.0) == 1.6',
        (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(_injectedApp(const ChildShellPage(), container));
      await pumpFrames(tester);

      final double s = MediaQuery.textScalerOf(
        tester.element(find.byType(ChildShellPage)),
      ).scale(1.0);
      expect(s, kTabletTextScaleMax,
          reason: 'iPad 13″ 上 device=1.0 时必须得到 1.6（修前是 1.3）');
      expect(drainExceptions(tester), isEmpty);
    });

    testWidgets('834×1194 + 真实注入 → 仍 1.3（iPad 11″ 零回归）',
        (WidgetTester tester) async {
      await boot(tester, _kIpad11);
      await tester.pumpWidget(_injectedApp(const ChildShellPage(), container));
      await pumpFrames(tester);

      final double s = MediaQuery.textScalerOf(
        tester.element(find.byType(ChildShellPage)),
      ).scale(1.0);
      expect(s, kTabletUiScale, reason: '锚点机型不得因本次改动变化');
      expect(drainExceptions(tester), isEmpty);
    });
  });

  group('F129 ② iPad 13″ 逐页溢出扫描（1.3 → 1.6 撑破布局的防线）', () {
    testWidgets('孩子端 5 个 tab：逐页切过去、逐页零异常', (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(_injectedApp(const ChildShellPage(), container));
      await pumpFrames(tester);
      expect(drainExceptions(tester), isEmpty, reason: '「今日」页（首屏）不得溢出');

      const List<String> labels = <String>['今日', '成长', '花园', '商店', '我的'];
      for (int i = 1; i < labels.length; i++) {
        await tester.tap(find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(labels[i]),
        ));
        await pumpFrames(tester);
        // 证明 tab **真的切过去了**（否则「零异常」可能只是没渲染新页）。
        expect(container.read(childShellTabIndexProvider), i,
            reason: '点击「${labels[i]}」后 tab 索引应为 $i');
        expect(drainExceptions(tester), isEmpty,
            reason: 'iPad 13″（1.6 倍字号）下「${labels[i]}」页不得溢出');
      }
    });

    testWidgets('「今日」与「我的」两页关键内容仍在、渲染盒非零（防「靠隐藏过关」）',
        (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(_injectedApp(const ChildShellPage(), container));
      await pumpFrames(tester);

      // 「今日」tab：三张状态卡的标签 + 主按钮。
      expect(find.byType(ChildTodayPage), findsOneWidget);
      expect(find.text('今日获取阳光'), findsOneWidget);
      expect(find.text('开始专注'), findsOneWidget);
      final Rect btn = tester.getRect(find.text('开始专注'));
      expect(btn.width, greaterThan(0), reason: '主按钮不得被压成零宽');
      expect(btn.right, lessThanOrEqualTo(_kIpad13.width + 0.5),
          reason: '主按钮必须留在屏内');

      // 「我的」tab：切过去后确认页面本体在树里且渲染盒非零。
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('我的'),
      ));
      await pumpFrames(tester);
      expect(find.byType(ChildProfilePage), findsOneWidget);
      expect(
        tester.getSize(find.byType(ChildProfilePage)).width,
        greaterThan(0),
        reason: '「我的」页必须真实渲染（非零宽），不是被藏起来',
      );
      expect(drainExceptions(tester), isEmpty,
          reason: '「我的」页在 iPad 13″ + 1.6 倍字号下不得溢出');
    });
  });
}
