/// 「家长赠予到账」金色卡 · **按钮文案跟随界面语言**回归（F157-BUG-2）。
///
/// ## 缺陷现象（玄参 2026-10-27 小米 14 Pro 截图）
/// 整界面 English：卡片标题 `🎁 Sunshine from Mom & Dad!`、条目 `Parent gift`、
/// 合计 `The sunshine is in your garden — go plant something!` —— **只有底部按钮
/// 是中文「知道啦」**。
///
/// ## 根因
/// `gold_notice_dialog.dart` 里 `GoldNoticeStyle.confirmLabel = '知道啦'` 是**硬编码
/// 中文常量**，且被当成 [GoldNoticeDialog.confirmLabel] 的默认值 —— 调用方（赠予卡
/// 等 5 处）没传自定义 label 就吃了这个中文默认值。
///
/// ## 修复口径（本文件钉死的四条）
///  ① 该常量**退役**：渲染时 `confirmLabel == null` → 走 `l10nOf(context).shared_got_it`；
///  ② 各调用点显式传 `l10n.shared_got_it`（赠予 / 核销 / 拒绝 / 任务审批 / 锁标提示）；
///  ③ **中文文案逐字不变**（既有 `parent_gift_notice_test` / `task_verified_notice_test`
///     / `c91` 等十余条断言依赖「知道啦」）；
///  ④ **F157-A2 新增**：源码守卫 ×2 ——
///     · `③` 全仓不得再出现裸字面量 `'知道啦'`（覆盖 `presentation/parent/**` + `shared/**`，
///       并断言两棵子树确实被扫到）；
///     · `④` **每个** `showGoldNoticeDialog(` 调用点必须写 `confirmLabel:`、
///       **每个** `showChildConfirmCard(` 调用点必须写 `cancelLabel:`（带计数自检）。
///
/// ⚠️ 关于 ① 的一个**重要修正**（QA 复验实测）：`?? l10nOf(context).xxx` 在弹窗里
/// **不是**语言感知兜底 —— 弹窗 builder 的 context 挂在根 Navigator 上，不在页级
/// `L10nScope` 之下，`l10nOf` 拿不到页面语言，裸宿主回落 `AppLocalizationsZh`
/// （等同中文）。所以兜底只是「不崩」，**调用方必须显式传**，这正是 ④ 的存在理由。
///
/// 本文件用**真实外壳 + 真实通知链路**（不是直接挂组件）双向验证 en / zh。
library gold_notice_confirm_label_l10n_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/shared/child_route_observer.dart';

/// 有界 pump（shell 宿主禁 `pumpAndSettle`：无限漂动 / 呼吸动画，C44e 纪律）。
Future<void> _pumpFrames(WidgetTester tester,
    {int frames = 14, int stepMs = 100}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(Duration(milliseconds: stepMs));
  }
}

/// 全文件字符级的「注释 / 字符串」掩码（一次扫描，供 [_callArgWindows] 查询）。
///
/// 为什么不按行判断：`//` 可能出现在字符串里（`'http://x'`），`/*` 可能跨行，
/// 按行判断一定出错。这里对**整份源码**跑一遍状态机，逐字符打标：
///  · [inComment]：该字符属于 `//` 行注释（含 `///` 文档注释）或 `/* */` 块注释；
///  · [inString]：该字符属于单 / 双引号字符串字面量（含引号本身与 `\` 转义体）。
///
/// 两个掩码互斥：注释里的字符不会再被标成字符串（状态机先进注释态就一路吃到结束）。
class _SrcMasks {
  _SrcMasks(int length)
      : inComment = List<bool>.filled(length, false),
        inString = List<bool>.filled(length, false);

  /// 逐字符：是否属于注释。
  final List<bool> inComment;

  /// 逐字符：是否属于字符串字面量。
  final List<bool> inString;
}

/// 对整份源码跑一遍状态机，产出 [_SrcMasks]。
_SrcMasks _scanMasks(String src) {
  final _SrcMasks masks = _SrcMasks(src.length);
  int i = 0;
  bool inSingle = false;
  bool inDouble = false;
  bool escaped = false;
  bool inLineComment = false;
  bool inBlockComment = false;
  while (i < src.length) {
    final String c = src[i];
    final String next = i + 1 < src.length ? src[i + 1] : '';

    if (inLineComment) {
      masks.inComment[i] = true;
      if (c == '\n') inLineComment = false;
      i++;
      continue;
    }
    if (inBlockComment) {
      masks.inComment[i] = true;
      if (c == '*' && next == '/') {
        masks.inComment[i + 1] = true;
        inBlockComment = false;
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    if (inSingle || inDouble) {
      masks.inString[i] = true;
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (inSingle && c == "'") {
        inSingle = false;
      } else if (inDouble && c == '"') {
        inDouble = false;
      }
      i++;
      continue;
    }
    if (c == '/' && next == '/') {
      masks.inComment[i] = true;
      masks.inComment[i + 1] = true;
      inLineComment = true;
      i += 2;
      continue;
    }
    if (c == '/' && next == '*') {
      masks.inComment[i] = true;
      masks.inComment[i + 1] = true;
      inBlockComment = true;
      i += 2;
      continue;
    }
    if (c == "'") {
      masks.inString[i] = true;
      inSingle = true;
      i++;
      continue;
    }
    if (c == '"') {
      masks.inString[i] = true;
      inDouble = true;
      i++;
      continue;
    }
    i++;
  }
  return masks;
}

/// 扫出一段源码里 [needle]（形如 `showGoldNoticeDialog(`，末尾必是左括号）的
/// **每一次真实调用**的实参窗口，并**已剥掉 `//` 行注释与 `/* */` 块注释**。
///
/// ## 为什么不用「到下一个 `);` 为止」
/// 调用实参里常有嵌套调用（`_rewardRows(...)` / `_items(...)`），`);` 会提前截断，
/// 导致窗口不完整 → 守卫漏判。这里做**括号配平**取到真正的右括号。
///
/// ## 三处必须跳过（否则配平会错位）—— 由 [_scanMasks] 的掩码统一供给
///  · **字符串字面量**里的括号；
///  · **`//` 行注释**里的括号（调用点常带 `// F157-BUG-2` 之类尾注）；
///  · **`/* */` 块注释**里的括号。
///
/// ## 🔴 两条「防假检查 / 防假绿」硬判据（F157-A2 QA 复验补强）
///  ① **命中位置必须在注释外**：`masks.inComment[at]` 为真直接丢弃。
///     为什么必须有：`gold_notice_dialog.dart` 的**文档注释里**举例写了
///     `` `showGoldNoticeDialog(` ``（含左括号）—— 不做这一步，它会被当成第 7 个
///     「调用点」，窗口一路吞到文件后半（里面有真实代码的 `confirmLabel:`），
///     于是「不会假红，但也不是真检查」，还让计数与基线注释对不上。
///  ② **返回「剥注释后的代码」而不是原文**：否则有人把 `confirmLabel: xxx,` 用
///     `//` 注释掉（**能编译通过**、行为回退成中文兜底），原文里仍有这串字符 →
///     守卫会**假绿**。
///
/// ## 声明不算调用点
/// `Future<void> showGoldNoticeDialog(` / `Future<bool?> showChildConfirmCard({`
/// 是**函数声明**，自然没有 `confirmLabel:` / `cancelLabel:`，必须排除。
/// 判据是复合的（单靠 `Future<` 会误伤箭头函数体）：
/// `needle` 前 40 个字符里出现 `Future<` **且**不含 `{` / `;` / `=>`。
///  · 真声明 `Future<bool?> showChildConfirmCard({` → 命中排除 ✅；
///  · 箭头函数体 `Future<bool?> f() => showChildConfirmCard(` → 含 `=>` → **保留** ✅；
///  · 普通调用 `final bool? ok = await showChildConfirmCard(` → 无 `Future<` → 保留 ✅。
List<String> _callArgWindows(String src, String needle) {
  final _SrcMasks masks = _scanMasks(src);
  final List<String> windows = <String>[];
  int from = 0;
  while (true) {
    final int at = src.indexOf(needle, from);
    if (at < 0) break;
    from = at + 1;
    // ① 注释里的「调用」不算调用点（文档注释举例、被注释掉的旧代码都走这条）。
    if (masks.inComment[at]) continue;
    // ② 函数声明不算调用点。
    final int declFrom = at - 40 < 0 ? 0 : at - 40;
    final String before = src.substring(declFrom, at);
    if (before.contains('Future<') &&
        !before.contains('{') &&
        !before.contains(';') &&
        !before.contains('=>')) {
      continue;
    }

    final int open = at + needle.length - 1; // needle 末字符就是 '('
    final StringBuffer code = StringBuffer(); // 只收「非注释」字符
    int depth = 0;
    int i = open;
    while (i < src.length) {
      if (masks.inComment[i]) {
        i++;
        continue;
      }
      final String c = src[i];
      // 字符串里的括号不参与配平（否则窗口会被字符串里的 ')' 提前截断）。
      if (!masks.inString[i]) {
        if (c == '(') {
          depth++;
        } else if (c == ')') {
          depth--;
          if (depth == 0) {
            code.write(c);
            break;
          }
        }
      }
      code.write(c);
      i++;
    }
    windows.add(code.toString());
  }
  return windows;
}

/// 把多行实参压成一行，用于失败信息里一眼看出是哪一处调用。
String _squash(String s) {
  final String flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= 140 ? flat : '${flat.substring(0, 140)}…';
}

const AppSettings _settings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 60,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

SunlightEntry _gift(String id, {double net = 12.0}) => SunlightEntry(
      id: id,
      ts: DateTime(2026, 10, 27, 12),
      type: SunlightType.earn,
      gross: net,
      net: net,
      balanceAfter: net,
      refType: 'parent_gift',
      refId: null,
      dayKey: '2026-10-27',
    );

class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository({this.latest});
  SunlightEntry? latest;

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => latest;
  @override
  Future<double> append(SunlightEntry entry) async => 999.0;
  @override
  Future<double> balance() async => 999.0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings;
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeFocusRepository implements FocusRepository {
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
      totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakeTaskRepository implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakePlantRepository implements PlantRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakeRewardRepository implements RewardRepository {
  @override
  Future<List<RewardTemplate>> templates() async => <RewardTemplate>[];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakeTrackingRepository implements TrackingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未打桩');
}

class _FakeWeeklyPoolRepository implements WeeklyPoolRepository {
  @override
  Future<WeeklyPool?> get(String weekKey) async => null;
  @override
  Future<void> upsert(WeeklyPool pool) async {}
  @override
  List<String> weeksBetween(String fromKey, String toKey) => const <String>[];
}

List<Override> _overrides(SharedPreferences prefs, SunlightRepository sunlight) =>
    <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      sunlightRepositoryProvider.overrideWithValue(sunlight),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      rewardRepositoryProvider.overrideWithValue(_FakeRewardRepository()),
      trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
      weeklyPoolRepositoryProvider
          .overrideWithValue(_FakeWeeklyPoolRepository()),
    ];

Future<void> _pumpShell(WidgetTester tester, SunlightRepository ledger) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(prefs, ledger),
      child: MaterialApp(
        navigatorObservers: <NavigatorObserver>[childShellRouteObserver],
        home: const ChildShellPage(),
      ),
    ),
  );
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppLocaleController.init(AppLanguage.system);
  });

  testWidgets('① 英文界面：赠予卡按钮 = `Got it`（不再是「知道啦」）',
      (WidgetTester tester) async {
    AppLocaleController.init(AppLanguage.en);
    final _FakeSunlightRepository ledger =
        _FakeSunlightRepository(latest: _gift('gift-en'));

    await _pumpShell(tester, ledger);

    // 卡片真的弹了（标题走 en ARB，顺带证明整卡是英文语境）。
    expect(find.textContaining('Sunshine from Mom & Dad'), findsOneWidget,
        reason: '英文赠予卡标题应在场');
    expect(find.text('Got it'), findsOneWidget,
        reason: '🔴 F157-BUG-2：英文界面按钮必须是 `Got it`');
    expect(find.text('知道啦'), findsNothing,
        reason: '🔴 英文界面**绝不能**再出现硬编码中文「知道啦」');
  });

  testWidgets('② 中文界面：赠予卡按钮仍是「知道啦」（文案逐字不变）',
      (WidgetTester tester) async {
    AppLocaleController.init(AppLanguage.zh);
    final _FakeSunlightRepository ledger =
        _FakeSunlightRepository(latest: _gift('gift-zh'));

    await _pumpShell(tester, ledger);

    expect(find.textContaining('爸爸妈妈送来阳光啦'), findsOneWidget,
        reason: '中文赠予卡标题应在场');
    expect(find.text('知道啦'), findsOneWidget,
        reason: '中文侧文案逐字不变（既有十余条测试依赖「知道啦」）');
    expect(find.text('Got it'), findsNothing, reason: '中文界面不该出现英文按钮');
  });

  testWidgets('③ 源码守卫：lib 里不得再有硬编码「知道啦」字面量', (WidgetTester tester) async {
    // 曾经的根因就是 `static const String confirmLabel = '知道啦'`（以及任何
    // `Text('知道啦')` 直写）。此处扫 **lib/**（不含 l10n/generated，那里是 ARB
    // 的产物、本该有中文）→ 出现即代表又有人在代码里硬编码了中文文案。
    //
    // F157-A2 扩面（主理人要求）：**必须确认覆盖 `lib/presentation/parent/**` 与
    // `lib/shared/**`** —— 这两棵子树是「家长赠予」链路的实际落点，也是上一轮
    // 扫描清单里最容易被漏掉的地方。本用例不只靠 `recursive: true` 的「理论上
    // 覆盖」，还把两棵子树的可达性**断言出来**（见下方 parentScanned /
    // sharedScanned）——否则将来目录改名 / 文件搬走后，守卫会静默变成空转。
    final Directory libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '测试应在工程根目录运行');

    final List<String> offenders = <String>[];
    /// 命中的「裸字面量」两种引号形态都要抓：`'知道啦'` 与 `"知道啦"`。
    bool hasBareLiteral(String line) =>
        line.contains("'知道啦'") || line.contains('"知道啦"');

    int parentScanned = 0;
    int sharedScanned = 0;
    int totalScanned = 0;
    for (final FileSystemEntity entity
        in libDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String path = entity.path.replaceAll(r'\', '/');
      // ARB 产物（generated/）与 ARB 源文件本身就是文案来源，跳过。
      if (path.contains('/l10n/generated/')) continue;
      if (path.endsWith('.arb')) continue;
      totalScanned++;
      if (path.contains('/presentation/parent/')) parentScanned++;
      if (path.contains('/shared/')) sharedScanned++;
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (!hasBareLiteral(line)) continue;
        // 只认「代码里的字符串字面量」：注释里提到「知道啦」（说明历史 bug）不算。
        final int quote = line.indexOf('知道啦');
        final int comment = line.indexOf('//');
        if (comment >= 0 && comment < quote) continue;
        offenders.add('$path:${i + 1}: ${line.trim()}');
      }
    }

    // ── 守卫自检：三棵树都必须被真的扫到，否则「全绿」毫无意义 ──────────────
    expect(totalScanned, greaterThan(100),
        reason: '扫到的 .dart 文件过少（$totalScanned）→ 路径 / 递归参数被改坏了');
    expect(parentScanned, greaterThan(0),
        reason: '`lib/presentation/parent/**` 一个文件都没扫到 → 覆盖声明不成立');
    expect(sharedScanned, greaterThan(0),
        reason: '`lib/shared/**` 一个文件都没扫到 → 覆盖声明不成立');

    expect(
      offenders,
      isEmpty,
      reason: 'lib 里出现硬编码「知道啦」→ BUG-2 的根因形态复发：\n'
          '${offenders.join('\n')}',
    );
  });

  testWidgets('④ 源码守卫：每个弹窗调用点都必须显式传文案槽位',
      (WidgetTester tester) async {
    // ## 为什么必须有这条（QA 复验实测出的隐患）
    // 弹窗 builder 的 context 挂在**根 Navigator** 上，不在页级 L10nScope 之下 →
    // 壳内 `l10nOf(context)` 拿不到页面语言，裸宿主直接回落中文。也就是说
    // `?? l10nOf(context).xxx` **不是语言感知兜底，等同中文兜底**。
    //
    // 今天不漏，只因为 6 个 `showGoldNoticeDialog` + 8 个 `showChildConfirmCard`
    // 调用点**都显式传了**。但只要有人新增调用忘了传，英文界面立刻回到 BUG-2 形态；
    // 而「忘传」不会有任何编译错误、也没有任何运行期异常。→ 必须源码守卫。
    //
    // ## 判据
    // 对每一次调用取其**实参原文窗口**（括号配平，跳过字符串 / 行注释里的括号），
    // 断言窗口内出现 `confirmLabel:` / `cancelLabel:`。声明（`Future<...> showX(`）
    // 不算调用点。
    final Directory libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '测试应在工程根目录运行');

    final List<String> goldMissing = <String>[];
    final List<String> cardMissing = <String>[];
    int goldSites = 0;
    int cardSites = 0;

    for (final FileSystemEntity entity
        in libDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String path = entity.path.replaceAll(r'\', '/');
      if (path.contains('/l10n/generated/')) continue;
      final String src = entity.readAsStringSync();

      for (final String window
          in _callArgWindows(src, 'showGoldNoticeDialog(')) {
        goldSites++;
        if (!window.contains('confirmLabel:')) {
          goldMissing.add('$path → ${_squash(window)}');
        }
      }
      for (final String window
          in _callArgWindows(src, 'showChildConfirmCard(')) {
        cardSites++;
        if (!window.contains('cancelLabel:')) {
          cardMissing.add('$path → ${_squash(window)}');
        }
      }
    }

    // ── 计数断言：防止「一个调用点都没扫到」时空转全绿 ──────────────────────
    // 实测基线：`showGoldNoticeDialog(` 6 处、`showChildConfirmCard(` 8 处。
    // 用 `> 5` 而不是 `== N`：将来新增调用点不该让守卫变红（那是正常的），
    // 但**扫不到**必须红。
    // ── 计数断言：防止「一个调用点都没扫到」时空转全绿 ──────────────────────
    // 实测基线（**硬化后重新实测**，2026-10-27）：
    //   · `showGoldNoticeDialog(` 真实调用点 **6** 处；
    //     （硬化前会多算 1 处 —— `gold_notice_dialog.dart` 的**文档注释里**举例写了
    //      `` `showGoldNoticeDialog(` ``，被当成第 7 个「调用点」，窗口还一路吞了
    //      9000+ 字符到文件后半。现在由 `masks.inComment[at]` 判据拦掉。）
    //   · `showChildConfirmCard(` 真实调用点 **8** 处
    //     （`premium_gate` / `eye_care_page` / `focus_page` / `garden_page`×2 /
    //      `store_page` / `plant_care_sheet` / `plant_confirm_dialog`）。
    // 用 `> 5` 而不是 `== 6/8`：将来**新增**调用点不该让守卫变红（那是正常的），
    // 但**扫不到**必须红。
    expect(goldSites, greaterThan(5),
        reason: '只扫到 $goldSites 个 `showGoldNoticeDialog(` 调用点（实测基线 6）'
            '→ 扫描逻辑（注释排除 / 配平 / 声明排除）已失效，本守卫在空转');
    expect(cardSites, greaterThan(5),
        reason: '只扫到 $cardSites 个 `showChildConfirmCard(` 调用点（实测基线 8）'
            '→ 扫描逻辑（注释排除 / 配平 / 声明排除）已失效，本守卫在空转');

    expect(
      goldMissing,
      isEmpty,
      reason: '以下 `showGoldNoticeDialog(` 调用点没传 `confirmLabel:` ——\n'
          '兜底在弹窗 context 里等同中文，英文界面会回到 BUG-2 形态。\n'
          '修法：`confirmLabel: l10n.shared_got_it`（在页面 scope 内取好再传）。\n'
          '${goldMissing.join('\n')}',
    );
    expect(
      cardMissing,
      isEmpty,
      reason: '以下 `showChildConfirmCard(` 调用点没传 `cancelLabel:` ——\n'
          '修法：`cancelLabel: l10n.shared_cancel`。\n'
          '${cardMissing.join('\n')}',
    );
  });
}
