/// 专注报告 v2 · `deepReport` 门控**证据性**测试（C76 裁定 #1 / T03）。
///
/// 为什么是「证据性」而不是「跑通了」：免费档最容易出的问题是**静默**——
/// 月 / 年点了没反应、深度区块凭空消失，用户会当成 bug 投诉。故这里要观测到：
///
///  1. **免费档 · 月 / 年被拦**：🔒 恰 2 枚；点「月」后**期间标题仍是周**（不切换）
///     且**弹出「升级解锁」**（给因，不静默）；
///  2. **免费档 · 引导只有 1 条**：稳定性区块渲染**一条** `ReportUpsellBar` 横条
///     （`解锁深度专注报告` × 1），**热力图区块整块不渲染**（连标题一起消失），
///     且**热力图组件与任何实格都没被渲染**（证明不是「先渲染再遮挡」）；
///  3. **免费档 · 日 / 周完整**：Hero 分钟、`本周专注分布`、护眼统计都在（近 7 天不缩水）；
///  4. **买断档 · 全开**：无 🔒；点「月」→ 标题 `2026 年 10 月`；热力图出现；
///     引导卡消失；稳定性读数可见；
///  5. **不翻未来**：日档 ▶（`下一期间`）为 disabled（`onPressed == null`）；
///  6. **免费档不做无用功**：不发起 365 天范围查询、不跑 `buildReport` 的 35 次按日查询
///     （用假仓储记录查询跨度取证）。
///
/// 固定「现在」= `2026-10-17 10:00`（周六，本周 10-12 ~ 10-18，自然月 2026-10）。
library focus_report_gating_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/presentation/parent/widgets/focus_report_section.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_heatmap.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_upsell_bar.dart';

/// 固定「现在」：2026-10-17（周六）10:00。
final DateTime _now = DateTime(2026, 10, 17, 10);

/// 假专注仓储：同时实现 [FocusRepository] 与 [FocusRangeQuery]（走快路径）。
///
/// 自带 5 天数据（10-12 ~ 10-16，每天 25 分钟、100% 完成 → 均为有效专注日），
/// 并记录每次**范围查询的跨度**，用于证明「免费档不查 365 天」。
class _FakeFocusRepository implements FocusRepository, FocusRangeQuery {
  _FakeFocusRepository() : _sessions = _seedSessions();

  final List<FocusSession> _sessions;

  /// 每次 [sessionsBetween] 的跨度（天）。免费档应只有 7 / 8 天这种小跨度。
  final List<int> rangeSpans = <int>[];

  static List<FocusSession> _seedSessions() {
    final List<FocusSession> list = <FocusSession>[];
    for (int i = 0; i < 5; i++) {
      final DateTime start = DateTime(2026, 10, 12 + i, 19, 0);
      list.add(
        FocusSession(
          id: 'fs-$i',
          start: start,
          end: start.add(const Duration(minutes: 25)),
          plannedMin: 25,
          actualFocusMin: 25,
          status: FocusStatus.completed,
          sunlightEarned: 5,
          createdAt: start,
        ),
      );
    }
    return list;
  }

  @override
  Future<void> saveSession(FocusSession session) async => _sessions.add(session);

  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      _sessions.where((FocusSession s) => dayKey(s.start) == key).toList();

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );

  @override
  Future<List<FocusSession>> sessionsBetween(DateTime from, DateTime to) async {
    rangeSpans.add(to.difference(from).inDays);
    final List<FocusSession> hits = _sessions
        .where((FocusSession s) => !s.start.isBefore(from) && s.start.isBefore(to))
        .toList()
      ..sort((FocusSession a, FocusSession b) => a.start.compareTo(b.start));
    return hits;
  }
}

/// 装配并渲染报告段（画布加高，保证 7 块内容全部真正 build）。
Future<void> _pumpSection(
  WidgetTester tester, {
  required bool premium,
  required _FakeFocusRepository repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      entitlementProvider.overrideWith(
        (Ref ref) => premium ? Entitlement.lifetime() : Entitlement.free,
      ),
      focusReportServiceProvider.overrideWithValue(
        FocusReportService(focus: repository),
      ),
      // 护眼两项仓储：本测试只关心门控，故让它们直接抛错 →
      // 走报告段的「静默降级」分支（0 次 / '—'），不影响任何断言。
      sunlightRepositoryProvider.overrideWith(
        (Ref ref) => throw UnimplementedError('gating test: no sunlight repo'),
      ),
      eyeCareLogRepositoryProvider.overrideWith(
        (Ref ref) => throw UnimplementedError('gating test: no eye care repo'),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: FocusReportSection(now: _now)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 点某档周期（用稳定 Key，不用文本 finder）。
Future<void> _tapPeriod(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey<String>('reportPeriod_$name')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('免费档 · 月/年被拦：🔒 恰 2 枚，点月不切换周期但弹「升级解锁」',
      (WidgetTester tester) async {
    final _FakeFocusRepository repository = _FakeFocusRepository();
    await _pumpSection(tester, premium: false, repository: repository);

    // 月 / 年两档各一枚锁图标（日 / 周不带锁）。
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2),
        reason: '免费档应且仅应在「月」「年」两档显示 🔒');

    // 默认周：标题是「2026年10月12日 ～ 10月18日」。
    expect(find.textContaining('～'), findsOneWidget);

    await _tapPeriod(tester, 'month');

    // ① 周期**没有**切换（仍是周区间）：没出现「2026 年 10 月」这种月标题。
    expect(find.text('2026 年 10 月'), findsNothing,
        reason: 'C62/C76：免费档点「月」不得切换周期');
    expect(find.textContaining('～'), findsOneWidget,
        reason: '周期未切换 → 周区间标题必须还在');

    // ② **给因**：弹「升级解锁」对话框（不静默）。
    expect(find.text('升级解锁'), findsOneWidget,
        reason: 'C62：「不可点」≠ 静默，必须弹出升级引导');
  });

  testWidgets('免费档 · 引导条只出现 1 条（不重复），热力图区块整块不渲染',
      (WidgetTester tester) async {
    final _FakeFocusRepository repository = _FakeFocusRepository();
    await _pumpSection(tester, premium: false, repository: repository);

    // ① C85：全段**恰有 1 条**引导横条（稳定性区块），点得动（非静默）。
    expect(find.byType(ReportUpsellBar), findsOneWidget,
        reason: 'C85：免费档只应有 1 条深度报告引导（原两张竖排大卡已压缩为一条横条）');
    expect(find.text('解锁深度专注报告'), findsOneWidget,
        reason: '横条主文案应唯一（重复出现即说明又变回「两张广告牌」）');
    expect(find.text('近 4 周稳定性 · 全年热力图'), findsOneWidget,
        reason: '横条副文案应唯一（说清买断后多看到什么）');

    // ② 旧大卡文案必须彻底消失（否则就是「压了但没删干净」）。
    expect(find.text('解锁「深度专注报告」'), findsNothing,
        reason: 'C85：PremiumUpsellCard 文案不得再出现（本段已零实例化）');
    expect(find.text('一次买断，永久解锁全部功能'), findsNothing);

    // ③ 热力图区块**整块**不渲染：标题也不许留（否则是「空标题」观感 bug）。
    expect(find.text('专注热力图 · 近 1 年'), findsNothing,
        reason: 'C85：免费档热力图整块（含标题）不渲染，不留空标题');

    // ④ 证明不是「先渲染真数据再遮挡」：组件本身与任何格子都不存在。
    expect(find.byType(ReportHeatmap), findsNothing,
        reason: '免费档不得渲染热力图组件');
    expect(find.byKey(const ValueKey<String>('heatCell_2026-10-17')), findsNothing,
        reason: '免费档不得渲染任何热力格');

    // ⑤ 点「查看详情」→ 弹「升级解锁」（C62「不可点」≠ 静默，引导必须给因）。
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('升级解锁'), findsOneWidget,
        reason: '横条必须给因（弹升级对话框），不得点不动');
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.text('升级解锁'), findsNothing, reason: '对话框应能正常关闭');

    // ⑥ 免费档不做无用功：只应有「本周期」的小跨度查询，没有 365 天窗口。
    expect(repository.rangeSpans.isNotEmpty, isTrue,
        reason: '周档本身要查 7 天数据');
    expect(repository.rangeSpans.every((int span) => span <= 8), isTrue,
        reason: '免费档不得发起 365 天热力图范围查询：${repository.rangeSpans}');
  });

  testWidgets('免费档 · 日/周完整：Hero 分钟、本周分布、护眼统计全部可见',
      (WidgetTester tester) async {
    final _FakeFocusRepository repository = _FakeFocusRepository();
    await _pumpSection(tester, premium: false, repository: repository);

    // Hero：本周 5 天 × 25 分钟 = 125 分钟；进行中周按「已过 6 天」算平均 → 21 分钟。
    expect(find.text('125 分钟'), findsOneWidget, reason: 'Hero 大字应显示本期间分钟');
    expect(find.text('有效专注日 5 天'), findsOneWidget);
    expect(find.text('平均每日 21 分钟'), findsOneWidget);

    // 趋势卡标题：默认周档。
    expect(find.text('本周专注分布'), findsOneWidget);

    // 护眼统计**免费可见**（文案照搬老页）。
    expect(find.text('护眼统计'), findsOneWidget);
    expect(find.text('完成护眼'), findsOneWidget);
    expect(find.text('跳过率'), findsOneWidget);
  });

  testWidgets('买断档 · 全开：无 🔒，月报可切，热力图与稳定性读数登场',
      (WidgetTester tester) async {
    final _FakeFocusRepository repository = _FakeFocusRepository();
    await _pumpSection(tester, premium: true, repository: repository);

    expect(find.byIcon(Icons.lock_outline), findsNothing,
        reason: '买断档四档全开，不应出现锁图标');
    expect(find.text('解锁「深度专注报告」'), findsNothing,
        reason: '买断档不应出现任何付费引导卡');
    expect(find.byType(ReportUpsellBar), findsNothing,
        reason: 'C85：买断档不得出现引导横条（含旧大卡残留）');

    await _tapPeriod(tester, 'month');

    expect(find.text('2026 年 10 月'), findsOneWidget,
        reason: '买断档点「月」应真正切到自然月标题');
    expect(find.text('本月专注分布（按周）'), findsOneWidget);
    expect(find.byType(ReportHeatmap), findsOneWidget,
        reason: '买断档应渲染热力图');
    expect(find.text('专注稳定性 · 近 4 周'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^稳定性 \d+%$')), findsOneWidget,
        reason: '买断档应显示稳定性读数');

    // 热力图真的取到了 365 天窗口（对照免费档的「不查」）。
    expect(repository.rangeSpans.any((int span) => span >= 365), isTrue,
        reason: '买断档应发起 365 天热力图范围查询：${repository.rangeSpans}');
  });

  testWidgets('不翻未来：日档锚定今天时「下一期间」为 disabled',
      (WidgetTester tester) async {
    final _FakeFocusRepository repository = _FakeFocusRepository();
    await _pumpSection(tester, premium: true, repository: repository);

    await _tapPeriod(tester, 'day');

    expect(find.text('今天 · 10月17日'), findsOneWidget,
        reason: '日档标题口径与记录页一致');
    expect(find.text('近 7 日专注分布'), findsOneWidget);

    final IconButton next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.tooltip, '下一期间');
    expect(next.onPressed, isNull,
        reason: '锚定今天时 ▶ 必须置空（不得翻到明天）');

    // 反证：往前一天可以翻（证明不是整体坏死）。
    final IconButton prev = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(prev.onPressed, isNotNull);
  });

  testWidgets('护眼统计不受门控：免费 / 买断两档文案一致', (WidgetTester tester) async {
    final _FakeFocusRepository repository = _FakeFocusRepository();
    await _pumpSection(tester, premium: false, repository: repository);
    expect(find.text('护眼统计'), findsOneWidget);
    // 仓储被设为抛错 → 静默降级为 0 次 / '—'（不阻塞整个报告段）。
    expect(find.text('0 次'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
  });
}
