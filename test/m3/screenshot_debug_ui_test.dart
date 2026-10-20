/// F139（玄参 2026-10-20 截图清单）：**截图会入镜**的调试入口必须全部收口到
/// 单点判据 [shouldShowDebugUi]（花园页 / 专注页）。
///
/// ## 为什么必须有这一层（C101-5「接线守」）
/// [kHideDebugUi] 与 [kDebugMode] 都是**编译期常量**，测试无法在运行时改 —— 所以
/// 「widget 用例挂页面断言调试入口消失」这条路在本仓库**物理不可行**（除非跑两遍
/// 构建）。剩下的唯一办法是**源码守卫**：把「这些入口的显示条件必须是
/// `shouldShowDebugUi(debugMode: kDebugMode, hideForScreenshots: kHideDebugUi)`」
/// 钉死在源码文本上。
///
/// ## 与既有 `test/m4/debug_ui_hide_guard_test.dart` 的分工
///  · 那边管**真值表**（纯函数四种组合）+ 前三处页面（我的 / 家长今日 / 家长设置）
///    的「出现 `shouldShowDebugUi(` 子串」粗守卫；
///  · 本文件管**本轮新接的两处**（花园页 / 专注页），且守卫强度更高：
///    **不是「字符串出现过就算过」**，而是沿源码找到调试入口 widget 的**直接包裹
///    条件**，逐条要求「含 `shouldShowDebugUi(` + 含 `debugMode: kDebugMode` +
///    含 `hideForScreenshots: kHideDebugUi` + 不含 `kDebugMode &&`」。
///    这样以下三种回归都会红：
///      ① 改回裸 `if (kDebugMode …)`（截图开关失效）；
///      ② `debugMode:` 写死成 `true`（release 也会渲染调试入口）；
///      ③ 漏传 `hideForScreenshots`（编译不过，但守卫也兜住）。
///
/// ## 守卫自身必须可证伪
/// 见 `守卫自检` 那一组：同一套判据喂给「改前形态」的合成源码时必须判假 ——
/// 否则「恒真守卫」= 没守卫（上一批教训）。
///
/// ## 覆盖范围：**每一处** anchor，不是第一处（F139 收口第 2 轮，修 QA 的 M8 假阴）
/// 初版守卫用 `code.indexOf(anchor)` 只看**第一处** anchor，于是「在文件里追加第二个
/// 裸入口」能 11 例全绿 —— 调试点有两处、守卫只盯一处，是可预见的复发形态。现在：
///  · `_allIndexOf` 遍历**全部**出现位置，**任一处**不过即红；
///  · 配一道**整文件反查** `_bareKDebugModeIf` = `RegExp(r'if \(\s*kDebugMode\b')`：
///    命中 `if (kDebugMode && …)` 也命中纯 `if (kDebugMode)`（初版正则要求必须有
///    `&&` → 纯裸形态逃逸）；但**不命中** `if (!kDebugMode)` /
///    `if (!kDebugMode || …)`（`\s*` 不吃 `!`）—— 这两类是**合法**的领域闸门
///    （`garden_page.dart` 的诊断日志、`focus_page.dart` 的快进函数），必须继续允许。
///
/// ## 已知取舍：守卫会禁止「谓词抽取」重构
/// 若把条件抽成 `bool get _x => shouldShowDebugUi(...)` 再 `if (_x && …)`，
/// 本守卫会判红（它只认 `if (` 到 anchor 之间的字面条件）。这是**刻意**的：
/// 静态文本守卫无法判定任意谓词是否等价，宁可误红让人来解释，也不放过真回归。
/// 若确需重构，请同步改本守卫并在此登记。
library screenshot_debug_ui_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 工程根（`flutter test` 通常以工程根为 cwd；从 `test/` 目录跑时回退一级）。
String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test') || cwd.endsWith('\\test')
      ? Directory.current.parent.path
      : cwd;
}

/// 读源码并**剔除整行注释**（`//` / `///`）。
///
/// 判据精度沿用 `plant_perk_bypass_guard_test.dart` 的纪律：注释里**提到**
/// `if (kDebugMode …)` 是在解释历史，不是代码旁路点，不得计入违例。
/// 反过来，若注释写成「旧写法 `if (kDebugMode && …)`」，不剔除就会让守卫假阳。
String _codeOf(String relativePath) {
  final List<String> lines =
      File('${_projectRoot()}/$relativePath').readAsStringSync().split('\n');
  final List<String> code = <String>[];
  for (final String line in lines) {
    if (line.trimLeft().startsWith('//')) continue;
    code.add(line);
  }
  return code.join('\n');
}

/// [anchor] 在 [code] 中的**全部**出现位置。
///
/// 🔴 QA M8 的真因之一：初版用 `code.indexOf(anchor)` 只看第一处 → 追加第二个裸
/// 入口视而不见。必须逐处过审。
List<int> _allIndexOf(String code, String anchor) {
  final List<int> hits = <int>[];
  int from = 0;
  while (true) {
    final int idx = code.indexOf(anchor, from);
    if (idx < 0) break;
    hits.add(idx);
    from = idx + anchor.length;
  }
  return hits;
}

/// 条件片段长度上限（字符）。正常写法约 100 字符；超出说明中间隔了别的语句。
const int _kMaxGuardLength = 400;

/// 第 [idx] 处 anchor 之前**最近一个 `if (`** 起的条件片段（到 anchor 前结束）。
///
/// 两重收窄 —— 少了它们会「跨段冒充守卫」而产生**假阴**：
///  · 片段过长（> [_kMaxGuardLength]）：中间已隔了别的语句，即没有紧邻的 `if (`；
///  · 片段里又出现 anchor 本身：已经跨过了**另一个入口**，边界不清 → 不算受守卫。
///
/// 返回 null 表示这一处入口没有紧邻守卫（裸奔），调用方一律判红。
String? _guardFragmentBefore(String code, String anchor, int idx) {
  final int guardIdx = code.lastIndexOf('if (', idx);
  if (guardIdx < 0) return null;
  final String guard = code.substring(guardIdx, idx);
  if (guard.length > _kMaxGuardLength) return null;
  if (guard.contains(anchor)) return null;
  return guard;
}

/// 单处判据：第 [idx] 处入口必须被**单点判据**包裹。
///
/// 四个条件缺一不可（见文件头注释的三种回归）。
bool _entryGuardedAt(String code, String anchor, int idx) {
  final String? guard = _guardFragmentBefore(code, anchor, idx);
  if (guard == null) return false;
  return guard.contains('shouldShowDebugUi(') &&
      guard.contains('debugMode: kDebugMode') &&
      guard.contains('hideForScreenshots: kHideDebugUi') &&
      // 内联旧判据若混在条件里（`kDebugMode && …`）说明改写不彻底。
      !RegExp(r'kDebugMode\s*&&').hasMatch(guard);
}

/// 判据本体：anchor 的**每一处**出现都必须过 [_entryGuardedAt]。
///
/// 一处都找不到也判假 —— 入口被整段删掉同样是回归（截图版也要保留调试能力）。
bool _guardedBySinglePoint(String code, String anchor) {
  final List<int> hits = _allIndexOf(code, anchor);
  if (hits.isEmpty) return false;
  for (final int idx in hits) {
    if (!_entryGuardedAt(code, anchor, idx)) return false;
  }
  return true;
}

/// **整文件反查**：裸 `if (kDebugMode …)`。
///
/// 命中 `if (kDebugMode && …)` **也**命中纯 `if (kDebugMode)`（初版正则要求必须有
/// `&&` → 纯裸形态逃逸，QA M8 的真因之二）。
/// 不命中 `if (!kDebugMode)` / `if (!kDebugMode || …)` —— `!` 不在 `\s*` 内，
/// 那两类是合法的领域闸门。
final RegExp _bareKDebugModeIf = RegExp(r'if \(\s*kDebugMode\b');

void main() {
  const String gardenPage = 'lib/presentation/child/pages/garden_page.dart';
  const String focusPage = 'lib/presentation/child/pages/focus_page.dart';
  const String childShellPage = 'lib/presentation/child/pages/child_shell_page.dart';

  group('守卫自检（恒真守卫 = 没守卫）', () {
    test('改前形态（裸 kDebugMode：含 `&&` 与**纯裸**两种）必须判假', () {
      const String before = '''
        if (kDebugMode && !_loading && _error == null)
          Positioned(
            top: 12,
            right: 12,
            child: BloomDebugEntry(onTap: _openDebugPanel),
          ),
      ''';
      expect(_guardedBySinglePoint(before, 'BloomDebugEntry('), isFalse,
          reason: '旧写法必须判假，否则守卫形同虚设');

      // 🔴 QA M8 真因之一：纯裸 `if (kDebugMode)`（**没有 `&&`**）同样是裸判据，
      // 初版的整文件正则 `if \(kDebugMode\s*&&` 要求必须有 `&&` → 这种形态逃逸。
      const String bareNoAnd = '''
        if (kDebugMode)
          Positioned(child: BloomDebugEntry(onTap: _openDebugPanel)),
      ''';
      expect(_guardedBySinglePoint(bareNoAnd, 'BloomDebugEntry('), isFalse,
          reason: '纯 if (kDebugMode) 也是裸入口，必须判假');
      expect(_bareKDebugModeIf.hasMatch(bareNoAnd), isTrue,
          reason: '整文件反查必须抓得住纯 if (kDebugMode)');
    });

    test('新形态必须判真；但「合法一处 + 追加第二处裸入口」必须判假（QA M8）', () {
      const String after = '''
        if (shouldShowDebugUi(
              debugMode: kDebugMode,
              hideForScreenshots: kHideDebugUi,
            ) &&
            !_loading &&
            _error == null)
          Positioned(
            top: 12,
            right: 12,
            child: BloomDebugEntry(onTap: _openDebugPanel),
          ),
      ''';
      expect(_guardedBySinglePoint(after, 'BloomDebugEntry('), isTrue);

      // 🔴 QA M8 真因之二：追加第二个裸入口（带自己的 `if (kDebugMode)`）。
      const String appendedBare = '''
        if (shouldShowDebugUi(
              debugMode: kDebugMode,
              hideForScreenshots: kHideDebugUi,
            ) &&
            !_loading)
          Positioned(child: BloomDebugEntry(onTap: _openDebugPanel)),
        if (kDebugMode)
          Positioned(child: BloomDebugEntry(onTap: _openDebugPanel)),
      ''';
      expect(_guardedBySinglePoint(appendedBare, 'BloomDebugEntry('), isFalse,
          reason: '遍历全部命中：第二处裸入口必须被抓到');
      expect(_bareKDebugModeIf.hasMatch(appendedBare), isTrue,
          reason: '整文件反查看得见那行 if (kDebugMode)');

      // 更狠：第二处**连 `if` 都没有**（直接裸奔）。靠「片段不得跨过另一个入口」兜住 ——
      // 否则 lastIndexOf('if (') 会跨段拿上一处的合法守卫片段来冒充。
      const String nakedSecond = '''
        if (shouldShowDebugUi(
              debugMode: kDebugMode,
              hideForScreenshots: kHideDebugUi,
            ))
          Positioned(child: BloomDebugEntry(onTap: _openDebugPanel)),
        Positioned(child: BloomDebugEntry(onTap: _openDebugPanel)),
      ''';
      expect(_guardedBySinglePoint(nakedSecond, 'BloomDebugEntry('), isFalse,
          reason: '第二处无任何守卫也必须判假（片段跨过上一个入口 → 判红）');
    });

    test('debugMode 写死成 true 必须判假（release 会渲染调试入口）', () {
      const String hardcoded = '''
        if (shouldShowDebugUi(
              debugMode: true,
              hideForScreenshots: kHideDebugUi,
            )) BloomDebugEntry(onTap: _openDebugPanel),
      ''';
      expect(_guardedBySinglePoint(hardcoded, 'BloomDebugEntry('), isFalse);
    });

    test('漏传 hideForScreenshots 必须判假（截图开关失效）', () {
      const String missing = '''
        if (shouldShowDebugUi(debugMode: kDebugMode))
          BloomDebugEntry(onTap: _openDebugPanel),
      ''';
      expect(_guardedBySinglePoint(missing, 'BloomDebugEntry('), isFalse);
    });

    test('裸奔（前面没有任何 if）必须判假；整文件反查正则的真值表同时在此钉住', () {
      const String naked = 'BloomDebugEntry(onTap: _openDebugPanel),';
      expect(_guardedBySinglePoint(naked, 'BloomDebugEntry('), isFalse);

      // 反查正则（P2-1）：**抓**裸的两种形态，**不误伤** `!kDebugMode` 的两类合法闸门。
      expect(_bareKDebugModeIf.hasMatch('if (kDebugMode && a) x;'), isTrue);
      expect(_bareKDebugModeIf.hasMatch('if (kDebugMode) x;'), isTrue);
      expect(_bareKDebugModeIf.hasMatch('if ( kDebugMode ) x;'), isTrue);
      expect(_bareKDebugModeIf.hasMatch('if (!kDebugMode) return;'), isFalse,
          reason: '`!` 不在 `\\s*` 内 → 合法闸门（garden_page 诊断日志）不得误伤');
      expect(_bareKDebugModeIf.hasMatch('if (!kDebugMode || _finished) return;'),
          isFalse,
          reason: '合法闸门（focus_page 快进函数）不得误伤');
      expect(_bareKDebugModeIf.hasMatch('if (shouldShowDebugUi('), isFalse);
    });
  });

  group('花园页：调试入口已收口（截图主场景，必入镜）', () {
    test('BloomDebugEntry 的包裹条件必须是 shouldShowDebugUi 单点判据', () {
      final String code = _codeOf(gardenPage);
      expect(code.contains('BloomDebugEntry('), isTrue,
          reason: '花园页必须仍渲染「花期调试」入口（未加 define 时行为不变）');
      expect(_guardedBySinglePoint(code, 'BloomDebugEntry('), isTrue,
          reason: '花园页调试入口必须走 shouldShowDebugUi(debugMode: kDebugMode, '
              'hideForScreenshots: kHideDebugUi)，否则截图构建藏不掉');
    });

    test('不得残留裸 `if (kDebugMode …)`（整文件；`if (!kDebugMode)` 合法不误伤）', () {
      final String code = _codeOf(gardenPage);
      expect(_bareKDebugModeIf.hasMatch(code), isFalse,
          reason: '内联判定与单点判据孪生 → 改一处漏一处（截图开关对入口无效）；'
              '不得回退成 `if (kDebugMode && …)` 或纯 `if (kDebugMode)`');
    });

    test('已 import 单点判据所在文件（app_constants.dart）', () {
      final String code = _codeOf(gardenPage);
      expect(
        code.contains("import 'package:sunflower_time/core/constants/app_constants.dart';"),
        isTrue,
        reason: 'shouldShowDebugUi / kHideDebugUi 来自 app_constants.dart',
      );
    });
  });

  group('专注页：护眼调试角标已收口（截图会入镜）', () {
    test('Icons.bug_report 角标的包裹条件必须是 shouldShowDebugUi 单点判据', () {
      final String code = _codeOf(focusPage);
      expect(code.contains('Icons.bug_report'), isTrue,
          reason: '专注页必须仍渲染护眼调试角标（未加 define 时行为不变）');
      expect(_guardedBySinglePoint(code, 'Icons.bug_report'), isTrue,
          reason: '专注页调试角标必须走 shouldShowDebugUi(debugMode: kDebugMode, '
              'hideForScreenshots: kHideDebugUi)');
      // 对称补一道整文件反查（QA M8：专注页同样可能被追加第二个裸入口）。
      // 本文件内 `if (!kDebugMode || _finished) return;` 是**合法**领域闸门，
      // 反查正则的 `\s*` 不吃 `!` → 不误伤（真值表见「裸奔」用例）。
      expect(_bareKDebugModeIf.hasMatch(code), isFalse,
          reason: '专注页不得残留裸 if (kDebugMode …)');
    });

    test('🔴 只藏按钮、不藏函数：`_debugFastForward` 的 kDebugMode 闸门必须保留', () {
      final String code = _codeOf(focusPage);
      expect(code.contains('if (!kDebugMode || _finished) return;'), isTrue,
          reason: '那是处理函数的领域闸门，不是 UI —— 本轮明确**不动**'
              '（按钮藏了函数留着无害，改它会把快进逻辑一并废掉）');
    });
  });

  group('🔴 防沉迷 bypass 逻辑不许被截图开关绑架（child_shell_page.dart）', () {
    test('bypass 仍只看 kDebugMode，**不得**改读 shouldShowDebugUi / kHideDebugUi', () {
      final String code = _codeOf(childShellPage);
      // 两处 bypass 的真源（改动前逐字）：拦截与否只与 kDebugMode + 本地调试开关 /
      // DISABLE_APP_CAP 有关。截图开关是「UI 显示」语义，绝不能顺手拿来放开限时。
      expect(code.contains('!kDebugMode || (!_debugCapBypass && !defineBypass)'),
          isTrue,
          reason: '点 tab 路径的拦截口径被改动 → 可能让截图开关放开防沉迷（业务行为变化）');
      expect(code.contains('if (kDebugMode && (_debugCapBypass || defineBypass))'),
          isTrue,
          reason: '中途踢人路径的 bypass 口径被改动 → 同上');
      expect(code.contains('shouldShowDebugUi'), isFalse,
          reason: '本文件是**业务逻辑**不是 UI：不得接入截图开关');
    });
  });
}
