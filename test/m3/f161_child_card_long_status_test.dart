/// F161（玄参 2026-10-29）：孩子端「成长」卡 **英文长状态胶囊把标题挤成竖排** 回归守卫。
///
/// 现象（真机 iPhone 390pt 实证）：点「我做到了」后右侧状态变
/// `Waiting for approval`，胶囊按 intrinsic 取宽（≈213pt），把左侧标题列压到
/// ≈33pt —— 英文按字母折行，"Read for 20 minutes" 变成一列竖字，卡片高度暴涨。
/// 中文「等待家长确认」只有 6 字（≈126pt）不触发，平板屏宽也不触发。
///
/// 修复口径：状态胶囊加**屏宽 36% 的宽度上限**，文案在胶囊内折行。
///
/// 本测试守的是「**标题不被压扁**」这个可量化事实（标题渲染宽度），
/// 不是某段文案 —— 换文案、换语言都不该让标题重新变成一列。
library f161_child_card_long_status_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';

/// 标题列渲染宽度的下限。修复前实测 ≈33pt（逐字竖排），修复后 ≈105pt。
/// 取 80 作闸门：既挡住「竖排」回归，又不锁死具体排版数值。
const double _kTitleMinWidth = 80;

void _useScreen(WidgetTester tester, Size logical) {
  tester.view.physicalSize = Size(logical.width * 3, logical.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  // 图标资产是真实位图 → 拦截加载，避免测试环境解码告警。
  const MethodChannel assets = MethodChannel('flutter/assets');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    assets,
    (MethodCall call) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(assets, null));
}

/// 起一张「已点我做到了、待家长确认」的成长卡（非联动项，requiresFocus=false）。
Future<void> _pumpPendingCard(
  WidgetTester tester, {
  required String taskName,
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
  final TaskLocalRepository repo =
      TaskLocalRepository(database, account: account);

  final Task task = Task(
    id: 't_long_status',
    name: taskName,
    subject: TaskSubject.general,
    requiresFocus: false,
    minFocusMin: 0,
    sunlightReward: 8,
    isCustom: true,
  );
  await repo.saveTask(task);

  final DateTime now = DateTime.now();
  await repo.checkIn(CheckIn(
    id: 'c_long_status',
    taskId: task.id,
    date: now,
    completedAt: now,
    sessionId: 's_long_status',
    isPerfectDay: false,
    status: CheckInStatus.pending,
    sunlightGross: 0,
    sunlightGranted: 0,
  ));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
        ],
      ),
      child: const MaterialApp(home: ChildTaskPage()),
    ),
  );
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppLocaleController.init(AppLanguage.system));

  group('F161 成长卡：状态胶囊限宽', () {
    testWidgets('英文 pending 胶囊不再把标题挤成逐字竖排', (WidgetTester tester) async {
      AppLocaleController.init(AppLanguage.en);
      _useScreen(tester, const Size(390, 844));
      await _pumpPendingCard(tester, taskName: 'Read for 20 minutes');

      expect(find.text('Waiting for approval'), findsOneWidget,
          reason: '先确认卡片确实进了「待家长确认」态（否则本用例测的不是目标分支）');

      final Size titleSize = tester.getSize(find.text('Read for 20 minutes'));
      expect(titleSize.width, greaterThanOrEqualTo(_kTitleMinWidth),
          reason: '标题宽度 ${titleSize.width}pt 过窄 → 长英文胶囊又把它压成一列竖字了。'
              '修复口径：胶囊宽度上限 = 屏宽 36%（见 _buildAction 的 capMax）');
    });

    testWidgets('中文 pending 胶囊照旧（不因限宽被截断或换行变形）',
        (WidgetTester tester) async {
      AppLocaleController.init(AppLanguage.zh);
      _useScreen(tester, const Size(390, 844));
      await _pumpPendingCard(tester, taskName: '朗读二十分钟');

      expect(find.text('等家长确认'), findsOneWidget,
          reason: '中文短文案本就放得下，限宽不许把它挤没');

      final Size titleSize = tester.getSize(find.text('朗读二十分钟'));
      expect(titleSize.width, greaterThanOrEqualTo(_kTitleMinWidth),
          reason: '中文环境标题也要有正常宽度');
    });

    testWidgets('平板宽屏：标题宽度不劣化（限宽在宽屏上不生效）',
        (WidgetTester tester) async {
      AppLocaleController.init(AppLanguage.en);
      _useScreen(tester, const Size(1024, 1366));
      await _pumpPendingCard(tester, taskName: 'Read for 20 minutes');

      expect(find.text('Waiting for approval'), findsOneWidget);
      final Size titleSize = tester.getSize(find.text('Read for 20 minutes'));
      expect(titleSize.width, greaterThanOrEqualTo(_kTitleMinWidth),
          reason: '平板屏宽够，本就无挤压；这里守的是限宽别把宽屏排版带坏');
    });
  });
}
