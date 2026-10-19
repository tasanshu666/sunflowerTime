/// F130（2026-10-19 玄参 iPad Pro 13″ 实测截图）：**定尺寸元素随平板倍率放大**的
/// 回归守卫。
///
/// ## 缺陷现象（真机截图）
/// 上一轮 F129 把平板倍率从固定 1.3 改为「随屏短边派生」（iPad 11″ = 1.3、
/// **iPad 13″ = 1.6**），文字经 `MediaQuery.textScaler` 全局放大。但若卡片里的
/// 图标 / 方块 / 圆角 / 间距仍是**写死常量**，1.6 倍下就表现为：
///  1. 家长端「奖励」页价格胶囊里**阳光图标明显偏小**（数字 22.4pt，图标仍 16pt）；
///  2. 孩子端「商店」页兑换按钮**横向溢出**（真机两条
///     `RIGHT OVERFLOWED BY 2.5 / 4.5 PIXELS`）——按钮是死宽 64，
///     里面「数字 + 图标」被 textScaler 放大后比 64 宽。
///
/// ## 修法（本文件守卫它）
///  · `responsive.dart` 铁律：文字走 textScaler，**文字之外的定尺寸元素一律乘
///    `uiScaleOf(context)`**，两者同源同值才等比；
///  · 兑换按钮由 `SizedBox(64×64)` 改为 `ConstrainedBox(minWidth/minHeight 64*s)`——
///    宽度随内容自然增长（任意位数价格都不溢出），高度保底 64*s；
///  · **禁止** FittedBox / AutoSizeText / 缩小字号来压字（大字号是无障碍需求）。
///
/// ## 三条断言口径
///  ① `takeException()` 全空（无 RenderFlex overflow）；
///  ② 阳光图标**渲染宽** ≈ `基准 × 倍率`（17→27.2 / 16→25.6），用 `tester.getSize`
///    实测而非读 widget 属性 —— 证明它真的画成了那么宽；
///  ③ 最宽的「200 ☀」按钮 `right ≤ 屏宽 − 列表右 padding`（真机溢出点）。
///
/// ⚠️ 全程**不用** `pumpAndSettle`：TabBackground 背景图 / 花园呼吸等存在无限动画，
/// `pumpAndSettle` 会永不返回（同 `tablet_scale_ipad13_test.dart` 的注释）。
/// ⚠️ `textScaler` 只能从 `MaterialApp.builder` 注入（F126/F127 探针踩过的坑）。
library tablet_card_scale_ipad13_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_sunlight_history_page.dart';
import 'package:sunflower_time/presentation/child/pages/store_page.dart';
import 'package:sunflower_time/presentation/child/widgets/reward_card.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_reward_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_task_config_page.dart';
import 'package:sunflower_time/presentation/parent/widgets/focus_report_section.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// iPad Pro 13″（M5）竖屏逻辑尺寸 —— 倍率 1.6（本次缺陷机型）。
const Size _kIpad13 = Size(1032, 1376);

/// iPad Pro 11″ 竖屏逻辑尺寸 —— 倍率 1.3（锚点机型，**零回归**对照组）。
const Size _kIpad11 = Size(834, 1194);

/// iPhone 竖屏逻辑尺寸 —— 倍率 1.0（手机，**零回归**对照组）。
const Size _kPhone = Size(390, 844);

/// 卡片列表右内边距（`store_page.dart` / `parent_reward_page.dart` 的
/// `EdgeInsets.fromLTRB(16, 0, 16, 16)` —— 是**页面级**常量，不随 UI 倍率放大）。
const double _kListPadH = 16.0;

/// 商店卡片「价签 + 阳光图标」里图标的**手机基准尺寸**（`reward_card.dart` 17pt）。
const double _kStoreSunIconBase = 17.0;

/// 家长奖励页价格胶囊里图标的**手机基准尺寸**（`parent_reward_page.dart` 16pt）。
const double _kParentSunIconBase = 16.0;

/// 家长「任务」页卡片阳光小胶囊图标的**手机基准尺寸**
/// （`parent_task_config_page.dart` 13pt）。
const double _kTaskSunIconBase = 13.0;

/// 阳光来源记录页顶部横幅图标的**手机基准尺寸**
/// （`child_sunlight_history_page.dart` 24pt）。
const double _kHistorySunIconBase = 24.0;

/// 家长专注报告 hero 卡图标的**手机基准尺寸**
/// （`focus_report_section.dart` 18pt）。
const double _kReportSunIconBase = 18.0;

/// 卡片列表内边距（`reward_card.dart` 12pt）——用于「padding 是否乘 s」的几何守卫。
const double _kCardPad = 12.0;

/// 一张「超长名字」的奖励模板（**实测 23 字**，390 宽下折 3 行）。
///
/// ⚠️ 别再写「33 字 / 29 字」这类估数（F130 三轮 QA P3-1）：QA 上轮取证用的
/// 是另一条 29 字夹具，与本常量无关，混写会让后来人以为夹具被换过。
///
/// 用途（F130 二轮）：手机修前的标题**没有 maxLines**（可自由折 3 行以上）。
/// 一轮里一刀切加的 `maxLines: 2` 会在手机上把长名字截断（QA 实测
/// `size=165.6×48, exceeded=true`）—— 本常量就是那条回归的取证靶子。
const String _kLongName = '睡前多玩10分钟再读一本绘本再说说今天发生的事';

/// 造一条成长项（家长「任务」页卡片需要非空列表，否则走空态没有卡片可量）。
Task _dailyTask(String id, String name) => Task(
      id: id,
      name: name,
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 15,
      sunlightReward: 12,
      isCustom: true,
    );

/// 造一条奖励模板：价格覆盖「2 位数 / 3 位数」，名字刻意给长（考验标题折行）。
RewardTemplate _reward({
  required String id,
  required String name,
  required int cost,
  required RewardContentCategory category,
}) =>
    RewardTemplate(
      id: id,
      name: name,
      category: RewardCategory.parentHandled,
      contentCategory: category,
      baseCost: cost,
      frequencyLimitPerWeek: 3,
    );

/// 「app.dart 同款注入壳」：走的是唯一注入点 [applyTabletTextScaling]。
///
/// 不在测试里写死 1.6 —— 让「视口 → MediaQueryData → 注入点 → 倍率」真实链路跑通。
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

  /// 建库 + 造数（3 条奖励，含 3 位数价格 200）+ 设视口 [size]。
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

    // 奖励模板：20 / 100 / **200**（3 位数 = 最宽的内容宽度压力）；
    // 200 那条用 [_kLongName]（23 字）—— 手机端必须**自由折行不截断**，
    // 平板端最多折 2 行且不溢出（F130 二轮的核心取证）。
    final RewardLocalRepository rewards =
        RewardLocalRepository(database, account: account);
    await rewards.saveTemplate(_reward(
      id: 'r_200',
      name: _kLongName,
      cost: 200,
      category: RewardContentCategory.play,
    ));
    await rewards.saveTemplate(_reward(
      id: 'r_100',
      name: '周末去游乐场',
      cost: 100,
      category: RewardContentCategory.play,
    ));
    await rewards.saveTemplate(_reward(
      id: 'r_20',
      name: '看动画20分钟',
      cost: 20,
      category: RewardContentCategory.entertainment,
    ));

    // 成长项：家长「任务」页（`ParentTaskConfigPage`）需要非空列表才渲染卡片。
    final TaskLocalRepository tasks =
        TaskLocalRepository(database, account: account);
    await tasks.saveTask(_dailyTask('t_read', '朗读英语'));
    await tasks.saveTask(_dailyTask('t_math', '数学口算练习十道题'));

    // 阳光余额 1000 → 三张卡都可兑换（**避免**全部走「阳光不足」禁用态，
    // 那样等于只测了一种分支；禁用态与可点态的内尺寸完全一致）。
    final DateTime now = DateTime.now();
    await SunlightLocalRepository(database, account: account).append(
      SunlightEntry(
        id: 'seed_sun',
        ts: now,
        type: SunlightType.earn,
        gross: 1000,
        net: 1000,
        balanceAfter: 1000,
        refType: 'test_seed',
        refId: 'f130',
        dayKey: dayKey(now),
      ),
    );

    container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(database),
        accountServiceProvider.overrideWithValue(account),
        // 家长奖励页顶部 WeeklyPoolCard 需要档位（免费档即可，与配额无关）。
        entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
      ],
    );
    addTearDown(container.dispose);
  }

  /// 有界 pump（禁用 `pumpAndSettle`，见文件头）。
  Future<void> pumpFrames(WidgetTester tester, {int frames = 12}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 抽干本帧期间的**全部**异常（`takeException` 一次只取一条；
  /// 真机截图里就有两条 overflow，只取一条会漏）。
  List<Object> drainExceptions(WidgetTester tester) {
    final List<Object> all = <Object>[];
    for (int i = 0; i < 20; i++) {
      final Object? e = tester.takeException();
      if (e == null) break;
      all.add(e);
    }
    return all;
  }

  /// 阳光素材图标（`assets/rewards/sunlight.png`）的 finder。
  Finder sunIcons() => find.byWidgetPredicate((Widget w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName == 'assets/rewards/sunlight.png');

  /// 奖励卡左侧「美术图标块」里的素材图（`assets/ui/store/*.webp`）finder。
  ///
  /// 它与阳光图标不同：由外层 `Container(56*s)` 给紧约束 → `getSize` 量到的就是
  /// 图标块的尺寸（素材无自带宽高，`BoxFit.cover` 满铺）。
  Finder rewardArtIcons() => find.byWidgetPredicate((Widget w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName.startsWith('assets/ui/store/'));

  /// 成长项卡片左侧图标块素材（`assets/ui/growth/*.webp`）—— 家长「任务」页用。
  Finder growthArtIcons() => find.byWidgetPredicate((Widget w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName.startsWith('assets/ui/growth/'));

  /// 断言所有阳光图标的**渲染宽度**都 ≈ [expected]（容差 0.5）。
  ///
  /// 用 `tester.getSize` 而不是读 widget 的 `width` 属性：只有真实渲染尺寸才能
  /// 证明「画出来」是那么大（父级约束把它压扁也能读到 width=27.2）。
  void expectWidthOf(
    WidgetTester tester,
    Finder finder,
    double expected, {
    required String reason,
  }) {
    final int count = finder.evaluate().length;
    expect(count, greaterThan(0), reason: '页面上必须真的渲染了 $finder');
    for (int i = 0; i < count; i++) {
      expect(tester.getSize(finder.at(i)).width, closeTo(expected, 0.5),
          reason: reason);
    }
  }

  group('F130 ① iPad 13″（1.6 倍）：商店卡片不再溢出、图标跟随放大', () {
    testWidgets('1032×1376 商店页：无溢出 + 阳光图标 17×1.6=27.2 + 「200 ☀」按钮不越界',
        (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(
        _injectedApp(const Scaffold(body: StorePage(embedded: true)), container),
      );
      await pumpFrames(tester);

      // 倍率真值（走真实注入链路）。
      final double s = uiScaleOf(tester.element(find.byType(StorePage)));
      expect(s, 1.6, reason: 'iPad 13″ 的 UI 倍率必须是 1.6（F129 派生）');

      // ① 无溢出（真机两条 RIGHT OVERFLOWED 的防线）。
      expect(drainExceptions(tester), isEmpty,
          reason: 'iPad 13″ 1.6 倍下商店页不得有任何 RenderFlex overflow');

      // ② 阳光图标渲染宽 = 17 × 1.6 = 27.2（此前写死 17 → 真机「图标偏小」）。
      expectWidthOf(tester, sunIcons(), _kStoreSunIconBase * s,
          reason: '兑换按钮里的阳光图标必须随倍率放大到 27.2（写死 17 就是本次缺陷）');

      // ③ 最宽的「200 ☀」按钮必须留在屏内。
      // 价格文案在按钮内部，故用 ancestor 精确定位那一张卡的按钮。
      final Finder widestButton = find.ancestor(
        of: find.text('200'),
        matching: find.byType(ElevatedButton),
      );
      expect(widestButton, findsOneWidget);
      final Rect btn = tester.getRect(widestButton);
      expect(btn.right, lessThanOrEqualTo(_kIpad13.width - _kListPadH + 0.5),
          reason: '三位数价格的兑换按钮不得越过列表右内边距（真机溢出点）');
      // 按钮仍保持「不窄于左侧图标块」的方正观感（min 约束生效）。
      expect(btn.width, greaterThanOrEqualTo(64 * s - 0.5),
          reason: '按钮宽度应 ≥ 64×1.6 = 102.4（minWidth 约束）');
      expect(btn.height, greaterThanOrEqualTo(64 * s - 0.5),
          reason: '按钮高度应 ≥ 64×1.6 = 102.4（minHeight 约束）');
      expect(drainExceptions(tester), isEmpty);

      // ④（F130 二轮 · 堵变异盲区）**内边距也必须乘 s**：QA 把 `padding: 12*s`
      // 改回 `12` 时 6 条用例全绿 → 间距类缩放完全无守卫。这里用几何反推：
      // 卡片外框左边缘 ↔ 首个图标块左边缘的差值 == 卡片 padding == 12×1.6 = 19.2。
      final Rect card = tester.getRect(find.byType(RewardCard).first);
      final Rect firstBlock = tester.getRect(rewardArtIcons().at(0));
      // ⚠️ 卡片外框有 `Border.all(0x26E8A600)` → **1pt 描边**，内容从描边内侧开始，
      // 故实测差值 = padding 19.2 + 1 = 20.2（不是 19.2）。把描边写进期望值，
      // 这样「padding 被改回 12」时差 7.2 → 必红，而描边本身变化也会被察觉。
      expect(firstBlock.left - card.left, closeTo(_kCardPad * s + 1.0, 0.5),
          reason: '卡片内边距必须随倍率放大到 19.2（+1pt 描边；改回 12 时此断言必红）');
    });
  });

  group('F130 ② iPad 13″（1.6 倍）：家长奖励页价格胶囊图标跟随放大', () {
    testWidgets('1032×1376 家长奖励页：无溢出 + 胶囊内阳光图标 16×1.6=25.6',
        (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(
        _injectedApp(
          const Scaffold(body: ParentRewardPage()),
          container,
        ),
      );
      await pumpFrames(tester);

      final double s = uiScaleOf(tester.element(find.byType(ParentRewardPage)));
      expect(s, 1.6);

      // ④ 无溢出。
      expect(drainExceptions(tester), isEmpty,
          reason: 'iPad 13″ 1.6 倍下家长奖励页不得溢出');

      // ⑤ 胶囊内阳光图标渲染宽 = 16 × 1.6 = 25.6（此前写死 16 → 真机截图「偏小」）。
      expectWidthOf(tester, sunIcons(), _kParentSunIconBase * s,
          reason: '价格胶囊里的阳光图标必须随倍率放大到 25.6');
    });

    testWidgets('1032×1376 家长奖励页：卡片图标块 56×1.6=89.6（字大图标不再小）',
        (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(
        _injectedApp(const Scaffold(body: ParentRewardPage()), container),
      );
      await pumpFrames(tester);

      final double s = uiScaleOf(tester.element(find.byType(ParentRewardPage)));
      // 奖励美术图标所在的方块：外层 `Container(56*s)` 给紧约束 → 量到的就是图标块。
      // 手机 56 → iPad 13″ 89.6。此前写死 56，1.6 倍下文字涨 60% 而图标块不动。
      expectWidthOf(tester, rewardArtIcons(), 56 * s,
          reason: '卡片左侧图标块必须随倍率放大到 89.6（写死 56 就是「字大图标小」）');
      expect(drainExceptions(tester), isEmpty);
    });
  });

  group('F130 ③ 对照组：iPad 11″（1.3×）与手机（1.0×）零回归', () {
    testWidgets('834×1194（iPad 11″）商店页：无溢出 + 图标 17×1.3=22.1',
        (WidgetTester tester) async {
      await boot(tester, _kIpad11);
      await tester.pumpWidget(
        _injectedApp(const Scaffold(body: StorePage(embedded: true)), container),
      );
      await pumpFrames(tester);

      final double s = uiScaleOf(tester.element(find.byType(StorePage)));
      expect(s, 1.3, reason: '锚点机型倍率仍是 1.3（F129 零回归）');
      expect(drainExceptions(tester), isEmpty, reason: 'iPad 11″ 不得因本次改动溢出');
      expectWidthOf(tester, sunIcons(), _kStoreSunIconBase * s,
          reason: 'iPad 11″ 图标应为 22.1（1.6 与 1.3 必须真的不同 → 随倍率变化）');
    });

    testWidgets('390×844（手机）商店页：无溢出 + 图标 17×1.0=17.0（逐位零回归）',
        (WidgetTester tester) async {
      await boot(tester, _kPhone);
      await tester.pumpWidget(
        _injectedApp(const Scaffold(body: StorePage(embedded: true)), container),
      );
      await pumpFrames(tester);

      final double s = uiScaleOf(tester.element(find.byType(StorePage)));
      expect(s, 1.0, reason: '手机恒 1.0（不得被平板分支污染）');
      expect(drainExceptions(tester), isEmpty, reason: '手机端不得溢出');
      expectWidthOf(tester, sunIcons(), _kStoreSunIconBase * s,
          reason: '手机端图标必须逐位等于修前的 17.0（零像素变化）');

      // 手机端卡片**几何逐位不变**：图标块 64×64、**两位数价格**的按钮 64×64
      //（C47 与成长任务卡对齐的 88pt 卡高就靠这两块），乘法在 s=1.0 时不得带走像素。
      final Size block = tester.getSize(rewardArtIcons().at(0));
      expect(block.width, closeTo(64.0, 0.5), reason: '手机图标块仍 64 宽');
      expect(block.height, closeTo(64.0, 0.5), reason: '手机图标块仍 64 高');
      final Rect btn20 = tester.getRect(find
          .ancestor(of: find.text('20'), matching: find.byType(ElevatedButton)));
      expect(btn20.width, closeTo(64.0, 0.5),
          reason: '两位数价格的按钮仍是 64×64（零像素变化）');
      expect(btn20.height, closeTo(64.0, 0.5), reason: '按钮高度仍 64');

      // 附带实证：**三位数**价格连手机都塞不进旧死宽 64（实测内容 65.3pt）——
      // 这正是「死宽」的隐性缺陷，改用 min 约束后它靠自然增长化解，不再溢出。
      final Rect btn200 = tester.getRect(find
          .ancestor(of: find.text('200'), matching: find.byType(ElevatedButton)));
      expect(btn200.width, greaterThan(64.0),
          reason: '三位数价格在手机上就超过 64pt：按钮必须按内容增长，不能溢出');

      // 🔴 F130 二轮：**长名字在手机上必须继续自由折行**（修前无 maxLines）。
      // 一轮里一刀切 `maxLines: 2` 把长名字截断了（QA 上轮用**另一条 29 字夹具**
      // 实测 exceeded=true），现改为「只有平板限 2 行」，手机 maxLines: null。
      //
      // 断言分主辅两层（F130 三轮 QA P3-4 修正）：
      //  · **主**：`Text.maxLines == null` —— 这是「一刀切 2 行」回归的**精确**守卫，
      //    不依赖任何字体/行高，永远不会假红。
      //  · 辅：`didExceedMaxLines == false` + 高度 > 48（≈2 行）。高度断言只是
      //    「确实折到了多行」的旁证；若将来主题字号/行高变动导致本夹具只折 2 行，
      //    这一条需要重新取基线（方向安全：只会假红，不会假绿）。
      final Text titleWidget = tester.widget<Text>(find.text(_kLongName));
      expect(titleWidget.maxLines, isNull,
          reason: '手机端标题必须无行数上限（maxLines: null 即修前口径）');
      final RenderParagraph title =
          tester.renderObject<RenderParagraph>(find.text(_kLongName));
      expect(title.didExceedMaxLines, isFalse,
          reason: '手机端长名字不得被截断（修前可自由折行，2 行封顶就是回归）');
      expect(title.size.height, greaterThan(48.0),
          reason: '必须真的折到 2 行以上（48 = 2×行高；被 2 行截断时会正好停在 48）');
      expect(drainExceptions(tester), isEmpty, reason: '自由折行也不得溢出');
    });

    testWidgets('390×844（手机）家长奖励页：无溢出 + 胶囊图标 16.0（零回归）',
        (WidgetTester tester) async {
      await boot(tester, _kPhone);
      await tester.pumpWidget(
        _injectedApp(const Scaffold(body: ParentRewardPage()), container),
      );
      await pumpFrames(tester);

      final double s = uiScaleOf(tester.element(find.byType(ParentRewardPage)));
      expect(s, 1.0);
      expect(drainExceptions(tester), isEmpty, reason: '手机端家长奖励页不得溢出');
      expectWidthOf(tester, sunIcons(), _kParentSunIconBase * s,
          reason: '手机端胶囊图标必须逐位等于修前的 16.0（零像素变化）');
    });
  });

  group('F130 ④ 二轮补充：平板限行 / 任务页覆盖 / 两处同款图标', () {
    testWidgets('1032×1376 商店页：长名字最多 2 行（不截断到只剩几个字）且不溢出',
        (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(
        _injectedApp(const Scaffold(body: StorePage(embedded: true)), container),
      );
      await pumpFrames(tester);

      final RenderParagraph title =
          tester.renderObject<RenderParagraph>(find.text(_kLongName));
      expect(title.maxLines, 2, reason: '平板端才限 2 行（手机端为 null，见上一个用例）');
      // 行数用高度反推（本 Flutter 版本的 RenderParagraph 没有 computeLineMetrics）：
      // 1.6 倍下 titleMedium ≈25.6pt、行高 ≈36pt → 2 行 ≈72、3 行 ≈108，
      // 故 `< 90` 足以区分「2 行封顶」与「折到 3 行」。
      expect(title.size.height, lessThan(90.0),
          reason: '平板端最多 2 行（限行的目的：1.6 倍下不让标题把卡片撑高）');
      expect(title.size.width, greaterThan(120),
          reason: '标题区不得被按钮挤成一条窄缝（得留出可读宽度）');
      expect(drainExceptions(tester), isEmpty, reason: '限行后不得溢出');
    });

    testWidgets('1032×1376 家长「任务」页：阳光小胶囊 13×1.6=20.8 + 图标块 89.6',
        (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(
        _injectedApp(
          const Scaffold(body: ParentTaskConfigPage(embedded: true)),
          container,
        ),
      );
      await pumpFrames(tester);

      final double s =
          uiScaleOf(tester.element(find.byType(ParentTaskConfigPage)));
      expect(s, 1.6);

      // 无异常 / 无 overflow。
      expect(drainExceptions(tester), isEmpty,
          reason: 'iPad 13″ 1.6 倍下家长任务页不得溢出');

      // 阳光小胶囊图标 13×1.6 = 20.8（QA 变异实测：改回 13 时其它用例全绿 →
      // 这一处此前完全无守卫，本用例就是它的守卫）。
      expectWidthOf(tester, sunIcons(), _kTaskSunIconBase * s,
          reason: '任务卡阳光胶囊图标必须随倍率放大到 20.8（写死 13 就是同款病）');
      // 卡片左侧成长素材图标块 56×1.6 = 89.6。
      expectWidthOf(tester, growthArtIcons(), 56 * s,
          reason: '任务卡图标块必须随倍率放大到 89.6');
    });

    testWidgets('1032×1376 阳光来源记录页：横幅图标 24×1.6=38.4',
        (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(
        _injectedApp(const ChildSunlightHistoryPage(), container),
      );
      await pumpFrames(tester);

      final double s =
          uiScaleOf(tester.element(find.byType(ChildSunlightHistoryPage)));
      expect(s, 1.6);
      expect(find.text('当前拥有阳光'), findsOneWidget,
          reason: '横幅必须真的渲染出来（否则「量不到图标」会被误读成通过）');
      expect(drainExceptions(tester), isEmpty,
          reason: 'iPad 13″ 1.6 倍下阳光来源记录页不得溢出');
      expectWidthOf(tester, sunIcons(), _kHistorySunIconBase * s,
          reason: '余额横幅阳光图标必须随倍率放大到 38.4（同卡文字已走 textScaler）');
    });

    testWidgets('1032×1376 家长专注报告 hero 卡：阳光图标 18×1.6=28.8',
        (WidgetTester tester) async {
      await boot(tester, _kIpad13);
      await tester.pumpWidget(
        // ⚠️ FocusReportSection 自带纵向 ListView（生产里挂在记录页分段中，有界高），
        // 不能再套 SingleChildScrollView —— 会「Vertical viewport was given unbounded
        // height」。直接作为 body 挂，给它有界高度。
        _injectedApp(const Scaffold(body: FocusReportSection()), container),
      );
      await pumpFrames(tester, frames: 20);

      final double s =
          uiScaleOf(tester.element(find.byType(FocusReportSection)));
      expect(s, 1.6);
      expect(find.text('本期间专注'), findsOneWidget,
          reason: 'hero 卡必须真的渲染出来');
      expect(drainExceptions(tester), isEmpty,
          reason: 'iPad 13″ 1.6 倍下专注报告段不得溢出');
      expectWidthOf(tester, sunIcons(), _kReportSunIconBase * s,
          reason: 'hero 卡阳光图标必须随倍率放大到 28.8（「字大图标不动」同款病）');
    });
  });
}
