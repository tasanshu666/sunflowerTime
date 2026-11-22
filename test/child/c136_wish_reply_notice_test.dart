/// C136 需求 1（玄参 2026-11-25 真机反馈）：孩子端「愿望通知卡」裁剪到**家长回应**两条。
///
/// ## 玄参原话
/// 「愿望处理了之后，不管是放入愿望池还是收藏箱，这个卡片是干啥的？不需要吧，
/// 把这个卡片提醒机制删除吧」。
///
/// ## 拍板口径（主理人 AskUserQuestion 实答）
/// 只删**愿望状态类**通知（fulfilled / selfFulfilled / released / restored /
/// abandoned / committed / replaced / tagged / untagged / taskAssigned / goalSet），
/// 保留 `taskVerified`（家长确认你做到了）与 `taskRejected`（家长驳回任务）两条。
///
/// ## 本文件守什么
///  · ① kind → 文案映射是**单点纯函数**：只有两个 kind 有文案，其余一律 null（不弹卡）；
///  · ② 状态类事件**不弹卡**，但必须**写入已读**（否则每次首帧全表扫描 tracking events，
///    越用越慢）；
///  · ③ `taskVerified` / `taskRejected` 仍弹卡，且文案是**中文**（不再是英文枚举名）；
///  · ④ 混合场景只展示回应类明细；弹窗关闭后**本次扫到的全部**未读一起写已读。
///
/// 装配：真 in-memory drift 库 + mock SharedPreferences + 真 `ChildShellPage`，
/// 只覆盖基础设施三件套（其余 provider 走真实装配）。
library c136_wish_reply_notice_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/wish_l10n.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/tracking_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/wish_local_repository.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart';

/// 卡头标题（拍板文案「爸爸妈妈回应你啦」）。
const String _kReplyTitle = '爸爸妈妈回应你啦';

/// `taskVerified` 副标题（须体现「爸妈确认你做到了」）。
const String _kVerifiedCopy = '爸爸妈妈确认你做到啦';

/// `taskRejected` 副标题（须体现「需要重新做」）。
const String _kRejectedCopy = '爸爸妈妈说这个再试试';

/// 弹窗按钮（`shared_got_it`）。
const String _kGotIt = '知道啦';

/// 一条跨端事件的造法（`event_id` 用生产单点 helper 拼，期望值不自己编）。
TrackingEvent _event({
  required String wishId,
  required WishEventKind kind,
  required DateTime at,
}) {
  final String name = switch (kind) {
    WishEventKind.taskVerified => TrackingEventNames.wishTaskVerified,
    WishEventKind.taskRejected => TrackingEventNames.wishTaskRejected,
    WishEventKind.fulfilled ||
    WishEventKind.selfFulfilled =>
      TrackingEventNames.wishFulfilled,
    WishEventKind.abandoned => TrackingEventNames.wishAbandoned,
    WishEventKind.released || WishEventKind.restored =>
      TrackingEventNames.wishTreeOpen,
    _ => TrackingEventNames.wishParentAction,
  };
  return TrackingEvent(
    id: 'track_${wishId}_${kind.name}_${at.microsecondsSinceEpoch}',
    name: name,
    type: TrackingType.metric,
    ts: at,
    payload: <String, dynamic>{
      'wish_id': wishId,
      'kind': kind.name,
      'event_id': wishEventIdOf(wishId, kind.name, at.millisecondsSinceEpoch),
    },
  );
}

/// 一条树上愿望（默认挂在 slot 0，详情里才有「放进收藏箱」等入口）。
Wish _wish(String id, {int? treeSlot = 0}) => Wish(
      id: id,
      childId: kChildIdDefault,
      text: '想要一架小飞机',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      treeSlot: treeSlot,
    );

/// 装配孩子端外壳（既有 `task_verified_notice_test` 的同款装配）。
Future<ProviderContainer> _pumpShell(
  WidgetTester tester, {
  required SharedPreferences sp,
  required db.AppDatabase database,
}) async {
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
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChildShellPage()),
    ),
  );
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

/// 点「知道啦」并等弹窗关闭后的异步写回完成。
Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(find.text(_kGotIt));
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppLocaleController.init(AppLanguage.zh));
  tearDown(() => AppLocaleController.init(AppLanguage.system));

  group('① kind → 文案映射（单点纯函数，返回 null = 不弹卡）', () {
    final AppLocalizations t = AppLocalizationsZh();

    test('只有 taskVerified / taskRejected 有文案，且为中文回应口吻', () {
      expect(wishReplyNoticeSubtitleOf(WishEventKind.taskVerified.name, t),
          _kVerifiedCopy);
      expect(wishReplyNoticeSubtitleOf(WishEventKind.taskRejected.name, t),
          _kRejectedCopy);
      // 「再试试」= 需要重新做（家长驳回的任务要孩子再试一次）。
      expect(_kRejectedCopy, contains('再试试'));
      expect(_kVerifiedCopy, contains('确认'));
    });

    test('其余 11 种状态类事件一律 null（= 不弹卡）', () {
      final Set<String> replyKinds = <String>{
        WishEventKind.taskVerified.name,
        WishEventKind.taskRejected.name,
      };
      expect(replyKinds.length, 2);
      for (final WishEventKind kind in WishEventKind.values) {
        final String? copy = wishReplyNoticeSubtitleOf(kind.name, t);
        if (replyKinds.contains(kind.name)) {
          expect(copy, isNotNull, reason: '${kind.name} 必须保留');
        } else {
          expect(copy, isNull,
              reason: '${kind.name} 属状态类事件，玄参要求不再打扰孩子');
        }
      }
      // 13 种 kind 全覆盖（枚举没被悄悄加/删）。
      expect(WishEventKind.values.length, 13);
    });

    test('未知 kind（老数据 / 脏 payload）也不弹卡', () {
      expect(wishReplyNoticeSubtitleOf('legacyUnknownKind', t), isNull);
      expect(wishReplyNoticeSubtitleOf('', t), isNull);
    });

    test('en 侧文案齐备且零 CJK（切英文不回落中文，en_switch_guard 口径）',
        () {
      final AppLocalizations en = AppLocalizationsEn();
      final RegExp cjk = RegExp(
        r'[\u3000-\u303F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]',
      );
      for (final String copy in <String>[
        en.wishNoticeReplyTitle,
        en.wishNoticeTaskVerified,
        en.wishNoticeTaskRejected,
        en.wishParentFulfilledBadge,
      ]) {
        expect(copy.trim(), isNotEmpty);
        expect(cjk.hasMatch(copy), isFalse, reason: 'en 文案含 CJK：$copy');
      }
      // 英文侧映射同样只认这两个 kind。
      expect(wishReplyNoticeSubtitleOf(WishEventKind.taskVerified.name, en),
          en.wishNoticeTaskVerified);
      expect(wishReplyNoticeSubtitleOf(WishEventKind.released.name, en), isNull);
    });
  });

  group('② 状态类事件：不弹卡 + 写入已读', () {
    testWidgets('released 事件：卡片不出现，但事件被标记已读', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await WishLocalRepository(database).save(_wish('w_rel'));
      final TrackingEvent event = _event(
        wishId: 'w_rel',
        kind: WishEventKind.released,
        at: DateTime.now(),
      );
      await TrackingLocalRepository(database).track(event);

      await _pumpShell(tester, sp: sp, database: database);

      expect(find.byType(GoldNoticeDialog), findsNothing,
          reason: '「放进收藏箱」这类状态变化不该再弹卡（玄参需求 1）');
      expect(find.text(_kReplyTitle), findsNothing);

      final List<String> acked = await SettingsStore(sp)
          .acknowledgedWishEventIds(childId: kChildIdDefault);
      expect(acked, contains(event.payload['event_id'] as String),
          reason: '被过滤的事件也必须写已读，否则永远未读、每次首帧全表扫描');
    });

    testWidgets('11 种状态类事件全塞进去：依旧一张卡都不弹，且全部写已读',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await WishLocalRepository(database).save(_wish('w_all'));
      final TrackingLocalRepository tracking = TrackingLocalRepository(database);
      final List<WishEventKind> statusKinds = WishEventKind.values
          .where((WishEventKind k) =>
              k != WishEventKind.taskVerified &&
              k != WishEventKind.taskRejected)
          .toList();
      expect(statusKinds.length, 11);
      final List<String> ids = <String>[];
      for (int i = 0; i < statusKinds.length; i++) {
        final TrackingEvent e = _event(
          wishId: 'w_all',
          kind: statusKinds[i],
          at: DateTime.now().add(Duration(seconds: i)),
        );
        ids.add(e.payload['event_id'] as String);
        await tracking.track(e);
      }

      await _pumpShell(tester, sp: sp, database: database);

      expect(find.byType(GoldNoticeDialog), findsNothing);
      final List<String> acked = await SettingsStore(sp)
          .acknowledgedWishEventIds(childId: kChildIdDefault);
      for (final String id in ids) {
        expect(acked, contains(id), reason: '$id 未写已读');
      }
    });
  });

  group('③ 回应类事件：仍弹卡 + 中文文案', () {
    testWidgets('taskVerified：标题「爸爸妈妈回应你啦」+ 中文副标题（无英文枚举名）',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await WishLocalRepository(database).save(_wish('w_ver'));
      await TrackingLocalRepository(database).track(_event(
        wishId: 'w_ver',
        kind: WishEventKind.taskVerified,
        at: DateTime.now(),
      ));

      await _pumpShell(tester, sp: sp, database: database);

      expect(find.byType(GoldNoticeDialog), findsOneWidget,
          reason: '家长确认做到仍要告诉孩子');
      expect(find.text(_kReplyTitle), findsOneWidget);
      expect(find.text(_kVerifiedCopy), findsOneWidget);
      // 愿望原文作为明细主行（孩子知道是哪条愿望）。
      expect(find.text('想要一架小飞机'), findsOneWidget);
      // 玄参的原病灶：副标题曾直接打印英文枚举名。
      expect(find.text('taskVerified'), findsNothing,
          reason: '枚举名是孩子看不懂的根源，绝不能出现');
      // 旧标题（愿望的果实正在成长）不再用于本卡。
      expect(find.text(wishTextOf(WishTextKey.wishGrowing)), findsNothing);
    });

    testWidgets('taskRejected：仍弹卡，副标题要求「再试试」，关掉后写已读',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await WishLocalRepository(database).save(_wish('w_rej'));
      final TrackingEvent event = _event(
        wishId: 'w_rej',
        kind: WishEventKind.taskRejected,
        at: DateTime.now(),
      );
      await TrackingLocalRepository(database).track(event);

      await _pumpShell(tester, sp: sp, database: database);

      expect(find.byType(GoldNoticeDialog), findsOneWidget);
      expect(find.text(_kRejectedCopy), findsOneWidget);
      expect(find.text('taskRejected'), findsNothing);

      // 未看先读防线：弹窗还开着时不得写已读。
      expect(
          await SettingsStore(sp)
              .acknowledgedWishEventIds(childId: kChildIdDefault),
          isEmpty,
          reason: '弹窗未关闭前写已读会永久吞掉这条通知');

      await _tapConfirm(tester);
      expect(find.byType(GoldNoticeDialog), findsNothing);
      expect(
          await SettingsStore(sp)
              .acknowledgedWishEventIds(childId: kChildIdDefault),
          contains(event.payload['event_id'] as String));
    });
  });

  group('④ 混合场景：只展示回应类明细，全部未读一起写已读', () {
    testWidgets('released + taskVerified 同在：卡里只有 1 条明细，确认后两条都已读',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await WishLocalRepository(database).save(_wish('w_mix'));
      final TrackingLocalRepository tracking = TrackingLocalRepository(database);
      final TrackingEvent released = _event(
        wishId: 'w_mix',
        kind: WishEventKind.released,
        at: DateTime.now(),
      );
      final TrackingEvent verified = _event(
        wishId: 'w_mix',
        kind: WishEventKind.taskVerified,
        at: DateTime.now().add(const Duration(minutes: 1)),
      );
      await tracking.track(released);
      await tracking.track(verified);

      await _pumpShell(tester, sp: sp, database: database);

      expect(find.byType(GoldNoticeDialog), findsOneWidget);
      expect(find.text(_kVerifiedCopy), findsOneWidget);
      expect(find.text('released'), findsNothing);
      expect(find.text('w_mix'), findsNothing, reason: '不得露出内部 id');
      // 明细只有一条：愿望原文只出现一次（被裁掉的 released 不占行）。
      expect(find.text('想要一架小飞机'), findsOneWidget);

      await _tapConfirm(tester);
      final List<String> acked = await SettingsStore(sp)
          .acknowledgedWishEventIds(childId: kChildIdDefault);
      expect(acked, contains(released.payload['event_id'] as String));
      expect(acked, contains(verified.payload['event_id'] as String));
    });
  });
}
