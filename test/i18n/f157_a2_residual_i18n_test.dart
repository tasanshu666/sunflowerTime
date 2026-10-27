/// F157-A2 · **残余硬编码中文 4 处收口**（第二轮，玄参 2026-10-27 英文界面实测）。
///
/// ## 本文件与其它文件的分工
/// · `gold_notice_confirm_label_l10n_test.dart` → BUG-2（`知道啦` 默认值退役）；
/// · 本文件 → 第一轮「硬编码中文扫描」里被认定**真漏网**的 4 处中的 3 处运行期验证；
///   第 4 处（`shared_got_it` 源码守卫）落在 `gold_notice_confirm_label_l10n_test.dart` ③；
/// · `test/m3/f141_qa_probe_test.dart` A4 ③ → 完美日的**源码守卫**（ARB zh 逐字
///   + 页面零中文字面量）。
///
/// ## 三组用例（对应主理人验收清单）
/// | 组 | 覆盖面 | 断言 |
/// |----|--------|------|
/// | ① | `child_task_page._celebratePerfectDay()` 三句 | en 真的取到英文 / zh 逐字不变（含 emoji 与「」标点） |
/// | ② | `parent_entry_action` tooltip | en `Parent Hub` / zh「家长天地」 |
/// | ③ | `ChildConfirmCard` **不传** `cancelLabel` | en `Cancel` / zh「取消」（此前恒为硬编码「取消」） |
///
/// ## 为什么①走「宿主 + 同款调用」而不是直接泵 `ChildTaskPage`
/// 该页需要 12 个仓储 fake 才能泵起来，且「完美日」要真的把当日成长项全做完才会弹。
/// 本文件复刻 `_celebratePerfectDay()` 的**调用形态一字不差**（同一个
/// `showGoldNoticeDialog` + 同三个 l10n 槽位 + `items: const <GoldNoticeItem>[]`），
/// 并额外由 f141 A4 ③ 在源码层钉死「页面确实用这三个词条」——
/// 两侧合起来等价于端到端，但快两个数量级、且不引入 flaky。
library f157_a2_residual_i18n_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/parent_entry_action.dart';

/// 切到 [lang] 并在用例结束后复位为 `system`（测试垫片 = zh），
/// 避免污染同进程内其它文件的断言（`AppLocaleController` 是静态单点）。
void _useLocale(AppLanguage lang) {
  AppLocaleController.init(lang);
  addTearDown(() => AppLocaleController.init(AppLanguage.system));
}

/// 生产同构宿主：`MaterialApp` → 页级 [L10nScope] → `Builder`。
///
/// 🔴 必须是 [L10nScope] 而非 `MaterialApp.locale`：生产每个迁移页都自带一层
/// 页级 scope（它遮蔽 app 壳那层），本文件要验的就是**这层里**的解析结果。
Widget _host(Widget Function(BuildContext ctx) builder) {
  return MaterialApp(
    home: L10nScope(
      child: Builder(
        builder: (BuildContext ctx) => Scaffold(body: builder(ctx)),
      ),
    ),
  );
}

/// `_celebratePerfectDay()` 的**逐字复刻**（槽位 / 顺序 / 空明细列表全一致）。
Widget _perfectDayTrigger() {
  return _host((BuildContext ctx) {
    return Center(
      child: TextButton(
        onPressed: () {
          // 与 `child_task_page.dart` 的 `_celebratePerfectDay()` 同一取法与同一组槽位。
          final AppLocalizations t = l10nOf(ctx);
          showGoldNoticeDialog(
            ctx,
            title: t.task_perfect_title,
            items: const <GoldNoticeItem>[],
            footerText: t.task_perfect_footer,
            confirmLabel: t.task_perfect_ok,
            badgeIcon: Icons.emoji_events,
          );
        },
        child: const Text('open'),
      ),
    );
  });
}

/// 点开触发钮 → 等弹窗路由推进（`showDialog` 是异步 push，需两帧）。
Future<void> _tapOpen(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  const String kZhTitle = '🌻 今日成长项全部完成！';
  const String kZhFooter = '你今天把全部成长项都做完啦，获得「完美日」标记！';
  const String kZhOk = '太棒啦';

  group('① 完美日三句（child_task_page._celebratePerfectDay）', () {
    testWidgets('en：真的取到英文，且一个中文字都不许漏',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.en);
      await tester.pumpWidget(_perfectDayTrigger());
      await _tapOpen(tester);

      expect(find.byType(GoldNoticeDialog), findsOneWidget,
          reason: '① 必须走统一通知卡壳（不是裸 AlertDialog）');
      expect(find.text('🌻 All growth tasks done today!'), findsOneWidget,
          reason: '① en 标题（含 emoji，非机翻腔）');
      expect(
          find.textContaining(
              'You finished every growth task today and earned a "Perfect Day" badge!'),
          findsOneWidget,
          reason: '① en 正文（口语化直译）');
      expect(find.text('Awesome!'), findsOneWidget, reason: '① en 按钮');

      // 反向断言：三句中文**一句都不许**在英文界面出现。
      expect(find.text(kZhTitle), findsNothing,
          reason: '① 英文界面出现中文标题 = 迁 ARB 没生效');
      expect(find.text(kZhFooter), findsNothing,
          reason: '① 英文界面出现中文正文 = 迁 ARB 没生效');
      expect(find.text(kZhOk), findsNothing,
          reason: '① 英文界面出现中文按钮 = 迁 ARB 没生效');
    });

    testWidgets('zh：三句必须与改前硬编码逐字相同（含 emoji 与「」标点）',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.zh);
      await tester.pumpWidget(_perfectDayTrigger());
      await _tapOpen(tester);

      expect(find.byType(GoldNoticeDialog), findsOneWidget);
      expect(find.text(kZhTitle), findsOneWidget,
          reason: '① zh 标题逐字不变（一个字符都不许动）');
      expect(find.textContaining(kZhFooter), findsOneWidget,
          reason: '① zh 正文逐字不变（含「」标点）');
      expect(find.text(kZhOk), findsOneWidget, reason: '① zh 按钮逐字不变');

      // 反向：英文词条不得串到中文界面。
      expect(find.text('Awesome!'), findsNothing);
    });
  });

  group('② parent_entry_action tooltip', () {
    testWidgets('en → Parent Hub；zh → 家长天地', (WidgetTester tester) async {
      // ── en ──────────────────────────────────────────────────────────
      _useLocale(AppLanguage.en);
      await tester.pumpWidget(
        _host((_) => const Center(child: ParentEntryAction(immersive: true))),
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(ParentEntryAction.iconKey))
            .tooltip,
        'Parent Hub',
        reason: '② 英文界面右上角入口 tooltip 必须是英文（长按上屏 + 无障碍朗读）',
      );

      // ── zh ──────────────────────────────────────────────────────────
      // 复用同一棵子树，靠 `AppLocaleController.revision` 触发 L10nScope 重建
      // （F154 语言即时切换机制），顺便验证「切换后 tooltip 也跟着切」。
      _useLocale(AppLanguage.zh);
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(ParentEntryAction.iconKey))
            .tooltip,
        '家长天地',
        reason: '② zh 必须逐字「家长天地」（原硬编码字面量，零变更）',
      );
    });

    testWidgets('immersive = false 形态同样走 l10n', (WidgetTester tester) async {
      _useLocale(AppLanguage.en);
      await tester.pumpWidget(
        _host((_) => const Center(child: ParentEntryAction(immersive: false))),
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(ParentEntryAction.iconKey))
            .tooltip,
        'Parent Hub',
        reason: '② 裸 IconButton 分支与胶囊分支同源同文案',
      );
    });
  });

  group('③ ChildConfirmCard 不传 cancelLabel 时的兜底', () {
    /// 只给 title / confirmLabel（**刻意不传 cancelLabel**）——
    /// 这正是「调用方忘了传」的最坏情形，改前会恒弹中文「取消」。
    Widget trigger({required String title, required String ok}) {
      return _host((BuildContext ctx) {
        return Center(
          child: TextButton(
            onPressed: () => showChildConfirmCard(
              context: ctx,
              title: title,
              confirmLabel: ok,
            ),
            child: const Text('open'),
          ),
        );
      });
    }

    testWidgets('en：兜底为 Cancel（不是「取消」）', (WidgetTester tester) async {
      _useLocale(AppLanguage.en);
      await tester.pumpWidget(
          trigger(title: 'Plant this seed?', ok: 'Plant now'));
      await _tapOpen(tester);

      expect(find.byType(ChildConfirmCard), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget,
          reason: '③ 不传 cancelLabel 时 en 必须兜底 `Cancel`');
      expect(find.text('取消'), findsNothing,
          reason: '③ 硬编码「取消」已退役 —— 英文界面不许再出现');
      expect(find.text('Plant now'), findsOneWidget);
    });

    testWidgets('zh：兜底仍为「取消」逐字不变（既有 find.text 断言不许破）',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.zh);
      await tester.pumpWidget(trigger(title: '现在种下吗？', ok: '确定种植'));
      await _tapOpen(tester);

      expect(find.byType(ChildConfirmCard), findsOneWidget);
      expect(find.text('取消'), findsOneWidget,
          reason: '③ zh 兜底 = `shared_cancel` =「取消」，与改前逐字相同');
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('显式传入时以传入值为准（不被 l10n 覆盖）',
        (WidgetTester tester) async {
      _useLocale(AppLanguage.en);
      await tester.pumpWidget(_host((BuildContext ctx) {
        return Center(
          child: TextButton(
            onPressed: () => showChildConfirmCard(
              context: ctx,
              title: 'Quit?',
              confirmLabel: 'Quit',
              // 调用方自定义文案必须优先：l10n 兜底只在 null 时生效。
              cancelLabel: 'Stay',
            ),
            child: const Text('open'),
          ),
        );
      }));
      await _tapOpen(tester);

      expect(find.text('Stay'), findsOneWidget,
          reason: '③ 显式 cancelLabel 优先，兜底不得覆盖调用方');
      expect(find.text('Cancel'), findsNothing);
    });
  });
}
