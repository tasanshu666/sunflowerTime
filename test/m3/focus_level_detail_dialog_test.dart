/// C74 · 等级**详情卡** widget 测试（2026-10-14 下午「徽章 = 摘要 / 点按 = 详情」）。
///
/// 钉住五件事：
///  ① **点徽章弹卡**：卡内含「当前等级 + 称号」与「距 Lv.N 还差 X」；
///  ② **9 个称号全列**（1/5/10/…/40 一行不落），**当前称号那行高亮 + ✨**；
///  ③ **点 barrier 关闭**（不是一次性演出，点外面就走）；
///  ④ **满级态**（Lv.40）：第二块显示满级文案，9 行里「时光大贤者」高亮；
///  ⑤ **跨级/压线**：刚好踩到门槛（60 → Lv.1 / 120 → Lv.2 / 59.9 → 未解锁）
///     三处数据都正确（`progressOf` 纯派生，本文件只验装配口径）。
///
/// 🟢 夹具纪律：不依赖网络 / 不依赖真机，纯 widget 度量；徽章可**单独立泵**
/// （详情卡是本组件的私事，不需要整张今日页）。
library focus_level_detail_dialog_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';

/// 立泵一枚摘要徽章（外层 `MaterialApp` 提供 Dialog 所需的 Navigator/Theme）。
Future<void> _pumpBadge(
  WidgetTester tester, {
  required double totalMinutes,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: FocusLevelBadge(
            progress: progressOf(totalMinutes),
            totalMinutes: totalMinutes,
          ),
        ),
      ),
    ),
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
    expect(
      gap.data,
      kLevelDetailNextTextTemplate
          .replaceAll('{n}', '8')
          .replaceAll('{r}', '4 小时'),
      reason: '距下一级 = 下一级门槛 − 累计（复用 progressOf.minutesToNext）',
    );
  });

  testWidgets('② 9 个称号全列 + 当前称号高亮（仅一行带 ✨）',
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
    // 当前称号 = 已解锁的**最高**称号节点（Lv.5，不是 Lv.10）。
    expect(find.text(kLevelDetailCurrentMark), findsOneWidget,
        reason: '9 行里只能有一行带 ✨');
    // ✨ 必须落在 Lv.5 那一行（用 descendant 定位，不靠视觉）。
    expect(
      find.descendant(
        of: find.byKey(FocusLevelDetailDialog.titleRowKeyOf(5)),
        matching: find.text(kLevelDetailCurrentMark),
      ),
      findsOneWidget,
      reason: 'Lv.7 的当前称号节点仍是 Lv.5（称号 ↔ 等级解耦，C74 §3）',
    );

    // v3：9 行右侧每行都有「小太阳 + 阳光奖励数」，金额 = sunlightOfLevel(节点)
    // （C74 §4：3/5/7/9/11/13/16/18/20）。
    for (final int level in kFocusLevelTitleLevels) {
      final Finder rewardFinder = find.byKey(
          FocusLevelDetailDialog.titleRowRewardKeyOf(level));
      expect(rewardFinder, findsOneWidget,
          reason: 'Lv.$level 行必须有「小太阳 + 奖励数」widget');
      expect(
        find.descendant(
            of: rewardFinder, matching: find.text('${sunlightOfLevel(level)}')),
        findsOneWidget,
        reason: 'Lv.$level 行奖励数 = ${sunlightOfLevel(level)} ☀（C74 §4）',
      );
    }

    // v3：已解锁 vs 未解锁的锁/太阳语义（Lv.7 → 已解锁 Lv.1/Lv.5，未解锁 Lv.10+）。
    // · 太阳色：已解锁 = 阳光橙（已领取）、未解锁 = 灰（预告激励）。
    // · 锁：未解锁行节点牌有 🔒、已解锁行无 🔒（节点牌显示等级数字）。
    const Color sunOrange = Color(0xFFE8A600);
    const Color lockedGrey = Color(0xFFB0A08C);
    for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
      final int node = kFocusLevelTitleLevels[i];
      final Finder row =
          find.byKey(FocusLevelDetailDialog.titleRowKeyOf(node));
      final Finder reward =
          find.byKey(FocusLevelDetailDialog.titleRowRewardKeyOf(node));
      final bool unlocked = 7 >= node;
      expect(
        find.descendant(of: row, matching: find.text('🔒')),
        unlocked ? findsNothing : findsOneWidget,
        reason: 'Lv.$node 节点牌：${unlocked ? '数字(无🔒)' : '🔒'}',
      );
      final Icon sun = tester.widget<Icon>(
        find.descendant(of: reward, matching: find.byType(Icon)),
      );
      expect(sun.color, unlocked ? sunOrange : lockedGrey,
          reason: 'Lv.$node 小太阳：${unlocked ? '阳光橙(已领取)' : '灰(预告)'}');
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
    expect(gap.data, kLevelMaxTextTemplate.replaceAll('{t}', '时光大贤者'),
        reason: '满级第二块显示满级文案（单点收敛到常量模板）');
    expect(
      find.descendant(
        of: find.byKey(FocusLevelDetailDialog.titleRowKeyOf(40)),
        matching: find.text(kLevelDetailCurrentMark),
      ),
      findsOneWidget,
      reason: '满级时高亮第 9 个称号（Lv.40 · 时光大贤者）',
    );
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
}
