/// C74 · 等级**详情卡** widget 测试（2026-10-14 下午「徽章 = 摘要 / 点按 = 详情」）。
///
/// 钉住五件事：
///  ① **点徽章弹卡**：卡内含「当前等级 + 称号」与「距 Lv.N 还差 X」；
///  ② **9 个称号全列**（1/5/10/…/40 一行不落），**当前称号那行高亮**（高亮底 + w800；
///     C81 ⑤ 已删行尾 ✨ —— 它会把当前行右列往左挤、破坏 9 行右对齐）；；
///  ③ **点 barrier 关闭**（不是一次性演出，点外面就走）；
///  ④ **满级态**（Lv.40）：第二块显示满级文案，9 行里「时光大贤者」高亮；
///  ⑤ **跨级/压线**：刚好踩到门槛（60 → Lv.1 / 120 → Lv.2 / 59.9 → 未解锁）
///     三处数据都正确（`progressOf` 纯派生，本文件只验装配口径）。
///
/// C80 · 追加三件（TC-V3-09..12）：
///  ⑥ **三态徽章**：免费档已达标行 = 锁标态（置灰 + 🔒 + 阳光图标）、未达行 = 灰字无锁；
///  ⑦ **付费恢复**：premium 档全橙实心；dialog 开着时 entitlement 变化 → 自动重建
///     （R-V3-3 / P1-1，零回调代码）；
///  ⑧ **锁标点按** → **只弹升级提示卡**（C81 ①：不 pop 详情卡、不跳转；V3-Q1 结案）。
///
/// C81 · 追加（玄参真机验收）：
///  ⑨ 属性 pill 顺序 = `[🔒] emoji 属性名 数值 ☀`；**9 行统一带 ☀**（不再按达等级条件渲染）。
///
/// 🟢 夹具纪律：不依赖网络 / 不依赖真机，纯 widget 度量；徽章可**单独立泵**
/// （详情卡是本组件的私事，不需要整张今日页）。C80 后详情卡为 ConsumerWidget，
/// 夹具一律包 [ProviderScope]（付费态经外部 [ProviderContainer] 注入）。
library focus_level_detail_dialog_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart'
    show perkOfTitleNode, perkShortTextOf;
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';

/// 立泵一枚摘要徽章（外层 `MaterialApp` 提供 Dialog 所需的 Navigator/Theme）。
///
/// [container] 传入时经 [UncontrolledProviderScope] 外接（⑦ 购买即时重建断言用）。
Future<void> _pumpBadge(
  WidgetTester tester, {
  required double totalMinutes,
  ProviderContainer? container,
}) async {
  final Widget app = MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: FocusLevelBadge(
          progress: progressOf(totalMinutes),
          totalMinutes: totalMinutes,
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    container == null
        ? ProviderScope(child: app)
        : UncontrolledProviderScope(container: container, child: app),
  );
  await tester.pumpAndSettle();
}

/// 点开详情卡并等动画结束。
Future<void> _openDetail(WidgetTester tester) async {
  await tester.tap(find.byKey(FocusLevelBadge.badgeTapKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① 点徽章 → 弹详情卡：含等级/称号/「距下一级还差 …」',
      (WidgetTester tester) async {
    // 900 分钟 = 15h → Lv.7（称号仍是 Lv.5 节点「专注小苗苗」）。
    await _pumpBadge(tester, totalMinutes: 900);

    // 摘要态：标题在，长文案**不在**（这是 v2 的核心：提示文案已撤出徽章）。
    expect(find.text('Lv.7'), findsOneWidget);
    expect(find.text('专注小苗苗'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing, reason: '默认是摘要，不弹卡');

    await _openDetail(tester);

    expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget);
    // a) 等级 + 称号（详情卡 head 里那枚大圆徽是独立的 Key）。
    expect(find.byKey(FocusLevelDetailDialog.detailBadgeCircleKey),
        findsOneWidget);
    expect(find.text('Lv.7'), findsWidgets);
    // v3：等级文案不再重复 —— 详情卡内「Lv.7」只在圆徽里出现 1 次（圆徽内 1 次、
    // 右侧标签 0 次）。圆徽外层摘要徽章仍有 1 次，故全树 findsWidgets，但**限定
    // 到详情卡子树**必须恰好 1 个（圆徽那枚）。
    expect(
      find.descendant(
        of: find.byKey(FocusLevelDetailDialog.dialogKey),
        matching: find.text('Lv.7'),
      ),
      findsOneWidget,
      reason: '详情卡内「Lv.7」只出现 1 次（圆徽），右侧重复标签已删（v3）',
    );
    expect(find.text('专注小苗苗'), findsWidgets);
    // b) 距下一级：Lv.8 门槛 1140 − 900 = 240 分钟 = 4 小时。
    final Text gap =
        tester.widget<Text>(find.byKey(FocusLevelDetailDialog.gapTextKey));
    // i18n B3（T05）：模板常量已删除，断言直接对 ARB 真值（zh）——
    // 比「常量替换」更强：它同时钉住 ARB 里的中文与占位符顺序。
    expect(
      gap.data,
      AppLocalizationsZh().shared_level_gap_next(8, '4 小时'),
      reason: '距下一级 = 下一级门槛 − 累计（复用 progressOf.minutesToNext）',
    );
  });

  testWidgets('② 9 个称号全列 + 当前称号高亮（高亮底 + 加粗；C81 ⑤ 无 ✨）',
      (WidgetTester tester) async {
    await _pumpBadge(tester, totalMinutes: 900); // Lv.7 → 当前节点 Lv.5
    await _openDetail(tester);

    // 9 个称号节点一行不落（按 kFocusLevelTitleLevels 逐个 Key 断言）。
    expect(kFocusLevelTitleLevels.length, 9);
    for (final int level in kFocusLevelTitleLevels) {
      expect(find.byKey(FocusLevelDetailDialog.titleRowKeyOf(level)),
          findsOneWidget,
          reason: 'Lv.$level 称号行必须在列表里');
    }
    // 每行必须显示**自己那一个**称号（当前称号在卡里会出现 3 次：摘要徽章 /
    // 详情卡 head / 列表行 —— 故按行 Key 限定范围，不用全树 findsOneWidget）。
    for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
      final int node = kFocusLevelTitleLevels[i];
      expect(
        find.descendant(
          of: find.byKey(FocusLevelDetailDialog.titleRowKeyOf(node)),
          matching: find.text(kFocusLevelTitles[i]),
        ),
        findsOneWidget,
        reason: 'Lv.$node 那一行必须显示「${kFocusLevelTitles[i]}」',
      );
    }
    // C81 ⑤：不再有 ✨ —— 当前称号行改用 **高亮底 + w800 加粗** 标示。
    for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
      final int node = kFocusLevelTitleLevels[i];
      final Text titleText = tester.widget<Text>(find.descendant(
        of: find.byKey(FocusLevelDetailDialog.titleRowKeyOf(node)),
        matching: find.text(kFocusLevelTitles[i]),
      ));
      final bool isCurrent = node == 5; // Lv.7 的当前称号节点 = Lv.5
      expect(titleText.style?.fontWeight,
          isCurrent ? FontWeight.w800 : FontWeight.w500,
          reason: 'Lv.$node ${isCurrent ? '是当前称号（w800 加粗）' : '非当前（w500）'}');
    }
    // ✨ 已删除（C81 ⑤）：全树不得再出现（它会把当前行右列往左挤、破坏 9 行对齐）。
    expect(find.text('✨'), findsNothing,
        reason: 'C81 ⑤：行尾 ✨ 已删（改高亮底 + 加粗，9 行右列严格对齐）');

    // C81 ②：9 行**统一**带阳光图标（不再按达等级条件渲染）。
    for (final int node in kFocusLevelTitleLevels) {
      expect(
        find.descendant(
          of: find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(node)),
          matching: find.byType(Image),
        ),
        findsOneWidget,
        reason: 'Lv.$node 行统一带阳光图标（C81 ②）',
      );
    }

    // C78：9 行的专属属性徽章（_PerkPill）渲染于**称号文字之后**（同 Row、右侧）。
    for (final int level in kFocusLevelTitleLevels) {
      final Finder pillFinder = find.byKey(
          FocusLevelDetailDialog.titleRowPerkKeyOf(level));
      expect(pillFinder, findsOneWidget,
          reason: 'Lv.$level 行必须有专属属性徽章');
      final Rect pillRect = tester.getRect(pillFinder);
      final Rect titleRect = tester.getRect(find.descendant(
        of: find.byKey(FocusLevelDetailDialog.titleRowKeyOf(level)),
        matching: find.text(kFocusLevelTitles[kFocusLevelTitleLevels.indexOf(level)]),
      ));
      expect(pillRect.left, greaterThan(titleRect.left),
          reason: 'Lv.$level 的属性徽章必须在称号文字之后（C78「说明移到称号后面」）');
    }

    // C80 三态语义（免费档默认）：
    //  · 已达标行（Lv.1 / Lv.5）= **锁标态**：pill 内含 🔒、文字置灰、可点；
    //  · 未达行 = **灰字**：pill 内无 🔒（节点牌的 🔒 是圆牌自己的，不在此列）。
    //  （免费档全体置灰；付费后的橙实心见 ⑦。）
    const Color perkOrange = Color(0xFFE8A600);
    const Color lockedGrey = Color(0xFFB0A08C);
    for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
      final int node = kFocusLevelTitleLevels[i];
      final Finder row =
          find.byKey(FocusLevelDetailDialog.titleRowKeyOf(node));
      final bool unlocked = 7 >= node;
      final Finder pill =
          find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(node));
      // 行内恰一枚 🔒：未解锁行 = 圆牌锁；已达标免费行 = pill 锁标。
      expect(
        find.descendant(of: row, matching: find.text('🔒')),
        findsOneWidget,
        reason: 'Lv.$node 行内恰一枚 🔒（未解锁=圆牌 / 已达标免费=pill 锁标）',
      );
      // pill 内的 🔒：仅已达标（锁标态）行有。
      expect(
        find.descendant(of: pill, matching: find.text('🔒')),
        unlocked ? findsOneWidget : findsNothing,
        reason: 'Lv.$node pill：${unlocked ? '锁标态（含🔒）' : '灰字（无🔒）'}',
      );
      final Text perkText = tester.widget<Text>(find.descendant(
        of: pill,
        matching: find.text(perkShortTextOf(perkOfTitleNode(node))),
      ));
      expect(perkText.style?.color, unlocked ? lockedGrey : lockedGrey,
          reason: '免费档全体置灰（已达标=锁标态灰 / 未达=灰字），付费橙见 ⑦');
      expect(perkText.style?.color, isNot(perkOrange));
    }
  });

  testWidgets('③ 点 barrier（卡片外）关闭详情卡', (WidgetTester tester) async {
    await _pumpBadge(tester, totalMinutes: 900);
    await _openDetail(tester);
    expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget);

    // 屏障左上角（10,10）远离卡片 ⇒ 命中 barrierDismissible。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsNothing,
        reason: '点卡片外必须关闭（玄参：不是一次性演出，随时可退）');
    // 关掉后今日页摘要徽章仍在（详情卡不该影响底层）。
    expect(find.byKey(FocusLevelBadge.badgeKey), findsOneWidget);
  });

  testWidgets('④ 满级态（21900 分钟 = Lv.40）→ 满级文案 + 末位称号高亮',
      (WidgetTester tester) async {
    await _pumpBadge(tester, totalMinutes: 21900);

    // 摘要态：满级隐藏细进度条（无处可进）。
    expect(find.byKey(FocusLevelBadge.badgeBarKey), findsNothing,
        reason: '满级隐藏进度条（C74）');
    await _openDetail(tester);

    final Text gap =
        tester.widget<Text>(find.byKey(FocusLevelDetailDialog.gapTextKey));
    // i18n B3（T05）：同上，断言 ARB 的 `shared_level_gap_max` 真值。
    expect(gap.data, AppLocalizationsZh().shared_level_gap_max('时光大贤者'),
        reason: '满级第二块显示满级文案（单点收敛到 ARB）');
    // C81 ⑤：改认证当前行 = **加粗**（✨ 已删）。
    final Text lastTitle = tester.widget<Text>(find.descendant(
      of: find.byKey(FocusLevelDetailDialog.titleRowKeyOf(40)),
      matching: find.text('时光大贤者'),
    ));
    expect(lastTitle.style?.fontWeight, FontWeight.w800,
        reason: '满级时高亮第 9 个称号（Lv.40 · 时光大贤者，C81 ⑤ 加粗）');
  });

  testWidgets('⑤ 压线 / 跨级：59.9 → 未解锁，60 → Lv.1，120 → Lv.2（进度归零）',
      (WidgetTester tester) async {
    // 59.9：差 0.1 分钟没到 Lv.1 门槛 ⇒ 仍未解锁，进度条指向 Lv.1。
    await _pumpBadge(tester, totalMinutes: 59.9);
    expect(find.text(kLevelLockedGlyph), findsOneWidget);
    await _openDetail(tester);
    expect(
      tester.widget<Text>(find.byKey(FocusLevelDetailDialog.gapTextKey)).data,
      '距 Lv.1 还差 1 分钟',
      reason: 'minutesToNext = ceil(60 − 59.9) = 1',
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 60：恰好踩线 ⇒ Lv.1，进度 0.0，距 Lv.2（门槛 120）还差 60 分钟 = 1 小时。
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadge(tester, totalMinutes: 60);
    expect(find.text('Lv.1'), findsOneWidget);
    await _openDetail(tester);
    expect(
      tester.widget<Text>(find.byKey(FocusLevelDetailDialog.gapTextKey)).data,
      '距 Lv.2 还差 1 小时',
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 120：跨到 Lv.2 ⇒ 跨级后进度归零（不是接着上一级的进度）。
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadge(tester, totalMinutes: 120);
    expect(find.text('Lv.2'), findsOneWidget);
    final FocusLevelProgress p2 = progressOf(120);
    expect(p2.progress, 0.0, reason: '跨级后进度回到本区间起点（0.0）');
    await _openDetail(tester);
    expect(
      tester.widget<Text>(find.byKey(FocusLevelDetailDialog.gapTextKey)).data,
      '距 Lv.3 还差 2 小时',
      reason: 'Lv.3 门槛 240 − 120 = 120 分钟',
    );
  });

  // ── C80/C81 · ⑥ 免费三态边界（TC-V3-10）：未达行灰字无锁不可点（☀ 统一带）──────
  testWidgets('⑥ C81 未达等级行：灰字、pill 无锁、带阳光图标、不可点（P0-6 边界）',
      (WidgetTester tester) async {
    // Lv.7 → 未达节点取 Lv.10（灰字态）。
    await _pumpBadge(tester, totalMinutes: 900);
    await _openDetail(tester);

    final Finder pill =
        find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(10));
    expect(pill, findsOneWidget);
    expect(find.descendant(of: pill, matching: find.text('🔒')), findsNothing,
        reason: '未达行灰字无锁（锁只出现在圆牌）');
    expect(find.descendant(of: pill, matching: find.byType(Image)),
        findsOneWidget,
        reason: 'C81 ②：9 行统一带阳光图标（未达行亦置灰带 ☀）');
    final Text perkText = tester.widget<Text>(find.descendant(
      of: pill,
      matching: find.text(perkShortTextOf(perkOfTitleNode(10))),
    ));
    expect(perkText.style?.color, const Color(0xFFB0A08C),
        reason: '未达行 = 灰字（_kDetailLockedColor）');
    // 不可点：tap 后详情卡仍在（无弹卡、无跳转行为可断言 → 卡未关即证）。
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget,
        reason: '灰字态不可点：tap 后详情卡仍开着');
    expect(find.byKey(FocusLevelDetailDialog.perkLockedHintKey), findsNothing,
        reason: '灰字态不弹升级提示卡（仅锁标态可点）');
  });

  // ── C80 · ⑦ 付费恢复（TC-V3-11）：橙实心 + dialog 开着购买自动重建 ──────────
  testWidgets('⑦ C80 premium：已达标行橙实心（w700 无🔒）；dialog 开着 → entitlement\n'
      '变化 → 自动重建恢复（P1-1 零回调）', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpBadge(tester, totalMinutes: 900, container: container);
    await _openDetail(tester);

    // 免费档初始：Lv.5 行 = 锁标态（灰 + 🔒）。
    final Finder pill5 =
        find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(5));
    expect(
      find.descendant(of: pill5, matching: find.text('🔒')),
      findsOneWidget,
    );

    // 模拟购买成功（不关 dialog）→ ConsumerWidget watch 驱动自动重建。
    container.read(entitlementProvider.notifier).state = Entitlement.lifetime();
    await tester.pumpAndSettle();

    expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget,
        reason: 'entitlement 变化只重建内容，不关卡（R-V3-3）');
    expect(find.descendant(of: pill5, matching: find.text('🔒')), findsNothing,
        reason: '付费后锁标消失');
    final Text perkText5 = tester.widget<Text>(find.descendant(
      of: pill5,
      matching: find.text(perkShortTextOf(perkOfTitleNode(5))),
    ));
    expect(perkText5.style?.color, const Color(0xFFE8A600),
        reason: '付费后已达标行恢复橙实心（_kBarFill）');
    expect(perkText5.style?.fontWeight, FontWeight.w700);
    // 未达行仍灰字（付费不改变等级意义）。
    final Text perkText10 = tester.widget<Text>(find.descendant(
      of: find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(10)),
      matching: find.text(perkShortTextOf(perkOfTitleNode(10))),
    ));
    expect(perkText10.style?.color, const Color(0xFFB0A08C),
        reason: '未达行与档位无关，恒灰字');
  });

  // ── C81 ① 锁标点按：只弹升级提示卡（不 pop、不跳转；V3-Q1 结案）───────────────
  testWidgets('⑧ C81 锁标态点按 → 弹「请升级到完整版本功能」提示卡（不 pop/不跳转）',
      (WidgetTester tester) async {
    await _pumpBadge(tester, totalMinutes: 900); // Lv.7：Lv.1/5 已达标（锁标态）
    await _openDetail(tester);
    expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget);

    await tester.tap(find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(1)));
    await tester.pumpAndSettle();

    // 弹提示卡（文案单点常量）。
    expect(find.byKey(FocusLevelDetailDialog.perkLockedHintKey), findsOneWidget,
        reason: '锁标点按 → 弹升级提示卡（C81 ①）');
    expect(find.text(kPremiumUpsellHintText), findsOneWidget,
        reason: '提示文案 = kPremiumUpsellHintText「请升级到完整版本功能」');
    // **不** pop 详情卡（提示卡叠在详情卡之上）。
    expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget,
        reason: '详情卡不得被 pop（C81 ①：只提示、不跳转）');

    // 点「知道了」→ 关提示卡，详情卡仍在。
    await tester.tap(find.text(kLevelDetailHintConfirmText));
    await tester.pumpAndSettle();
    expect(find.byKey(FocusLevelDetailDialog.perkLockedHintKey), findsNothing);
    expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget,
        reason: '关提示卡后回到详情卡（未跳转、未 pop）');
  });
}
