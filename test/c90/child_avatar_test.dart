/// C90-C：孩子端「我的」页头像（玄参 2026-10-18 拍板）。
///
/// 钉死四条口径：
///  ① 默认头像 = 阳光 UI（child_profiles.avatar 默认 kChildAvatarSun）；
///     点头像弹「选择头像」卡片（阳光 + 全部物种；C91：居中 Dialog）；
///  ② **已种植**的物种可选 → 选中落库 `child_profiles.avatar`（物种 id），
///     AccountService 快照经 switchTo 刷新；
///  ③ **未种植**的物种置灰 + 小锁但**可点** —— 点击提示
///     [kChildAvatarLockedHint]（绝不静默，C62 纪律），面板不收起、不落库；
///  ④ 头像跟孩子档案走：切孩子各用各的（B 未种过 → 全部物种加锁、保持阳光）。
///
/// 脚手架参照 `test/c90/child_profile_page_child_binding_test.dart`：
/// 内存 Drift 库 + mock SP + 真 Dao / 真仓储全链路，无平台通道。
library child_avatar_test;

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
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';
import 'package:sunflower_time/presentation/child/widgets/child_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, AccountService, ChildProfileLocalRepository)>
      pumpPage(WidgetTester tester,
          {Map<String, Object> spValues = const <String, Object>{}}) async {
    SharedPreferences.setMockInitialValues(spValues);
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ChildProfileLocalRepository children =
        ChildProfileLocalRepository(database);
    final AccountService account = AccountService(
      children: children,
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
        ],
        child: const MaterialApp(home: Scaffold(body: ChildProfilePage())),
      ),
    );
    // 等待 _reload 完成（成就区出现即加载完成）。
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('累计成就').evaluate().isNotEmpty) break;
    }
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(ChildProfilePage)));
    return (container, account, children);
  }

  /// 给当前孩子种一株指定物种的植物（走真仓储 → plants 表按当前 childId 落标）。
  Future<void> plantSpecies(
      ProviderContainer container, String speciesId) async {
    final DateTime now = DateTime(2026, 9, 15, 10);
    await container.read(plantRepositoryProvider).savePlant(Plant(
          id: 'plant_$speciesId',
          speciesId: speciesId,
          potIndex: 0,
          stage: PlantStage.seed,
          stageStartedAt: now,
          growthFactor: 1.0,
          status: PlantStatus.growing,
          plantedAt: now,
        ));
  }

  /// 弹层内（C91：居中 Dialog 卡片 `child_avatar_dialog` 子树）的加锁图标数。
  Finder dialogBody(WidgetTester tester) => find.descendant(
        of: find.byKey(const ValueKey<String>('child_avatar_dialog')),
        matching: find.byIcon(Icons.lock_outline),
      );
  int sheetLockCount(WidgetTester tester) => dialogBody(tester).evaluate().length;

  testWidgets('① 默认头像阳光；点头像弹选择面板（阳光 + 全部物种，未种植全加锁）',
      (tester) async {
    await pumpPage(tester);

    // 默认头像视图存在（阳光取值渲染在 ChildAvatarView）。
    expect(find.byType(ChildAvatarView), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('child_avatar_tap')),
        findsOneWidget);

    // 点头像 → 面板出现。
    await tester.tap(find.byKey(const ValueKey<String>('child_avatar_tap')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('选择头像'), findsOneWidget);
    expect(find.text('阳光'), findsOneWidget);
    // 物种种子 8 种全部出现在面板（以代表性物种钉死）。
    expect(find.text('向日葵'), findsOneWidget);
    expect(find.text('月光兰'), findsOneWidget);
    expect(find.text('葡萄'), findsOneWidget);
    expect(find.text('玫瑰'), findsOneWidget);
    // 未种植 → 全部 8 个物种加锁；阳光选项恒可选（当前选中打勾）。
    expect(sheetLockCount(tester), 8);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('child_avatar_dialog')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
      reason: '当前头像（阳光）在卡片中打勾',
    );
  });

  testWidgets('② 未种植物种：置灰加锁但可点 → 提示语出现、面板不收起、不落库',
      (tester) async {
    final (ProviderContainer container, _, ChildProfileLocalRepository children) =
        await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey<String>('child_avatar_tap')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 点锁定项（月光兰，未种植）→ 提示（绝不静默）。
    await tester.tap(
        find.byKey(const ValueKey<String>('avatar_option_species_moon_orchid')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(kChildAvatarLockedHint), findsOneWidget,
        reason: '锁定项点击必须给出提示，不可静默（C62 纪律）');
    expect(find.text('选择头像'), findsOneWidget,
        reason: '锁定项提示后卡片留在原地（不 pop、不落库）');
    expect(
      (await children.children()).single.avatar,
      kChildAvatarSun,
      reason: '锁定项点击绝不改头像',
    );
    expect(container.read(childProfileRevisionProvider), 0,
        reason: '锁定项点击不触发任何落库 / 修订号自增');

    // 收尾：点可选的阳光 → 卡片收起（重复选同一头像不落库，静默关闭）。
    await tester
        .tap(find.byKey(const ValueKey<String>('avatar_option_$kChildAvatarSun')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('选择头像'), findsNothing);
  });

  testWidgets('③ 已种植物种可选：选中 → 落库 avatar + AccountService 快照刷新',
      (tester) async {
    final (ProviderContainer container, AccountService account,
            ChildProfileLocalRepository children) =
        await pumpPage(tester);

    // 当前孩子（默认孩子）种下番茄 → 重载后 plantedSpecies 含番茄。
    await plantSpecies(container, 'species_tomato');
    container.read(childProfileRevisionProvider.notifier).state++;
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey<String>('child_avatar_tap')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 已种 1 种 → 锁数 = 8 - 1 = 7（番茄解锁）。
    expect(sheetLockCount(tester), 7, reason: '番茄已种植，必须解锁可选');

    await tester
        .tap(find.byKey(const ValueKey<String>('avatar_option_species_tomato')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 卡片收起 + 头像落库（物种 id）+ 活跃快照刷新。
    expect(find.text('选择头像'), findsNothing);
    expect((await children.children()).single.avatar, 'species_tomato');
    expect((await account.currentProfile())!.avatar, 'species_tomato',
        reason: 'switchTo 刷新后 AccountService 快照头像同步');
  });

  testWidgets('④ 头像跟孩子走：A 选植物头像，B（未种）保持阳光且全加锁',
      (tester) async {
    final (ProviderContainer container, AccountService account,
            ChildProfileLocalRepository children) =
        await pumpPage(tester);

    // A（默认孩子）：种番茄并选它当头像。
    await plantSpecies(container, 'species_tomato');
    container.read(childProfileRevisionProvider.notifier).state++;
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey<String>('child_avatar_tap')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester
        .tap(find.byKey(const ValueKey<String>('avatar_option_species_tomato')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect((await children.children()).first.avatar, 'species_tomato');

    // 切到 B（小明，未种任何植物）→ 页面随修订号重载。
    final ChildProfile second = await account.createChild('小明', AgeTier.low);
    await account.switchTo(second.id);
    container.read(childProfileRevisionProvider.notifier).state++;
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey<String>('child_avatar_tap')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // B 视角：番茄也没种过 → 全部 8 种加锁（各用各的，不蹭 A 的已种记录）。
    expect(sheetLockCount(tester), 8,
        reason: '切孩子后已种集合跟孩子走：B 未种过 → 全加锁');

    // 收面板（点遮罩关闭）→ B 头像保持默认阳光。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(
      (await children.children())
          .firstWhere((p) => p.id == second.id)
          .avatar,
      kChildAvatarSun,
      reason: 'B 未选过头像，必须保持默认阳光',
    );
    // A 的头像不被串改。
    expect(
      (await children.children())
          .firstWhere((p) => p.id == kChildIdDefault)
          .avatar,
      'species_tomato',
      reason: 'A 的植物头像独立保存，切孩子互不影响',
    );
  });

  /// 弹层全部选项的 ValueKey（阳光 + 8 物种 = 9 条）。
  List<String> optionKeys() => <String>[
        'avatar_option_$kChildAvatarSun',
        'avatar_option_$kStarterSpeciesId',
        'avatar_option_species_moon_orchid',
        'avatar_option_species_tomato',
        'avatar_option_species_strawberry',
        'avatar_option_species_coral_orchid',
        'avatar_option_species_jade_hydrangea',
        'avatar_option_species_grape',
        'avatar_option_species_rose',
      ];

  /// C91 二轮（玄参 iOS 模拟器反馈：网格不对称）：**固定每行恰 3 个**的对称
  /// 网格 —— 最窄支持视口（320×568，C83 先例）下也必须 3+3+3、每行（含尾行）
  /// 水平居中。位置断言全部用真实渲染坐标（`tester.getCenter`，真实字体度量），
  /// 不写死任何高度。
  /// F153（2026-10-26）：物种 7→8（+玫瑰）→ 头像选项 8→9 项 = 3+3+3。
  testWidgets('⑤ 网格对称：320 宽手机下每行恰 3 个、尾行（第 9 项）水平居中',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey<String>('child_avatar_tap')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 9 个选项（阳光默认 + 8 物种）全部渲染。
    final List<Offset> centers = <Offset>[
      for (final String k in optionKeys())
        tester.getCenter(find.byKey(ValueKey<String>(k))),
    ];
    expect(centers, hasLength(9));

    // 按 y 坐标分行（同行 y 差 < 1px）。
    final List<List<Offset>> rows = <List<Offset>>[];
    for (final Offset c in centers) {
      List<Offset> row;
      try {
        row = rows.firstWhere(
          (List<Offset> r) => (r.first.dy - c.dy).abs() < 1.0,
        );
      } on StateError {
        row = <Offset>[];
        rows.add(row);
      }
      row.add(c);
    }
    expect(
      rows.map((List<Offset> r) => r.length).toList(),
      <int>[3, 3, 3],
      reason: '9 个条目必须固定 3+3+3 三行（窄屏手机不再折成 2 列，平板不漂移）',
    );

    // 每行（含不满一行的尾行）都必须水平居中于弹窗。
    final double dialogCenterX = tester
        .getCenter(find.byKey(const ValueKey<String>('child_avatar_dialog')))
        .dx;
    for (final List<Offset> row in rows) {
      final double rowCenterX = (row.first.dx + row.last.dx) / 2;
      expect(rowCenterX, closeTo(dialogCenterX, 1.0),
          reason: '每行（含第 ${rows.indexOf(row) + 1} 行）水平居中');
    }

    // 触点纪律照旧：每个选项的可点区域 ≥ 44pt。
    for (final String k in optionKeys()) {
      final Size size = tester.getSize(find.byKey(ValueKey<String>(k)));
      expect(size.width, greaterThanOrEqualTo(44.0), reason: '$k 宽触点 ≥44pt');
      expect(size.height, greaterThanOrEqualTo(44.0),
          reason: '$k 高触点 ≥44pt');
    }
  });

  /// 平板（800×600 测试默认视口）下行结构与手机**完全一致**（3+3+3、尾行居中、
  /// 条目尺寸 / 间距统一）—— 钉死「平板与手机一致美观」。
  testWidgets('⑥ 平板视口：行结构与手机一致（3+3+3），条目尺寸统一', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey<String>('child_avatar_tap')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final List<Offset> centers = <Offset>[
      for (final String k in optionKeys())
        tester.getCenter(find.byKey(ValueKey<String>(k))),
    ];
    final List<List<Offset>> rows = <List<Offset>>[];
    for (final Offset c in centers) {
      List<Offset> row;
      try {
        row = rows.firstWhere(
          (List<Offset> r) => (r.first.dy - c.dy).abs() < 1.0,
        );
      } on StateError {
        row = <Offset>[];
        rows.add(row);
      }
      row.add(c);
    }
    expect(
      rows.map((List<Offset> r) => r.length).toList(),
      <int>[3, 3, 3],
      reason: '平板视口同样固定 3+3+3（行结构不随屏宽漂移）',
    );

    // 两视口下条目尺寸完全一致（窄屏 72pt 格 → 平板同款）。
    for (final String k in optionKeys()) {
      expect(tester.getSize(find.byKey(ValueKey<String>(k))).width, 72.0,
          reason: '条目尺寸平板与手机一致（72pt 格）');
    }
  });
}
