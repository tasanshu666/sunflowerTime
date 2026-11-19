/// QA 独立差分复验 · v0.3 许愿弹层（居中 Dialog + 字数双阈值）。
///
/// ## 覆盖 PRD R3-P0-02 / R3-P0-04 / R3-P0-03
///  - **居中**（玄参反馈 2「在中间显示，不要在下面」）⇒ 量 `Dialog` 卡片矩形，
///    水平居中偏差 ≤ 24dp、底边距 ≥ 80dp；
///  - **高度 ≤ 屏高 85%** + 内容超高**内部滚动**；
///  - **键盘弹起**时卡片整体在可视区内（`viewInsets` 避让）；
///  - **字数双阈值**：zh 100 / en 300，counter 与本地校验**同源**；
///  - 超长**不关闭**弹层（草稿保留），且**不落库**；
///  - 域层 `createWish(maxTextLength:)` 的入参**真的生效**（不是写死 100）。
///
/// ## 反假绿要点
/// ① 「101 被拦」不能只看 counter 颜色 —— 必须断言**弹层仍在 + 无返回值 + DB 无新行**；
/// ② 「en 300 生效」不能只看常量 —— 必须走**真实 createWish** 用 101 字在 en 档
///    通过、在 zh 档被拒（同一段文本、同一函数，只换入参）。
library wish_compose_v03_qa_test;

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
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_compose_dialog.dart';

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

/// 真实 DI（内存库 + 真实服务图），供 `createWish` 用。
Future<ProviderContainer> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
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
      iapServiceProvider.overrideWithValue(IapService(adapter: _OfflineIap())),
      settingsRepositoryProvider.overrideWithValue(_QuietSettings()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(database.close);
  return container;
}

/// 打开弹层的宿主：按钮 → `showWishComposeDialog`，把结果与"是否仍打开"暴露出来。
class _ComposeHost extends StatefulWidget {
  const _ComposeHost({
    required this.l10n,
    required this.maxTextLength,
  });

  final AppLocalizations l10n;
  final int maxTextLength;

  @override
  State<_ComposeHost> createState() => _ComposeHostState();
}

class _ComposeHostState extends State<_ComposeHost> {
  WishComposeResult? _result;
  bool _returned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          TextButton(
            key: const Key('open_compose'),
            onPressed: () async {
              final WishComposeResult? r = await showWishComposeDialog(
                context: context,
                l10n: widget.l10n,
                maxTextLength: widget.maxTextLength,
              );
              if (!mounted) return;
              setState(() {
                _result = r;
                _returned = true;
              });
            },
            child: const Text('open'),
          ),
          Text(
            _returned ? 'RETURNED:${_result?.text ?? "null"}' : 'PENDING',
            key: const Key('host_result'),
          ),
        ],
      ),
    );
  }
}

Future<void> _open(WidgetTester tester, _ComposeHost host) async {
  // ⚠️ `MaterialApp` 给 `UniqueKey()` 是必要的：同一用例里第二次 `_open` 时，
  // 若元素被复用，`showDialog` 推在上一个 Navigator 上的路由**不会消失**，
  // 于是「重新打开」实际是叠了一层旧弹层（假象：新入参没生效）。
  await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: host));
  await tester.pump();
  await tester.tap(find.byKey(const Key('open_compose')));
  await tester.pumpAndSettle();
}

/// 输入指定码点长度的文本（用 ASCII 'a' 保证 1 码点 = 1 code unit，排除 emoji 干扰；
/// emoji 口径另有一条专门用例）。
Future<void> _enterChars(WidgetTester tester, int count) async {
  await tester.enterText(
    find.byKey(const Key('wish_compose_field')),
    'a' * count,
  );
  await tester.pump();
}

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  group('④ 字数双阈值 —— zh 100 / en 300（widget 层真交互）', () {
    testWidgets('zh 恰好 100 字：counter 显示 100/100、可提交、弹层关闭',
        (WidgetTester tester) async {
      await _open(
        tester,
        _ComposeHost(l10n: zh, maxTextLength: wishMaxTextLength('zh')),
      );
      await _enterChars(tester, 100);

      expect(find.text('100/100'), findsOneWidget,
          reason: 'counter 必须显示 100/100（上限来自 maxTextLength 入参）');
      // 未超限 ⇒ 无错误提示。
      expect(find.text(zh.wishComposeTooLong), findsNothing);

      await tester.tap(find.byKey(const Key('wish_compose_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsNothing,
          reason: '刚好 100 字必须放行并关闭');
      expect(find.text('RETURNED:${'a' * 100}'), findsOneWidget);
    });

    testWidgets('🔴 zh 101 字：counter 显示 101/100、拦截、弹层**不关闭**、草稿仍在',
        (WidgetTester tester) async {
      await _open(
        tester,
        _ComposeHost(l10n: zh, maxTextLength: wishMaxTextLength('zh')),
      );
      await _enterChars(tester, 101);

      expect(find.text('101/100'), findsOneWidget,
          reason: 'counter 与校验同源 ⇒ 必须显示 101/100');
      expect(find.text(zh.wishComposeTooLong), findsOneWidget,
          reason: '超长必须给出可见错误文案');

      await tester.tap(find.byKey(const Key('wish_compose_submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(kWishComposeDialogKey), findsOneWidget,
          reason: '超长时弹层必须留在原地（草稿不能丢）');
      expect(find.text('PENDING'), findsOneWidget,
          reason: '被拦截 ⇒ 不得返回任何结果给调用方');
      // 草稿仍在输入框里（R3-P0-04③）。
      expect(
        (tester.widget<TextField>(
          find.byKey(const Key('wish_compose_field')),
        )).controller!.text,
        'a' * 101,
        reason: '超长后草稿必须原样保留',
      );
    });

    testWidgets('en 恰好 300 字放行 / 301 字拦截（en 档位真的 300 不是 100）',
        (WidgetTester tester) async {
      await _open(
        tester,
        _ComposeHost(l10n: en, maxTextLength: wishMaxTextLength('en')),
      );

      // 先证「300 也放行」——这一条就足以证明 en 不是 100。
      await _enterChars(tester, 300);
      expect(find.text('300/300'), findsOneWidget,
          reason: 'en 档 counter 上限必须是 300');
      expect(find.text(en.wishComposeTooLong), findsNothing);
      await tester.tap(find.byKey(const Key('wish_compose_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsNothing,
          reason: 'en 300 字必须放行');

      // 再证 301 被拦。
      await _open(
        tester,
        _ComposeHost(l10n: en, maxTextLength: wishMaxTextLength('en')),
      );
      await _enterChars(tester, 301);
      expect(find.text('301/300'), findsOneWidget);
      expect(find.text(en.wishComposeTooLong), findsOneWidget);
      await tester.tap(find.byKey(const Key('wish_compose_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsOneWidget,
          reason: 'en 301 字必须被拦');
    });

    testWidgets('同一段 101 字文本：zh 档被拒、en 档放行（证明上限来自入参而非写死）',
        (WidgetTester tester) async {
      final String text = 'a' * 101; // 与 _enterChars 实际输入保持一致
      // zh 档：101 > 100 ⇒ 拦。
      await _open(
        tester,
        _ComposeHost(l10n: zh, maxTextLength: wishMaxTextLength('zh')),
      );
      await _enterChars(tester, 101);
      await tester.tap(find.byKey(const Key('wish_compose_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsOneWidget,
          reason: 'zh 档 101 字必须被拦（上限 100）');

      // en 档：101 <= 300 ⇒ 放行，且返回的就是这 101 字。
      await _open(
        tester,
        _ComposeHost(l10n: en, maxTextLength: wishMaxTextLength('en')),
      );
      await _enterChars(tester, 101);
      await tester.tap(find.byKey(const Key('wish_compose_submit')));
      await tester.pumpAndSettle();
      final String hostResult = tester
              .widget<Text>(find.byKey(const Key('host_result')))
              .data ??
          '';
      expect(hostResult, 'RETURNED:$text',
          reason: 'en 档 101 字必须放行 ⇒ 上限确实取自 maxTextLength 入参；'
              '实际 host 状态：$hostResult');
      expect(find.byKey(kWishComposeDialogKey), findsNothing,
          reason: '放行后弹层必须关闭');
    });

    test('字数按 Unicode 码点计（emoji 算 1，不是 2）', () {
      expect(wishTextRuneCount('🌻'), 1,
          reason: 'emoji 在 UTF-16 里 2 个 code unit，但长度口径必须是 1');
      expect('🌻'.length, 2, reason: '前置自证：String.length 会算成 2（这就是坑）');
      expect(wishTextRuneCount('🌻🌻🌻'), 3);
      expect(wishTextRuneCount('abc'), 3);
      expect(wishTextRuneCount(''), 0);
    });

    testWidgets('100 个 emoji 不被误判超长（码点口径在真实交互里也成立）',
        (WidgetTester tester) async {
      await _open(
        tester,
        _ComposeHost(l10n: zh, maxTextLength: wishMaxTextLength('zh')),
      );
      await tester.enterText(
        find.byKey(const Key('wish_compose_field')),
        '🌻' * 100,
      );
      await tester.pump();
      expect(find.text('100/100'), findsOneWidget,
          reason: '100 个 emoji 的码点数是 100，不是 200');
      expect(find.text(zh.wishComposeTooLong), findsNothing);
    });
  });

  group('④ 域层 createWish(maxTextLength:) 入参真的生效', () {
    test('101 字：maxTextLength=100 抛、maxTextLength=300 通过', () async {
      final ProviderContainer c = await _boot();
      final String text = 'c' * 101;
      Object? zhError;
      try {
        await c.read(wishOrchestrationServiceProvider).createWish(
              text: text,
              category: WishCategory.other,
              now: DateTime(2026, 11, 20, 9),
              maxTextLength: kWishTextMaxLengthZh,
            );
      } catch (e) {
        zhError = e;
      }
      expect(zhError, isNotNull,
          reason: 'zh 档（100）下 101 字必须被域层拒绝 —— 不能只靠 UI 拦');

      final Wish ok = await c.read(wishOrchestrationServiceProvider).createWish(
            text: text,
            category: WishCategory.other,
            now: DateTime(2026, 11, 20, 9),
            maxTextLength: kWishTextMaxLengthEn,
          );
      expect(ok.text.length, 101,
          reason: '🔴 en 档（300）下同一段 101 字必须落库 ⇒ 上限确实来自入参');
    });

    test('恰好 100 字在 zh 档通过（边界不误杀）', () async {
      final ProviderContainer c = await _boot();
      final Wish w = await c.read(wishOrchestrationServiceProvider).createWish(
            text: 'd' * 100,
            category: WishCategory.other,
            now: DateTime(2026, 11, 20, 9),
            maxTextLength: kWishTextMaxLengthZh,
          );
      expect(w.text.length, 100);
    });

    test('301 字在 en 档被拒；300 字通过', () async {
      final ProviderContainer c = await _boot();
      Object? err;
      try {
        await c.read(wishOrchestrationServiceProvider).createWish(
              text: 'e' * 301,
              category: WishCategory.other,
              now: DateTime(2026, 11, 20, 9),
              maxTextLength: kWishTextMaxLengthEn,
            );
      } catch (e) {
        err = e;
      }
      expect(err, isNotNull, reason: 'en 档 301 字必须被拒');

      final Wish w = await c.read(wishOrchestrationServiceProvider).createWish(
            text: 'f' * 300,
            category: WishCategory.other,
            now: DateTime(2026, 11, 20, 10),
            maxTextLength: kWishTextMaxLengthEn,
          );
      expect(w.text.length, 300);
    });

    test('过短（< kWishTextMinLength，trim 后）也被域层拒', () async {
      final ProviderContainer c = await _boot();
      for (final String short in <String>['', 'a', ' a ', '  ']) {
        Object? err;
        try {
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: short,
                category: WishCategory.other,
                now: DateTime(2026, 11, 20, 9),
                maxTextLength: kWishTextMaxLengthZh,
              );
        } catch (e) {
          err = e;
        }
        expect(err, isNotNull,
            reason: 'trim 后长度 < $kWishTextMinLength 的「$short」必须被拒');
      }
    });

    test('分类 UI 已下线：createWish 一律写 other（category = 0）', () async {
      final ProviderContainer c = await _boot();
      final Wish w = await c.read(wishOrchestrationServiceProvider).createWish(
            text: '想要一只小乌龟',
            category: WishCategory.other,
            now: DateTime(2026, 11, 20, 9),
            maxTextLength: kWishTextMaxLengthZh,
          );
      expect(w.category, WishCategory.other);
      expect(w.category.index, 0, reason: 'DB 侧落 0（历史安全默认）');
    });
  });

  group('⑤ 居中弹层几何（真实 MediaQuery，不是读源码）', () {
    const Size phone = Size(390, 844);

    Future<void> bootPhone(WidgetTester tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('水平/垂直居中偏差 ≤ 24dp，底边距 ≥ 80dp，高度 ≤ 85% 屏高',
        (WidgetTester tester) async {
      await bootPhone(tester);
      await _open(
        tester,
        _ComposeHost(l10n: zh, maxTextLength: wishMaxTextLength('zh')),
      );

      final Rect card = tester.getRect(find.byKey(kWishComposeDialogKey));
      final double dx = (card.center.dx - phone.width / 2).abs();
      final double dy = (card.center.dy - phone.height / 2).abs();
      final double bottomGap = phone.height - card.bottom;

      expect(dx, lessThanOrEqualTo(24),
          reason: '🔴 玄参反馈 2：卡片必须在**中间**（水平居中偏差 ≤24dp），实测 $dx');
      expect(dy, lessThanOrEqualTo(24),
          reason: '垂直也必须居中（不是贴底 bottom sheet），实测 $dy');
      expect(bottomGap, greaterThanOrEqualTo(80),
          reason: '底边距屏底 ≥80dp（排除"在下面显示"的 bottom sheet 观感），'
              '实测 $bottomGap');
      expect(card.height, lessThanOrEqualTo(phone.height * 0.85 + 0.5),
          reason: '高度 ≤ 屏高 85%，实测 ${card.height} vs ${phone.height * 0.85}');
      // 卡片确实有宽度（不是 0 宽假绿）。
      expect(card.width, greaterThan(200),
          reason: '前置自证：量到的是真实卡片矩形，宽 ${card.width}');
    });

    testWidgets('内容超高时弹层内部可滚动（不是把卡片撑破屏幕）',
        (WidgetTester tester) async {
      await bootPhone(tester);
      await _open(
        tester,
        _ComposeHost(l10n: zh, maxTextLength: wishMaxTextLength('en')),
      );
      // 灌 300 字 → TextField 撑到 minLines..maxLines 的 maxLines 上限并内部滚动；
      // 同时输入法错误提示出现时会再占一行 ⇒ 整体高度增长。
      await _enterChars(tester, 300);
      final Rect card = tester.getRect(find.byKey(kWishComposeDialogKey));
      expect(card.height, lessThanOrEqualTo(phone.height * 0.85 + 0.5),
          reason: '内容多也必须被 85% 上限约束');

      final Finder scroller = find.descendant(
        of: find.byKey(kWishComposeDialogKey),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scroller, findsOneWidget,
          reason: '超高内容必须由弹层内部 SingleChildScrollView 承接');
      // 提交按钮可达（能滚动到底并点到）——行为侧证明"没被裁掉"。
      await tester.tap(find.byKey(const Key('wish_compose_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsNothing,
          reason: '300 字在 en 档合法 ⇒ 提交按钮可点到并关闭');
    });

    testWidgets('键盘弹起（viewInsets.bottom=300）时卡片仍在可视区内',
        (WidgetTester tester) async {
      await bootPhone(tester);
      await _open(
        tester,
        _ComposeHost(l10n: zh, maxTextLength: wishMaxTextLength('zh')),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final Rect card = tester.getRect(find.byKey(kWishComposeDialogKey));
      const double visibleBottom = 844 - 300;
      expect(card.bottom, lessThanOrEqualTo(visibleBottom + 0.5),
          reason: '键盘弹起后卡片底边不得被键盘遮住（bottom=${card.bottom} '
              'vs 可视底 $visibleBottom）');
      expect(card.top, greaterThanOrEqualTo(0),
          reason: '卡片不得被顶出屏幕上方');
      // 提交按钮仍可点到（键盘场景的真实可用性）：先填合法文本再提交。
      expect(find.byKey(const Key('wish_compose_submit')), findsOneWidget);
      await _enterChars(tester, 10);
      await tester.tap(find.byKey(const Key('wish_compose_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsNothing,
          reason: '键盘弹起时提交按钮必须仍可点到并生效');
    });

    testWidgets('点遮罩不关闭（barrierDismissible=false，防误触丢草稿）',
        (WidgetTester tester) async {
      await bootPhone(tester);
      await _open(
        tester,
        _ComposeHost(l10n: zh, maxTextLength: wishMaxTextLength('zh')),
      );
      // 点屏幕左上角（远离卡片）＝点遮罩。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsOneWidget,
          reason: '点遮罩必须不关闭（草稿保护）');
      // 显式取消出口必须存在（否则无路可退）。
      expect(find.byKey(const Key('wish_compose_cancel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('wish_compose_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsNothing);
      expect(find.text('RETURNED:null'), findsOneWidget,
          reason: '取消 ⇒ 返回 null');
    });

    testWidgets('分类 chip 已下线：弹层里不得出现任何分类选择控件', (WidgetTester tester) async {
      await bootPhone(tester);
      await _open(
        tester,
        _ComposeHost(l10n: zh, maxTextLength: wishMaxTextLength('zh')),
      );
      // 6 个分类文案一个都不许出现（反馈 3：孩子不可能自己分类）。
      for (final String label in <String>[
        zh.wishCategoryGift,
        zh.wishCategoryExperience,
        zh.wishCategoryToy,
        zh.wishCategoryGrowth,
        zh.wishCategoryCompanionship,
        zh.wishCategoryOther,
      ]) {
        expect(find.text(label), findsNothing,
            reason: '分类 chip「$label」必须已下线');
      }
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
    });
  });
}
