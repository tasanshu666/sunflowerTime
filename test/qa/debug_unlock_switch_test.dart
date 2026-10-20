/// C85 · 🐞 Debug「会员模式」开关的证据性测试。
///
/// 钉住四件事：
///  ① **可渲染**：`DebugUnlockSwitch` 出现在树上，默认关闭（`value == false`）；
///  ② **双向可切**：点一下 → 权益态变买断 + 开关态 true；再点 → 双双回免费；
///  ③ **真能预览**：开关打开后挂载 `FocusReportSection` → 热力图出现、引导横条消失
///     （证明调试开关**真的**能预览买断态，而不只是改了个布尔值）；
///  ④ **release 不可见**：直读 `parent_settings_page.dart` 源码，调试区必须被
///     `if (kDebugMode)` 包裹（release 构建整段 tree-shake，用户不会看到调试项）。
///
/// F142：文案由「模拟已解锁（仅调试）」改为「会员模式（仅调试）」，副标题改为
/// 「打开即解锁全部付费功能；重启 App 后失效」——作用范围从「预览月/年报告与热力图」
/// 扩展为**全部付费功能**（因为本次修复同时覆盖了领域层配额判定，见
/// `test/m3/f142_premium_mode_switch_test.dart`）。
///
/// ⚠️ 本测试自身跑在 Debug 下，故 ①③ 依赖 `kDebugMode` 的「真」分支是**预期的**，
/// 不做环境绕道（绕道反而会把「开关只在 Debug 挂载」这条约束测丢）。
library debug_unlock_switch_test;

import 'dart:io';

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
import 'package:sunflower_time/presentation/parent/widgets/debug_unlock_switch.dart';
import 'package:sunflower_time/presentation/parent/widgets/focus_report_section.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_heatmap.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_upsell_bar.dart';

/// 固定「现在」：2026-10-17（周六）10:00（与 `focus_report_gating_test` 一致）。
final DateTime _now = DateTime(2026, 10, 17, 10);

/// 工程根（兼容从 `test/qa` 目录直接 `flutter test` 的两种 cwd）。
String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/qa') || cwd.endsWith('\\test\\qa')
      ? Directory.current.parent.parent.path
      : cwd;
}

/// 假专注仓储：同时实现 [FocusRepository] 与 [FocusRangeQuery]（走快路径）。
///
/// 只需「有数据可渲染」即可 —— 本测试关心的是门控联动，不是数值口径
/// （数值口径由 `focus_report_gating_test.dart` 负责）。
class _FakeFocusRepository implements FocusRepository, FocusRangeQuery {
  _FakeFocusRepository() : _sessions = _seedSessions();

  final List<FocusSession> _sessions;

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
    final List<FocusSession> hits = _sessions
        .where((FocusSession s) => !s.start.isBefore(from) && s.start.isBefore(to))
        .toList()
      ..sort((FocusSession a, FocusSession b) => a.start.compareTo(b.start));
    return hits;
  }
}

/// 建一个「报告段可渲染」的容器：专注仓储有数据，护眼两项仓储直接抛错
/// （报告段对护眼是静默降级，不影响任何断言）。
ProviderContainer _buildContainer() {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      focusReportServiceProvider.overrideWithValue(
        FocusReportService(focus: _FakeFocusRepository()),
      ),
      sunlightRepositoryProvider.overrideWith(
        (Ref ref) => throw UnimplementedError('debug switch test: no sunlight repo'),
      ),
      eyeCareLogRepositoryProvider.overrideWith(
        (Ref ref) => throw UnimplementedError('debug switch test: no eye care repo'),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('① 默认关闭：开关行渲染，value == false（不预置解锁）',
      (WidgetTester tester) async {
    final ProviderContainer container = _buildContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: DebugUnlockSwitch()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('会员模式（仅调试）'), findsOneWidget);
    expect(find.text('打开即解锁全部付费功能；重启 App 后失效'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);

    final SwitchListTile tile =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isFalse, reason: '默认必须是关闭态（不得预置解锁）');
    expect(container.read(debugPremiumUnlockProvider), isFalse);
    // 默认免费档（不因渲染开关而改变业务态）。
    expect(container.read(entitlementProvider).tier, EntitlementTier.free);
  });

  testWidgets('② 双向可切：开 → 买断；再关 → 回免费（内存态同步）',
      (WidgetTester tester) async {
    final ProviderContainer container = _buildContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: DebugUnlockSwitch()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 开。
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(container.read(debugPremiumUnlockProvider), isTrue,
        reason: '开关态应写入 debugPremiumUnlockProvider');
    expect(container.read(entitlementProvider).isPremium, isTrue,
        reason: '权益态应同步为买断（否则「预览」无从谈起）');
    expect(container.read(entitlementProvider).productId, 'debug.simulated.unlock',
        reason: '假票据 productId 必须一眼可辨（真机排查用）');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
      reason: 'UI 开关必须回读为打开',
    );

    // 关。
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(container.read(debugPremiumUnlockProvider), isFalse);
    expect(container.read(entitlementProvider), Entitlement.free,
        reason: '关闭必须精确回到 Entitlement.free（不是只改 tier）');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets('③ 联动买断态：开关打开后报告段出现热力图、引导横条消失',
      (WidgetTester tester) async {
    final ProviderContainer container = _buildContainer();

    // 先渲染开关并打开（同一容器 → 状态延续）。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: DebugUnlockSwitch()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(container.read(entitlementProvider).isPremium, isTrue);

    // 再挂载报告段：initState 读到的已是买断档 → 会真的去取 365 天热力图。
    await tester.binding.setSurfaceSize(const Size(600, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: FocusReportSection(now: _now)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReportHeatmap), findsOneWidget,
        reason: '调试开关必须真能预览买断态：热力图应渲染');
    expect(find.byType(ReportUpsellBar), findsNothing,
        reason: '已解锁 → 引导横条零渲染');
    expect(find.text('专注热力图 · 近 1 年'), findsOneWidget,
        reason: '已解锁 → 热力图标题也回来（与免费档「整块不渲染」互为反证）');
    expect(find.textContaining(RegExp(r'^稳定性 \d+%$')), findsOneWidget,
        reason: '稳定性读数出现，进一步证明走了买断分支');
  });

  testWidgets('④ release 不可见（源码守卫）：调试区被 kDebugMode 包裹',
      (WidgetTester tester) async {
    final File page = File(
      '${_projectRoot()}/lib/presentation/parent/pages/parent_settings_page.dart',
    );
    expect(page.existsSync(), isTrue, reason: '设置页源码缺失，守卫失效');

    final String src = page.readAsStringSync();
    // 🔴 2026-10-19（C95）：守卫从内联 `if (kDebugMode)` 统一为
    // `if (shouldShowDebugUi(debugMode: kDebugMode, hideForScreenshots: kHideDebugUi))`
    // —— 截图构建可额外隐藏调试区。两条断言仍钉住「必须传 kDebugMode」，
    // 有人把 debugMode 写死成 true 时本用例同样会红。
    const String guard = 'if (shouldShowDebugUi(';
    expect(src.contains(guard), isTrue,
        reason: '调试区必须包在调试守卫内（release 整段 tree-shake）');
    expect(src.contains('debugMode: kDebugMode'), isTrue,
        reason: '守卫必须真的传 kDebugMode，否则 release 也会渲染调试区');
    expect(src.contains('DebugUnlockSwitch'), isTrue,
        reason: '设置页必须真的挂载调试开关（否则上面那条断言形同虚设）');
    // 弱但有效的顺序证据：守卫出现在 `DebugUnlockSwitch()` **之前**。
    expect(
      src.indexOf(guard) < src.indexOf('DebugUnlockSwitch()'),
      isTrue,
      reason: '`DebugUnlockSwitch` 必须出现在调试守卫分支**内部**',
    );
  });
}
