/// ChildProfileBar（C90 期 1 · 家长天地档案胶囊条）组件测试。
///
/// 钉死：
///  · 胶囊条显示当前孩子名；切换后文字更新（**屏幕正中轻提示**「已切换到 X」，
///    玄参 2026-10-17 反馈：底部 SnackBar 太不显眼）；
///  · 免费档已有 1 个 → 点「新建孩子」→ 填名提交 → 弹「升级解锁」且**列表不变**
///    （🔴 C69 红线：绝不删已存档案；C62：按钮照常可点，点了才拦）；
///  · 买断档可建到 3 个；第 4 个被拦时**不再弹「升级解锁」**（玄参反馈：已买断
///    的用户不该再看到升级页），改为居中轻提示「最多支持 3 个孩子账户」；
///  · 菜单为**原地下拉**（玄参反馈：不要从屏幕底部弹抽屉）；
///  · 编辑 = 预填对话框改名，落库生效（C90 期 1 追加，不受门控）；
///  · 删除 = 家长 PIN 复核（玄参拍板）：PIN 错内联报错不删；最后 1 个不可删；
///    删除生效后档案数减少（C90 期 1 追加）。
///
/// 权益注入仿 `test/m3/parent_history_page_test.dart` 的 `_overrides(premium:)`
/// 模式（`entitlementProvider.overrideWith`）。
library child_profile_bar_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/secure_store.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/parent/widgets/child_profile_bar.dart';

void main() {
  testWidgets('胶囊条显示当前孩子名（默认孩子）', (WidgetTester tester) async {
    final _Harness h = await _Harness.create(tester, premium: false);
    await h.pump();

    expect(find.text('孩子'), findsOneWidget,
        reason: '冷启动 initialize 建的默认孩子 name = 孩子');
  });

  testWidgets('切换：点「二娃」→ 胶囊文字更新 + 居中轻提示', (WidgetTester tester) async {
    final _Harness h = await _Harness.create(tester, premium: false);
    await h.account.createChild('二娃', AgeTier.mid);
    await h.pump();

    await h.openMenu();
    await tester.tap(find.text('二娃'));
    await tester.pumpAndSettle();

    expect(find.text('已切换到「二娃」'), findsOneWidget,
        reason: '屏幕正中轻提示（Overlay）');
    expect(find.text('二娃'), findsWidgets, reason: '胶囊条已更新为二娃');
    expect(h.account.childId, isNot('single-child'));
    await _flushToast(tester);
  });

  testWidgets('免费档：已有 1 个 → 新建被拦弹「升级解锁」且列表不变（C69）',
      (WidgetTester tester) async {
    final _Harness h = await _Harness.create(tester, premium: false);
    await h.pump();

    await h.openMenu();
    await tester.tap(find.text('新建孩子'));
    await tester.pumpAndSettle();

    // 填名提交（按钮照常可点，C62）。
    await tester.enterText(find.byType(TextField), '二娃');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    // 弹升级、不创建。
    expect(find.text('升级解锁'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    // 🔴 列表不变：档案仍是 1 个（默认孩子），重开菜单只有「孩子」。
    expect(await h.repo.count(), 1);
    await h.openMenu();
    expect(find.text('孩子'), findsWidgets, reason: '胶囊条 + 菜单各一处「孩子」');
    expect(find.text('二娃'), findsNothing,
        reason: '被拦的新建不得产生任何档案行（C69）');
    await _closeMenu(tester);
  });

  testWidgets('买断档：已有 3 个 → 第 4 个被拦，提示「最多支持 3 个孩子账户」且列表不变（C69）',
      (WidgetTester tester) async {
    final _Harness h = await _Harness.create(tester, premium: true);
    // 预置到 3 个（默认 + 2）。
    await h.account.createChild('大娃', AgeTier.low);
    await h.account.createChild('二娃', AgeTier.mid);
    await h.pump();

    // 第 4 个：填名提交 → 被拦。
    await h.openMenu();
    await tester.tap(find.text('新建孩子'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '三娃');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    // 玄参 2026-10-17 反馈：买断档已到顶**不再弹「升级解锁」**，改居中轻提示。
    expect(find.text('升级解锁'), findsNothing);
    expect(find.text('最多支持 3 个孩子账户'), findsOneWidget);
    await _flushToast(tester);

    expect(await h.repo.count(), 3, reason: 'C69：被拦的第 4 个不得创建，已存 3 个保留');
    await h.openMenu();
    expect(find.text('三娃'), findsNothing,
        reason: '被拦的新建不得产生任何档案行（C69）');
    await _closeMenu(tester);
  });

  testWidgets('买断档：已有 2 个 → 可建到 3 个（居中轻提示「已添加」）',
      (WidgetTester tester) async {
    final _Harness h = await _Harness.create(tester, premium: true);
    await h.account.createChild('大娃', AgeTier.low);
    await h.pump();

    await h.openMenu();
    await tester.tap(find.text('新建孩子'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '二娃');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.text('已添加「二娃」'), findsOneWidget);
    expect(await h.repo.count(), 3);
    await _flushToast(tester);
  });

  testWidgets('新建对话框：三档年龄段文案与固定尺寸卡片（玄参 2026-10-17 反馈）',
      (WidgetTester tester) async {
    final _Harness h = await _Harness.create(tester, premium: true);
    await h.pump();

    await h.openMenu();
    await tester.tap(find.text('新建孩子'));
    await tester.pumpAndSettle();

    // 三档文案（拍板口径）逐字在屏；每档都在同一尺寸（48 高）的固定卡片里。
    expect(find.text('低年级 · 小于 8 岁'), findsOneWidget);
    expect(find.text('中年级 · 8–12 岁'), findsOneWidget);
    expect(find.text('高年级 · 大于 12 岁'), findsOneWidget);
    final Finder card48 = find.byWidgetPredicate(
      (Widget w) => w is SizedBox && w.height == 48,
    );
    for (final String label in <String>[
      '低年级 · 小于 8 岁',
      '中年级 · 8–12 岁',
      '高年级 · 大于 12 岁',
    ]) {
      expect(
        find.ancestor(of: find.text(label), matching: card48),
        findsOneWidget,
        reason: '$label 必须在 48 高的固定尺寸卡片内（玄参反馈）',
      );
    }
    final List<Size> sizes = <Size>[
      for (final String label in <String>['低年级 · 小于 8 岁', '中年级 · 8–12 岁', '高年级 · 大于 12 岁'])
        tester.getSize(find.ancestor(
          of: find.text(label),
          matching: card48,
        )),
    ];
    expect(sizes[0].width, sizes[1].width, reason: '同宽（纵向并列）');
    expect(sizes[1].width, sizes[2].width, reason: '同宽（纵向并列）');

    // 选中第 2 档 → 选中态迁移（勾标恰 1 枚 = 单选）。
    await tester.tap(find.text('中年级 · 8–12 岁'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget, reason: '选中卡片带勾');
  });

  testWidgets('编辑：预填名字改名保存 → 落库 + 胶囊条更新（不受门控）',
      (WidgetTester tester) async {
    final _Harness h = await _Harness.create(tester, premium: false);
    await h.account.createChild('二娃', AgeTier.mid);
    await h.pump();

    await h.openMenu();
    // 二娃在菜单第 2 行 → 其行尾编辑图标 = 全部编辑图标中的最后一个。
    await tester.tap(find.byIcon(Icons.edit_outlined).last);
    await tester.pumpAndSettle();

    // 预填「二娃」→ 改名 → 保存（编辑不受门控，免费档也放行）。
    expect(find.text('编辑孩子'), findsOneWidget, reason: '编辑模式标题');
    expect(find.text('二娃'), findsWidgets, reason: '名字预填');
    await tester.enterText(find.byType(TextField), '二娃子');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('已更新「二娃子」'), findsOneWidget);
    final List<ChildProfile> list = await h.repo.children();
    expect(list.map((ChildProfile c) => c.name), contains('二娃子'),
        reason: '改名已落库');
    expect(list.map((ChildProfile c) => c.name), isNot(contains('二娃')));
    await _flushToast(tester);
  });

  testWidgets('删除兜底：仅剩 1 个档案 → 删除被拦「至少保留一个孩子档案」',
      (WidgetTester tester) async {
    final _Harness h = await _Harness.create(tester, premium: false);
    await h.pump();

    await h.openMenu();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // 不出 PIN 对话框，直接居中提示；档案不动。
    expect(find.text('至少保留一个孩子档案'), findsOneWidget);
    expect(find.text('家长 PIN'), findsNothing);
    expect(await h.repo.count(), 1);
    await _flushToast(tester);
  });

  testWidgets('删除 PIN 复核：错 PIN 内联报错不删，对 PIN 才落删',
      (WidgetTester tester) async {
    final _Harness h = await _Harness.create(tester, premium: true);
    await h.account.createChild('二娃', AgeTier.mid);
    await h.pump();

    // 错 PIN：内联报错、弹窗不关、不落删。
    await h.openMenu();
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('PIN 不正确，请重试'), findsOneWidget);
    expect(await h.repo.count(), 2, reason: '错 PIN 不得删除');

    // 对 PIN：弹窗关闭、落删、居中提示。
    await tester.enterText(find.byType(TextField), '888888');
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('已删除「二娃」'), findsOneWidget);
    expect(await h.repo.count(), 1);
    await _flushToast(tester);
  });
}

/// SecureStore 桩：跳过 flutter_secure_storage 平台通道（测试环境无实现）。
/// 只有 '888888' 校验通过，其余一律 false（含空串 / 错值）。
class _StubSecureStore extends SecureStore {
  _StubSecureStore() : super();

  static const String kCorrectPin = '888888';

  @override
  Future<bool> verify(String pin) async => pin == kCorrectPin;
}

/// 测试脚手架：内存库 + 真仓储 + 真 AccountService（mock SP）+ 权益覆盖。
class _Harness {
  _Harness(this.tester, {required this.premium});  /// 异步工厂：先完成初始化（内存库 / mock SP / initialize）再返回。
  static Future<_Harness> create(
    WidgetTester tester, {
    required bool premium,
  }) async {
    final _Harness h = _Harness(tester, premium: premium);
    await h._init();
    return h;
  }

  final WidgetTester tester;
  final bool premium;

  late AppDatabase db;
  late ChildProfileLocalRepository repo;
  late AccountService account;
  bool _inited = false;

  Future<void> _init() async {
    if (_inited) return;
    _inited = true;
    SharedPreferences.setMockInitialValues(
      <String, Object>{kPrefActiveChildId: 'single-child'},
    );
    final SharedPreferences sp = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    // 测试卫生：用例结束关库（否则 drift 会告警「多次实例化 AppDatabase」）。
    addTearDown(db.close);
    repo = ChildProfileLocalRepository(db);
    account = AccountService(
      children: repo,
      settings: SettingsLocalRepository(db),
      prefs: sp,
    );
    await account.initialize();
  }

  Future<void> pump() async {
    await _init();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          childProfileRepositoryProvider.overrideWithValue(repo),
          accountServiceProvider.overrideWithValue(account),
          // 删除流程的 PIN 复核桩：只有 '888888' 能通过（flutter_secure_storage
          // 在测试环境无平台实现，必须替换）。
          secureStoreProvider.overrideWithValue(_StubSecureStore()),
          if (premium)
            entitlementProvider.overrideWith(
              (Ref ref) => Entitlement.lifetime(
                acquiredAt: DateTime(2026, 10, 17),
                productId: 'test.lifetime',
              ),
            ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChildProfileBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu() async {
    await tester.tap(find.byType(ChildProfileBar));
    await tester.pumpAndSettle();
  }
}

/// 结束前把居中轻提示的显示 / 淡出 / 自摘 Timer 走完（防 pending timer 误报）。
Future<void> _flushToast(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 关掉仍开着的下拉菜单（点空白处）。
Future<void> _closeMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}
