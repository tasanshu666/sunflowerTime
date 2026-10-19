/// F127（2026-10-20）：**孩子端外壳在小屏 + 大字号下横向溢出**的回归守卫。
///
/// ## 缺陷现象（修复前，探针实测）
/// 视口 320×568 逻辑像素、`textScaler: 1.3`、孩子端外壳、库里 1 个任务 + 1 条打卡：
/// ```
/// A RenderFlex overflowed by 14 pixels on the right.
/// ```
/// 定位到 **`child_today_page.dart` 的 `_StatCard` 内那条「主数值 + 次要单位」
/// 基线 Row**（第 628 行起）：可用宽 198pt，
/// `今日专注` 卡的 `Row` 内容 = 值 `0 分钟`（119.6）+ 间距 6 + 单位 `· 0 次`（84.5）
/// = **210.1pt → 溢出 14px**。
/// 「今日成长」卡在全完成态更宽：`1 / 1`（149.5）+ 6 + `全部完成 🌻`（101.4）= 256.9。
/// 同尺寸 1.0 倍字号下不溢出（内容 ~162pt），360/375 宽 + 1.3 倍也不溢出 ——
/// 该 Row 自始至终**没有任何弹性**，只是宽屏下恰好装得下，属潜在缺陷。
///
/// ## 修法（为什么不是压字）
/// 大字号是无障碍需求，绝不可以用 `FittedBox` / `AutoSizeText` / 改 fontSize 去
/// 对抗用户设置。这里做**结构性修复**：给该 Row 的两个文本各自套 `Flexible`
/// 并允许单行省略 —— 空间不够时收缩，而不是撑破父级。
///
/// ## 断言口径（为什么 1.0x 对照组必须存在）
/// 若探针/测试脚手架本身失效（例如 `textScaler` 没真正注入到路由，或视口没设对），
/// 用例① 会「假绿」。故 ② 在**同尺寸、同数据、只改成 1.0 倍字号**下也断言无异常，
/// 二者组合才说明测量链是通的；③ 再断言关键文案仍在树里、渲染盒非零且在屏内，
/// 防「靠隐藏/删掉内容」过关。
///
/// ⚠️ `textScaler` 必须从 `MaterialApp.builder` 注入（F126 探针踩过的坑）：
/// 包在 `home` 上的 MediaQuery 覆盖不到 Dialog 路由 / 覆盖层，量到的约束与线上不一致。
library shell_narrow_large_text_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';

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
/// 最宽的分支（值 `1 / 1` + 单位 `全部完成 🌻`），而不是空态。
///
/// ⚠️ 用 pending 而非 verified：`verified` 会触发外壳的金色确认卡（另一条链），
/// 与本用例要量的布局无关，且弹层会换掉被测的渲染树。
CheckIn _todayPendingCheckIn(String id, String taskId) {
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

/// 种一株向日葵（避免花园页/我的页走空态分支）。
Future<void> _seedPlant(db.AppDatabase database, AccountService account) async {
  final DateTime now = DateTime.now();
  await PlantLocalRepository(database, account: account).savePlant(
    Plant(
      id: 'plant_f127',
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

/// 挂载孩子端外壳：320×568 逻辑像素 + 指定字号倍率。
///
/// 固定次数 `pump`（不用 `pumpAndSettle`）：今日页阳光气泡是 12s 无限循环动画，
/// `pumpAndSettle` 会永不返回（`child_shell_page.dart` 的 `_tabs` 注释同因）。
Future<void> _pumpShellAt320x568(
  WidgetTester tester, {
  required SharedPreferences sp,
  required db.AppDatabase database,
  required AccountService account,
  required double textScale,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
        ],
      ),
      child: MaterialApp(
        // 🔴 textScaler 只能从这里注入（见文件头注释）。
        builder: (BuildContext ctx, Widget? child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const ChildShellPage(),
      ),
    ),
  );
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 建库 + 造数据 + 挂外壳，返回外壳挂载后的状态。
Future<AccountService> _pumpWithData(
  WidgetTester tester, {
  required double textScale,
}) async {
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

  final TaskLocalRepository tasks =
      TaskLocalRepository(database, account: account);
  await tasks.saveTask(_dailyTask('t_read', '朗读英语'));
  await tasks.checkIn(_todayPendingCheckIn('c_read', 't_read'));
  await _seedPlant(database, account);

  await _pumpShellAt320x568(
    tester,
    sp: sp,
    database: database,
    account: account,
    textScale: textScale,
  );
  return account;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('① 320×568 + textScaler 1.3 + 有数据的孩子端外壳 → 不出现 RenderFlex 溢出',
      (WidgetTester tester) async {
    await _pumpWithData(tester, textScale: 1.3);

    // RenderFlex overflow 以 FlutterError 形式进入 takeException —— 修复前这里
    // 拿到 "A RenderFlex overflowed by 14 pixels on the right."（真实红）。
    expect(tester.takeException(), isNull,
        reason: '320×568 + 1.3 倍字号下外壳不得出现任何横向溢出（F127）');
  });

  testWidgets('② 对照组：同尺寸同数据的 1.0 倍字号 → 不溢出（证明测量链有效，防假绿）',
      (WidgetTester tester) async {
    await _pumpWithData(tester, textScale: 1.0);

    expect(tester.takeException(), isNull,
        reason: '正常字号下本就不该溢出；此用例同时证明 320×568 视口已生效');
  });

  testWidgets('③ 大字号下关键文案仍在：三张状态卡 + 主按钮 + 主数值渲染盒非零且在屏内',
      (WidgetTester tester) async {
    await _pumpWithData(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);

    // 1) 三张状态卡的标签仍在（没有被整体隐藏 / 挪走）。
    expect(find.text('今日获取阳光'), findsOneWidget);
    expect(find.text('今日专注'), findsOneWidget);

    // 2) 主数值与单位文案仍在树里且没被压成零宽（1.3 倍字号下值 + 单位必须让位收缩
    //    而不是撑破父级；`Flexible` 收缩后文本**数据**不变，故此处找得到）。
    expect(find.text('0 分钟'), findsOneWidget, reason: '今日专注主数值不得被删/隐藏');
    expect(find.text('· 0 次'), findsOneWidget, reason: '单位不得被删/隐藏');

    final Rect valueRect = tester.getRect(find.text('0 分钟'));
    expect(valueRect.width, greaterThan(0), reason: '主数值不得被压成零宽');
    expect(valueRect.left, greaterThanOrEqualTo(0));
    expect(valueRect.right, lessThanOrEqualTo(320.0 + 0.5),
        reason: '主数值右缘必须留在屏内');

    // 3) 第三张卡（「今日成长」全完成态 = 最宽内容：`1 / 1` + `全部完成 🌻`）在
    //    1.3 倍字号下落到首屏之外 → 滚进视野后再量一次，确保最宽那张卡也不溢出。
    final Finder todayList = find.descendant(
      of: find.byType(ChildTodayPage),
      matching: find.byType(ListView),
    );
    expect(todayList, findsOneWidget, reason: '今日页必须有一条可滚动的状态卡列表');
    for (int i = 0; i < 4; i++) {
      if (find.text('今日成长').evaluate().isNotEmpty) break;
      await tester.drag(todayList, const Offset(0, -80));
      await tester.pump();
    }
    expect(find.text('今日成长'), findsOneWidget,
        reason: '大字号下滚动后第三张卡必须可见（内容不得被整体裁掉）');
    expect(find.text('全部完成 🌻'), findsOneWidget,
        reason: '最宽的单位文案不得被删/隐藏');
    expect(find.text('1 / 1'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '滚动到最宽的那张卡后仍不得出现溢出');

    // 4) 钉底主按钮仍在（页面主操作没有被挤掉）。
    expect(find.text('开始专注'), findsOneWidget);
  });
}
