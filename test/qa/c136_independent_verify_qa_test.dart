/// C136 独立验证（QA 严过关 / Edward，独立于工程师自测）。
///
/// ## 目的
/// 玄参 2026-11-25 真机 4 条反馈 + 拍板口径（需求 1 只删「愿望状态类」通知、
/// 保留 `taskVerified` / `taskRejected` 且中文化；需求 3 保留 🌟 并补 🤝 双轨）。
/// 本文件**不重跑工程师用例**，而是从需求原文出发另写一套探针，独立证明 6 条核心断言。
///
/// ## 与工程师用例刻意不同的取证手段（避免「假修」互相掩护）
///  · 事件不手搓 payload：一律走生产 `emitCrossEndEvent`（真 `_emit` + 真事件名映射
///    + 真 `wishEventIdOf`），期望的 eventId 从**库里读回**，不用公式现算；
///  · 宽度不只看常量：在**真实生产弹窗**里读 `SizedBox.width`（tight 证明），
///    并同时量树上详情卡仍是 420（未被顺手改掉）；
///  · 收藏箱失败路径用**真抛错的服务替身**（工程师只做了源码字符串守卫）；
///  · 双轨标识在**真实 drift 三来源数据**上端到端验（工程师只挂单 tile）；
///  · 零回归用**真数据触发的三条既有通知卡**证明，而不是只断言源码顺序。
library c136_independent_verify_qa_test;

import 'dart:io';

import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/wish_l10n.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart'
    show kGardenHelpDialogMaxWidth;
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_pool_tile.dart';

// ── 拍板文案（玄参口径，独立写死做取证；不 import 生产常量以免自证） ──────────
const String _kReplyTitle = '爸爸妈妈回应你啦';
const String _kVerifiedCopy = '爸爸妈妈确认你做到啦';
const String _kRejectedCopy = '爸爸妈妈说这个再试试';
const String _kSelfBadge = '我自己做到的';
const String _kParentBadge = '爸爸妈妈帮我做到的';
const String _kGotIt = '知道啦';

/// 只保留这两条「家长回应类」通知（拍板口径）。
const Set<WishEventKind> _kReplyKinds = <WishEventKind>{
  WishEventKind.taskVerified,
  WishEventKind.taskRejected,
};

/// 11 种「愿望状态类」通知 —— 玄参要求不再打扰孩子。
final List<WishEventKind> _statusKinds = WishEventKind.values
    .where((WishEventKind k) => !_kReplyKinds.contains(k))
    .toList();

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

/// 落库必失败的许愿编排替身（只用于「失败不能关卡」用例）。
///
/// 生产方式：继承真服务并只覆盖 [collectToBox] —— 依赖（仓储 / 埋点）全部是真装配，
/// 保证失败点落在「落库」这一步而不是别处。
class _FailingCollectService extends WishOrchestrationService {
  _FailingCollectService({
    required super.wishes,
    required super.wishTasks,
    required super.account,
    required super.tracking,
  });

  @override
  Future<Wish> collectToBox({required String id, required DateTime now}) async {
    throw StateError('qa-simulated-collect-failure');
  }
}

/// 真基础设施装配（内存 drift + mock SP + 真 AccountService），可选注入失败替身。
class _Ctx {
  _Ctx(this.database, this.sp, this.account, this.container);

  final db.AppDatabase database;
  final SharedPreferences sp;
  final AccountService account;
  final ProviderContainer container;

  WishOrchestrationService get service =>
      container.read(wishOrchestrationServiceProvider);

  SettingsStore get store => SettingsStore(sp);

  /// 从**库里读回**本次真实落库的 eventId（不用公式现算）。
  Future<List<String>> storedEventIds() async {
    final List<TrackingEvent> events = await container
        .read(trackingRepositoryProvider)
        .eventsOfType(TrackingType.metric);
    return events
        .map((TrackingEvent e) => e.payload['event_id'])
        .whereType<String>()
        .toList();
  }

  Future<List<String>> ackedWishEventIds() =>
      store.acknowledgedWishEventIds(childId: kChildIdDefault);
}

Future<_Ctx> _boot({bool failCollect = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();

  final List<Override> overrides = <Override>[
    sharedPreferencesProvider.overrideWithValue(sp),
    appDatabaseProvider.overrideWithValue(database),
    accountServiceProvider.overrideWithValue(account),
    iapServiceProvider.overrideWithValue(IapService(adapter: _OfflineIap())),
    settingsRepositoryProvider.overrideWithValue(_QuietSettings()),
  ];
  if (failCollect) {
    overrides.add(wishOrchestrationServiceProvider
        .overrideWith((Ref ref) {
      return _FailingCollectService(
        wishes: ref.watch(wishRepositoryProvider),
        wishTasks: ref.watch(wishTaskRepositoryProvider),
        account: ref.watch(accountServiceProvider),
        tracking: ref.watch(trackingRepositoryProvider),
      );
    }));
  }
  final ProviderContainer container =
      ProviderContainer(overrides: overrides);
  // LIFO：先 dispose 容器（让 provider 正常释放），再关库。
  addTearDown(database.close);
  addTearDown(container.dispose);
  return _Ctx(database, sp, account, container);
}

/// 固定视口挂孩子端外壳并等首帧通知检查跑完（有界帧，禁 pumpAndSettle）。
Future<void> _pumpShell(
  WidgetTester tester,
  _Ctx c, {
  Size viewport = const Size(390, 844),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c.container,
    child: const MaterialApp(home: ChildShellPage()),
  ));
  for (int i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 卸载外壳（下次 [_pumpShell] 即 remount ⇒ initState 重跑一遍通知检查）。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapGotIt(WidgetTester tester) async {
  await tester.tap(find.text(_kGotIt));
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 造一条挂在树上的愿望（`text` 互不相同，避开重复文案闸门）。
Future<Wish> _makeWish(_Ctx c, String text) => c.service.createWish(
      text: text,
      category: WishCategory.other,
      now: DateTime.now().subtract(const Duration(days: 2)),
      maxTextLength: kWishTextMaxLengthZh,
    );

/// 固定视口挂真 `WishTreePage` 并等异步数据就绪。
Future<void> _pumpTree(
  WidgetTester tester,
  _Ctx c, {
  required Size viewport,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c.container,
    child: const MaterialApp(home: WishTreePage()),
  ));
  for (int i = 0; i < 26; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// 页面上所有 Text 的字面量（用于「绝不出现英文枚举名」的整体取证）。
Set<String> _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text w) => w.data)
    .whereType<String>()
    .toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AudioService.instance.resetForTest());

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 1：通知裁剪真生效 —— 13 种 kind，11 种状态类一条都不弹卡
  // ═══════════════════════════════════════════════════════════════════════
  group('断言 1 · 状态类事件一条卡都不弹（逐 kind 独立取证）', () {
    test('枚举面：13 种 kind，回应类恰好 2 条、状态类恰好 11 条', () {
      expect(WishEventKind.values.length, 13);
      expect(_kReplyKinds.length, 2);
      expect(_statusKinds.length, 11);
      // 与玄参拍板口径逐字对齐：状态类就是这 11 个名字（不许悄悄改口径）。
      expect(
        _statusKinds.map((WishEventKind k) => k.name).toSet(),
        <String>{
          'fulfilled',
          'selfFulfilled',
          'released',
          'restored',
          'abandoned',
          'committed',
          'replaced',
          'tagged',
          'untagged',
          'taskAssigned',
          'goalSet',
        },
        reason: '拍板口径：11 种愿望状态类通知全部不再打扰孩子',
      );
      expect(_kReplyKinds.map((WishEventKind k) => k.name).toSet(),
          <String>{'taskVerified', 'taskRejected'},
          reason: '拍板口径：家长回应类两条必须保留');
    });

    for (final WishEventKind kind in _statusKinds) {
      testWidgets('${kind.name}：走生产 emitCrossEndEvent 也不弹卡',
          (WidgetTester tester) async {
        final _Ctx c = await _boot();
        final Wish w = await _makeWish(c, '想要一架小飞机');
        // 🔴 生产路径发事件（真 _emit / 真事件名 / 真 event_id）。
        await c.service.emitCrossEndEvent(
          wishId: w.id,
          kind: kind,
          now: DateTime.now(),
        );
        final List<String> ids = await c.storedEventIds();
        expect(ids.length, 1, reason: '事件必须真的落库，否则本用例是空转');

        await _pumpShell(tester, c);

        expect(find.byType(GoldNoticeDialog), findsNothing,
            reason: '${kind.name} 属「愿望状态类」，玄参要求不再弹卡');
        expect(find.text(_kReplyTitle), findsNothing);
        // 副标题绝不能是英文枚举名（原病灶）。
        expect(_visibleTexts(tester), isNot(contains(kind.name)));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('11 种状态类事件同时未读：一张卡都不弹', (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');
      final DateTime base = DateTime.now();
      for (int i = 0; i < _statusKinds.length; i++) {
        await c.service.emitCrossEndEvent(
          wishId: w.id,
          kind: _statusKinds[i],
          now: base.add(Duration(seconds: i)),
        );
      }
      expect((await c.storedEventIds()).length, 11);

      await _pumpShell(tester, c);

      expect(find.byType(GoldNoticeDialog), findsNothing);
      final Set<String> texts = _visibleTexts(tester);
      for (final WishEventKind kind in _statusKinds) {
        expect(texts, isNot(contains(kind.name)),
            reason: '英文枚举名 ${kind.name} 出现在孩子端页面上');
      }
    });
  });

  group('断言 1 · 保留的两条回应类：仍弹卡且副标题是中文', () {
    for (final (WishEventKind kind, String copy) in <(WishEventKind, String)>[
      (WishEventKind.taskVerified, _kVerifiedCopy),
      (WishEventKind.taskRejected, _kRejectedCopy),
    ]) {
      testWidgets('${kind.name}：弹 1 张卡，标题/副标题中文，无英文枚举名',
          (WidgetTester tester) async {
        final _Ctx c = await _boot();
        final Wish w = await _makeWish(c, '想要一架小飞机');
        await c.service.emitCrossEndEvent(
          wishId: w.id,
          kind: kind,
          now: DateTime.now(),
        );

        await _pumpShell(tester, c);

        expect(find.byType(GoldNoticeDialog), findsOneWidget,
            reason: '${kind.name} 是家长回应，必须告诉孩子');
        expect(find.text(_kReplyTitle), findsOneWidget);
        expect(find.text(copy), findsOneWidget);
        // 愿望原文作为明细主行：孩子知道是哪条愿望。
        expect(find.text('想要一架小飞机'), findsOneWidget);
        expect(_visibleTexts(tester), isNot(contains(kind.name)),
            reason: '副标题曾直接打印英文枚举名，这是玄参看不懂的根因');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('混合 11 状态 + 2 回应：只弹 1 张卡，明细恰好 2 行',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');
      final DateTime base = DateTime.now();
      int i = 0;
      for (final WishEventKind kind in <WishEventKind>[
        ..._statusKinds,
        WishEventKind.taskVerified,
        WishEventKind.taskRejected,
      ]) {
        await c.service.emitCrossEndEvent(
          wishId: w.id,
          kind: kind,
          now: base.add(Duration(seconds: i++)),
        );
      }

      await _pumpShell(tester, c);

      expect(find.byType(GoldNoticeDialog), findsOneWidget);
      expect(find.text(_kVerifiedCopy), findsOneWidget);
      expect(find.text(_kRejectedCopy), findsOneWidget);
      // 明细行数 = 愿望原文出现次数（被裁掉的 11 条不占行）。
      expect(find.text('想要一架小飞机'), findsNWidgets(2),
          reason: '只有 2 条回应类构成明细行');
      final Set<String> texts = _visibleTexts(tester);
      for (final WishEventKind kind in WishEventKind.values) {
        expect(texts, isNot(contains(kind.name)));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 2：被过滤的事件也写已读 + 原有时序语义（弹窗未关不写）
  // ═══════════════════════════════════════════════════════════════════════
  group('断言 2 · 被过滤的也写已读（性能正确性）', () {
    testWidgets('只有状态类未读：不弹卡，但 11 个 eventId 全部写已读',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');
      final DateTime base = DateTime.now();
      for (int i = 0; i < _statusKinds.length; i++) {
        await c.service.emitCrossEndEvent(
          wishId: w.id,
          kind: _statusKinds[i],
          now: base.add(Duration(seconds: i)),
        );
      }
      final List<String> stored = await c.storedEventIds();
      expect(stored.length, 11);

      await _pumpShell(tester, c);

      expect(find.byType(GoldNoticeDialog), findsNothing);
      final List<String> acked = await c.ackedWishEventIds();
      for (final String id in stored) {
        expect(acked, contains(id),
            reason: '被裁掉的通知不弹卡，但绝不能滞留未读集合'
                '（否则每次首帧全表扫描 tracking events，越用越慢）');
      }
      expect(acked.length, greaterThanOrEqualTo(11));
    });

    testWidgets('弹窗关着时才写：混合场景开着时 acked 为空，关后含被过滤项',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');
      final DateTime base = DateTime.now();
      await c.service.emitCrossEndEvent(
        wishId: w.id,
        kind: WishEventKind.released,
        now: base,
      );
      await c.service.emitCrossEndEvent(
        wishId: w.id,
        kind: WishEventKind.taskVerified,
        now: base.add(const Duration(minutes: 1)),
      );
      final List<String> stored = await c.storedEventIds();
      expect(stored.length, 2);

      await _pumpShell(tester, c);

      expect(find.byType(GoldNoticeDialog), findsOneWidget);
      expect(find.text(_kVerifiedCopy), findsOneWidget);
      expect(find.text('想要一架小飞机'), findsOneWidget,
          reason: 'released 被裁掉，不占明细行');
      expect(await c.ackedWishEventIds(), isEmpty,
          reason: '「未看先读」会永久吞掉通知：弹窗还开着时一条都不能写');

      await _tapGotIt(tester);

      expect(find.byType(GoldNoticeDialog), findsNothing);
      final List<String> acked = await c.ackedWishEventIds();
      for (final String id in stored) {
        expect(acked, contains(id),
            reason: '混合场景关闭后，含被过滤的 released 也必须一起写已读');
      }
    });

    testWidgets('全量混合（11 状态 + 2 回应）：弹 1 张卡含 2 条，关闭后 13 条全部已读',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');
      final DateTime base = DateTime.now();
      int i = 0;
      for (final WishEventKind kind in <WishEventKind>[
        ..._statusKinds,
        WishEventKind.taskVerified,
        WishEventKind.taskRejected,
      ]) {
        await c.service.emitCrossEndEvent(
          wishId: w.id,
          kind: kind,
          now: base.add(Duration(seconds: i++)),
        );
      }
      final List<String> stored = await c.storedEventIds();
      expect(stored.length, 13, reason: '13 条事件必须真的落库');

      await _pumpShell(tester, c);

      expect(find.byType(GoldNoticeDialog), findsOneWidget);
      expect(find.text('想要一架小飞机'), findsNWidgets(2),
          reason: '明细 2 条（taskVerified + taskRejected），11 条状态类被裁掉');
      expect(await c.ackedWishEventIds(), isEmpty,
          reason: '弹窗还开着时一条都不能写（未看先读会吞通知）');

      await _tapGotIt(tester);

      final List<String> acked = await c.ackedWishEventIds();
      for (final String id in stored) {
        expect(acked, contains(id), reason: '$id 未写已读');
      }
      expect(acked.toSet().length, greaterThanOrEqualTo(13),
          reason: '本次扫到的 13 条（含 11 条被过滤的）必须一次全部写已读');
    });

    testWidgets('写已读后重进孩子端：不再弹卡（幂等，不重复打扰）',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');
      final DateTime base = DateTime.now();
      await c.service.emitCrossEndEvent(
        wishId: w.id,
        kind: WishEventKind.released,
        now: base,
      );
      await c.service.emitCrossEndEvent(
        wishId: w.id,
        kind: WishEventKind.fulfilled,
        now: base.add(const Duration(seconds: 1)),
      );

      await _pumpShell(tester, c);
      expect(find.byType(GoldNoticeDialog), findsNothing);
      final List<String> firstAck = await c.ackedWishEventIds();
      expect(firstAck.length, 2);

      await _unmount(tester);
      await _pumpShell(tester, c);
      expect(find.byType(GoldNoticeDialog), findsNothing);
      expect((await c.ackedWishEventIds()).toSet(), firstAck.toSet(),
          reason: '已读集合只增不重写，二次进入不再打扰');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 3：弹窗宽度真变宽 + 手机零变化 + tight 约束 + 详情卡 420 未动
  // ═══════════════════════════════════════════════════════════════════════
  group('断言 3 · wishListDialogWidth 真值表', () {
    test('iPhone 视口：逐点等于旧实现「视口 − 48」，且都 < 420', () {
      expect(wishListDialogWidth(390), 342.0, reason: 'iPhone 14');
      expect(wishListDialogWidth(393), 345.0);
      expect(wishListDialogWidth(428), 380.0, reason: 'iPhone Pro Max');
      expect(wishListDialogWidth(390), lessThan(420.0),
          reason: '手机上旧 maxWidth 420 本就不生效 ⇒ 观感零变化');
    });

    test('iPad 视口：封顶 600（玄参要的「别那么窄」）', () {
      expect(wishListDialogWidth(834), 600.0, reason: 'iPad 11 英寸');
      expect(wishListDialogWidth(1032), 600.0, reason: 'iPad 13 英寸');
      expect(wishListDialogWidth(1194), 600.0, reason: 'iPad 横屏');
      expect(wishListDialogWidth(834), greaterThan(420.0),
          reason: '必须明显宽于旧的硬编码 420，否则就是没修');
    });

    test('临界点与单调性：647→599 / 648→600，随视口单调不减', () {
      expect(wishListDialogWidth(647), 599.0);
      expect(wishListDialogWidth(648), 600.0);
      double prev = -1;
      for (double w = 0; w <= 1200; w += 25) {
        final double got = wishListDialogWidth(w);
        expect(got, greaterThanOrEqualTo(prev));
        expect(got, lessThanOrEqualTo(kGardenHelpDialogMaxWidth));
        prev = got;
      }
    });

    test('上限复用 kGardenHelpDialogMaxWidth（不另造孪生 600）', () {
      expect(kGardenHelpDialogMaxWidth, 600.0);
      expect(wishListDialogWidth(5000), kGardenHelpDialogMaxWidth);
    });

    test('极端窄视口钳到 0，绝不返回负宽（SizedBox 传负宽会崩）', () {
      expect(wishListDialogWidth(48), 0.0);
      expect(wishListDialogWidth(0), 0.0);
      expect(wishListDialogWidth(-100), 0.0);
    });
  });

  group('断言 3 · 真实生产弹窗（宽度 + tight 约束）', () {
    testWidgets('iPad 834 愿望池：容器宽 600，且外层 SizedBox.width 也是 600（tight）',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');
      await c.service.putIntoPool(id: w.id, now: DateTime.now());

      await _pumpTree(tester, c, viewport: const Size(834, 1194));
      await tester.tap(find.byKey(const Key('wish_scene_pool_button')));
      await _settle(tester);

      final Finder dialog = find.byKey(const Key('wish_pool_dialog'));
      expect(dialog, findsOneWidget, reason: '点「愿望池」必须弹出居中卡片');
      expect(tester.getSize(dialog).width, 600.0,
          reason: 'iPad 上按屏宽定宽，而不是内容固有宽或硬编码 420');

      // 🔴 tight 证明：只量宽不足以区分 SizedBox(width:) 与 ConstrainedBox(maxWidth)。
      // 本弹窗内容是 SingleChildScrollView + Column(min)，松约束时会收缩到内容宽。
      final Finder boxFinder =
          find.ancestor(of: dialog, matching: find.byType(SizedBox)).first;
      final SizedBox box = tester.widget<SizedBox>(boxFinder);
      expect(box.width, 600.0,
          reason: '必须是 SizedBox(width:) 的 tight 约束（maxWidth 是玄参这次'
              '「还是窄」的根因，改常量到 600 也是假修）');
      expect(tester.getSize(boxFinder).width, 600.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPad 1032 收藏箱：同样 600（不是只有池弹窗改了）',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');
      await c.service.collectToBox(id: w.id, now: DateTime.now());

      await _pumpTree(tester, c, viewport: const Size(1032, 1376));
      await tester.tap(find.byKey(const Key('wish_scene_box_button')));
      await _settle(tester);

      final Finder dialog = find.byKey(const Key('wish_box_dialog'));
      expect(dialog, findsOneWidget);
      expect(tester.getSize(dialog).width, 600.0, reason: 'iPad 13 英寸');
      final SizedBox box = tester.widget<SizedBox>(
          find.ancestor(of: dialog, matching: find.byType(SizedBox)).first);
      expect(box.width, 600.0);
    });

    testWidgets('iPhone 390 愿望池：342（手机零变化）', (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');
      await c.service.putIntoPool(id: w.id, now: DateTime.now());

      await _pumpTree(tester, c, viewport: const Size(390, 844));
      await tester.tap(find.byKey(const Key('wish_scene_pool_button')));
      await _settle(tester);

      final Finder dialog = find.byKey(const Key('wish_pool_dialog'));
      expect(dialog, findsOneWidget);
      expect(tester.getSize(dialog).width, 342.0,
          reason: '390 − 48 = 342，手机端逐点与旧实现一致');
      expect(tester.takeException(), isNull);
    });

    testWidgets('树上愿望详情卡：iPad 上仍是 420（玄参没要求改，不能被顺手改掉）',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一架小飞机');

      await _pumpTree(tester, c, viewport: const Size(834, 1194));
      final Finder card = find.byKey(Key('wish_card_${w.id}'));
      expect(card, findsOneWidget);
      await tester.tap(card);
      await _settle(tester, frames: 16);

      final Finder detail = find.byKey(kWishDetailDialogKey);
      expect(detail, findsOneWidget);
      expect(tester.getSize(detail).width, 420.0,
          reason: '需求 2 只针对池 / 箱弹窗；树上详情卡保持 420');
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 4：池卡双轨来源标识（🌟 / 🤝 互补，每卡有且仅有一个）
  // ═══════════════════════════════════════════════════════════════════════
  group('断言 4 · 判据互补（穷举全部来源）', () {
    Wish poolWish(String id, String? source) => Wish(
          id: id,
          childId: kChildIdDefault,
          text: '想要一架小飞机',
          status: WishStatus.fulfilled,
          createdAt: DateTime.now().subtract(const Duration(days: 6)),
          fulfilledAt: DateTime.now().subtract(const Duration(days: 1)),
          fulfillSource: source,
        );

    test('child 是自己做到；progress / parentAction / null 都是家长助力',
        () {
      const List<String?> allSources = <String?>[
        kWishFulfillSourceChild,
        kWishFulfillSourceProgress,
        kWishFulfillSourceParentAction,
        null,
      ];
      for (final String? source in allSources) {
        final Wish w = poolWish('x', source);
        final bool self = WishPoolTile.isSelfFulfilled(w);
        final bool parent = WishPoolTile.isParentHelped(w);
        expect(self, source == kWishFulfillSourceChild, reason: 'source=$source');
        expect(parent, !self, reason: '双轨必须互补，source=$source 不能两轨都不是');
      }
    });

    testWidgets('每种来源都恰好 1 个标识，且 key / emoji / 语义文案对得上',
        (WidgetTester tester) async {
      const Map<String?, (String, String, String)> expected =
          <String?, (String, String, String)>{
        kWishFulfillSourceChild: ('wish_pool_self_badge', '🌟', _kSelfBadge),
        kWishFulfillSourceProgress: (
          'wish_pool_parent_badge',
          '🤝',
          _kParentBadge
        ),
        kWishFulfillSourceParentAction: (
          'wish_pool_parent_badge',
          '🤝',
          _kParentBadge
        ),
        null: ('wish_pool_parent_badge', '🤝', _kParentBadge),
      };

      for (final MapEntry<String?, (String, String, String)> e
          in expected.entries) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 342,
                child: WishPoolTile(
                  wish: poolWish('w_${e.key ?? 'legacy'}', e.key),
                  t: AppLocalizationsZh(),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();

        final (String key, String emoji, String label) = e.value;
        final Finder badge = find.byKey(Key(key));
        expect(badge, findsOneWidget, reason: 'source=${e.key} 缺标识');
        expect(tester.widget<Text>(badge).data, emoji);
        // 互补轨不出现：每卡有且仅有 1 个标识。
        expect(find.byKey(const Key('wish_pool_self_badge')).evaluate().length +
            find.byKey(const Key('wish_pool_parent_badge')).evaluate().length, 1,
            reason: 'source=${e.key} 出现了多个/零个标识');
        expect(
          tester
              .widgetList<Semantics>(find.ancestor(
                  of: badge, matching: find.byType(Semantics)))
              .any((Semantics s) => s.properties.label == label),
          isTrue,
          reason: '只挂 emoji 孩子读不懂 —— 玄参这次问的正是「小星星是干啥的」',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('真实 drift 三来源端到端：池弹窗里 1 个 🌟 + 2 个 🤝（3 卡 3 标识）',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      // ① 孩子自己点「实现了」→ source=child
      final Wish viaChild = await _makeWish(c, '想要一架小飞机');
      await c.service.selfFulfill(id: viaChild.id, now: DateTime.now());
      // ② 家长直接实现 → source=parentAction
      final Wish viaParent = await _makeWish(c, '想要一只小乌龟');
      await c.service.fulfill(id: viaParent.id, now: DateTime.now());
      // ③ 走成长任务/显式进池 → source=progress
      final Wish viaProgress = await _makeWish(c, '想要一本绘本');
      await c.service.putIntoPool(id: viaProgress.id, now: DateTime.now());

      // 真库核对三来源（先证明夹具正确，再看 UI）。
      final Map<String, String?> sources = <String, String?>{
        for (final Wish w in await c.service.poolWishes()) w.id: w.fulfillSource,
      };
      expect(sources.length, 3, reason: '三个愿望都必须真的在愿望池');
      expect(sources[viaChild.id], kWishFulfillSourceChild);
      expect(sources[viaParent.id], kWishFulfillSourceParentAction);
      expect(sources[viaProgress.id], kWishFulfillSourceProgress);

      await _pumpTree(tester, c, viewport: const Size(834, 1194));
      await tester.tap(find.byKey(const Key('wish_scene_pool_button')));
      await _settle(tester);

      expect(find.byKey(const Key('wish_pool_dialog')), findsOneWidget);
      expect(find.byKey(const Key('wish_pool_self_badge')), findsOneWidget,
          reason: '「想要小飞机」这条是孩子自己做到的 ⇒ 🌟');
      expect(find.byKey(const Key('wish_pool_parent_badge')), findsNWidgets(2),
          reason: '另外两条是家长助力 ⇒ 🤝（玄参：不能有的卡有星有的没有）');
      // 每张池卡都有且仅有 1 个标识。
      expect(
        find.byKey(const Key('wish_pool_self_badge')).evaluate().length +
            find.byKey(const Key('wish_pool_parent_badge')).evaluate().length,
        find.byKey(const Key('wish_pool_text')).evaluate().length,
        reason: '标识数必须等于池卡数（不许出现无标识的卡）',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 5：放进收藏箱后详情卡自动关闭；落库失败不关
  // ═══════════════════════════════════════════════════════════════════════
  group('断言 5 · 收藏箱后自动关卡', () {
    testWidgets('落库成功：卡片消失、愿望真进收藏箱、树上入口一并消失',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final Wish w = await _makeWish(c, '想要一只小乌龟');
      expect(await c.service.boxedWishes(), isEmpty);

      await _pumpTree(tester, c, viewport: const Size(390, 844));
      final Finder card = find.byKey(Key('wish_card_${w.id}'));
      expect(card, findsOneWidget);
      await tester.tap(card);
      await _settle(tester, frames: 16);

      expect(find.byKey(kWishDetailDialogKey), findsOneWidget);
      // 收进箱前的树上入口确实在（对照既有行为）。
      expect(find.byKey(const Key('wish_detail_change')), findsOneWidget);
      expect(find.byKey(const Key('wish_detail_collect')), findsOneWidget);

      await tester.tap(find.byKey(const Key('wish_detail_collect')));
      await _settle(tester);

      expect(find.byKey(kWishDetailDialogKey), findsNothing,
          reason: '落库成功后详情卡必须自动消失（玄参需求 4）');
      expect(find.byKey(const Key('wish_detail_change')), findsNothing,
          reason: '箱里的愿望不能再「换个愿望」');
      expect(find.byKey(const Key('wish_detail_self_fulfill')), findsNothing,
          reason: '箱里的愿望不能再「实现了」，只能取回');
      final List<Wish> boxed = await c.service.boxedWishes();
      expect(boxed.map((Wish x) => x.id).toList(), <String>[w.id],
          reason: '必须真的落库进收藏箱，而不是只关卡片');
      expect(tester.takeException(), isNull);
    });

    testWidgets('落库失败：详情卡必须留在原地（不许误关）',
        (WidgetTester tester) async {
      final _Ctx c = await _boot(failCollect: true);
      final Wish w = await _makeWish(c, '想要一只小乌龟');

      await _pumpTree(tester, c, viewport: const Size(390, 844));
      await tester.tap(find.byKey(Key('wish_card_${w.id}')));
      await _settle(tester, frames: 16);
      expect(find.byKey(kWishDetailDialogKey), findsOneWidget);

      await tester.tap(find.byKey(const Key('wish_detail_collect')));
      await _settle(tester);

      expect(find.byKey(kWishDetailDialogKey), findsOneWidget,
          reason: '落库抛错时关掉卡片＝孩子以为成功了，实际没进箱');
      expect(find.byKey(const Key('wish_detail_collect')), findsOneWidget,
          reason: '失败后按钮仍在，孩子可重试');
      expect(await c.service.boxedWishes(), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 6：零回归（既有三条通知 / 果实文案 / DB schema）
  // ═══════════════════════════════════════════════════════════════════════
  group('断言 6 · 既有三条通知行为不变（真数据触发）', () {
    /// 造一条已核销 / 已拒绝的兑换申请（真仓储落库）。
    Future<void> seedRequest(
      _Ctx c,
      String id,
      RequestStatus status,
    ) async {
      final RewardLocalRepository repo =
          RewardLocalRepository(c.database, account: c.account);
      final DateTime now = DateTime.now();
      await repo.createRequest(RedemptionRequest(
        id: id,
        childId: kChildIdDefault,
        templateId: 'tpl_$id',
        requestedAt: now.subtract(const Duration(hours: 2)),
        cost: 10,
      ));
      await repo.updateRequest(RedemptionRequest(
        id: id,
        childId: kChildIdDefault,
        templateId: 'tpl_$id',
        requestedAt: now.subtract(const Duration(hours: 2)),
        cost: 10,
        status: status,
        verifiedAt: status == RequestStatus.verified ? now : null,
        parentNote: status == RequestStatus.rejected ? '阳光还不够哦' : null,
      ));
    }

    testWidgets('兑换核销卡（M2）仍弹：标题「🎉 家长已确认你的兑换」',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      await seedRequest(c, 'r_ok', RequestStatus.verified);

      await _pumpShell(tester, c);

      expect(find.text('🎉 家长已确认你的兑换'), findsOneWidget,
          reason: '既有兑换核销通知行为必须一字不变（C136 只裁许愿树卡）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('兑换拒绝卡（B4）仍弹：标题「🚫 兑换未被通过」+ 家长备注',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      await seedRequest(c, 'r_no', RequestStatus.rejected);

      await _pumpShell(tester, c);

      expect(find.text('🚫 兑换未被通过'), findsOneWidget,
          reason: '既有兑换拒绝通知行为必须一字不变');
      expect(tester.takeException(), isNull);
    });

    testWidgets('任务审批卡（F126）仍弹：标题「🎉 家长已确认你的成长任务」',
        (WidgetTester tester) async {
      final _Ctx c = await _boot();
      final TaskLocalRepository tasks =
          TaskLocalRepository(c.database, account: c.account);
      await tasks.saveTask(const Task(
        id: 't_a',
        name: '朗读英语',
        subject: TaskSubject.general,
        requiresFocus: false,
        minFocusMin: 15,
        sunlightReward: 12,
        isCustom: true,
      ));
      final DateTime now = DateTime.now();
      await tasks.checkIn(CheckIn(
        id: 'c_a',
        taskId: 't_a',
        date: now,
        completedAt: now.subtract(const Duration(hours: 3)),
        isPerfectDay: false,
        status: CheckInStatus.verified,
        sunlightGross: 12,
        sunlightGranted: 12,
        resolvedAt: now.subtract(const Duration(hours: 1)),
      ));

      await _pumpShell(tester, c);

      expect(find.text('🎉 家长已确认你的成长任务'), findsOneWidget,
          reason: '既有任务审批通知行为必须一字不变');
      expect(find.text('朗读英语'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('断言 6 · 文案 / schema 零回归', () {
    test('wishFruitGrowing 未被删：果实阶段文案仍在（wish_card.dart 在用）', () {
      final AppLocalizationsZh zh = AppLocalizationsZh();
      expect(zh.wishFruitGrowing, '愿望的果实正在成长');
      expect(wishTextOf(WishTextKey.wishGrowing), zh.wishFruitGrowing);
      final String cardSrc =
          File('lib/presentation/child/widgets/wish_card.dart')
              .readAsStringSync();
      expect(cardSrc.contains('WishFruitStage.growing => t.wishFruitGrowing'),
          isTrue,
          reason: '需求 1 只删「通知卡」，果实阶段展示不许被连带删掉');
      // 通知卡标题换新了，但旧文案常量本身仍存在（果实阶段独占）。
      final String shellSrc =
          File('lib/presentation/child/pages/child_shell_page.dart')
              .readAsStringSync();
      expect(shellSrc.contains('WishTextKey.wishGrowing'), isTrue,
          reason: '愿望原文缺失时仍用该文案兜底明细主行');
    });

    test('DB schema 未动：schemaVersion 32 / wishes 22 列 / WishStatus 6 态', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      expect(database.schemaVersion, 32, reason: 'C136 是纯 UI 裁剪，不许动库版本');

      final List<QueryRow> rows =
          await database.customSelect('PRAGMA table_info(wishes)').get();
      final List<String> columns = rows
          .map((QueryRow r) => r.data['name'] as String)
          .toList()
        ..sort();
      expect(columns.length, 22, reason: 'Wish 仍是 22 字段 / 22 列');
      for (final String col in <String>[
        'fulfill_source',
        'released_at',
        'progress_value',
        'target_value',
        'target_mode',
      ]) {
        expect(columns, contains(col));
      }
      // 不许新增 C136 相关列（需求 1/3/4 全是展示层裁剪）。
      for (final String col in columns) {
        expect(col.toLowerCase().contains('notice'), isFalse,
            reason: '新增了通知相关列：$col');
      }
      expect(WishStatus.values.length, 6, reason: 'WishStatus 6 态 index 不变');
    });
  });
}
