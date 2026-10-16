/// C74 · 专注等级**口径巡检护栏**（grep 级断言，防止数值孪生 / 越界 / 付费门控）。
///
/// 钉住八条（对应设计 §5.24.11 的 TC-19 ~ TC-22 + 新增的 40 级口径；**C78 修订**）：
///  ① **常量冻结**：`kTodayCardTopRatio` = 0.40、`kTodayBgPanelTargetRatio` = 0.37（C67）；
///  ② **阶梯表逐条核对**：40 档门槛 = C74 §2 的小时表 × 60；
///  ③ **称号节点**：9 个节点；**C78 后零阳光、零账本行**（经济层删除，
///     删除守卫另见 `c78_economy_removal_guard_test.dart`）；
///  ④ **数值单点**：门槛分钟 / 称号文案 / `'focus_level_up'` 在 `lib/` 里**只出现在
///     `prd_params.dart`**（其余文件一律引用常量）；
///  ⑤ **只在今日页**：结算页 / 我的页 / 家长端**不引用**等级组件与服务；
///  ⑥ **等级/称号不做门控，专属属性门控**（C80 修订 C74 §4）：等级数据/逻辑链路
///     （域 + 存储 + 今日页）零权益引用；仅展示文件（徽章 / 演出卡）允许为
///     `FeatureKey.titlePerks` 锁标读 `entitlementProvider`；
///  ⑦ **分层纪律**：`domain` 的等级文件**零 flutter / 零插件 import**；
///  ⑧ **账本映射**：`child_sunlight_history_page.dart` 已登记 `kFocusLevelUpRefType`。
library focus_level_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart'
    show kTodayBgPanelTargetRatio, kTodayCardTopRatio;

/// 工程根目录（本测试位于 `<root>/test/qa/`）。
Directory get _root => Directory.current;

/// 读取 `lib/` 下某文件的源码文本。
String _read(String relative) =>
    File('${_root.path}/$relative').readAsStringSync();

/// 遍历 `lib/` 下全部 `.dart` 文件。
List<File> _libDartFiles() => Directory('${_root.path}/lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart'))
    .toList();

/// C74 §2 的小时阶梯表（**宪法原文**，用于反查代码里的分钟常量是否逐条一致）。
const List<int> _c74Hours = <int>[
  1, 2, 4, 6, 8, 11, 15, 19, 23, 28,
  33, 38, 44, 51, 57, 65, 72, 80, 89, 98,
  107, 117, 127, 138, 149, 160, 172, 184, 197, 210,
  224, 238, 252, 267, 282, 298, 314, 331, 348, 365,
];

/// C74 §3 的 9 个称号（宪法原文）。
const List<String> _c74Titles = <String>[
  '专注小萌芽',
  '专注小苗苗',
  '静心小书童',
  '时光小卫士',
  '专心小骑士',
  '守时小星使',
  '专注小法师',
  '星辰守护者',
  '时光大贤者',
];

/// 本功能涉及的 lib 文件（门槛字面量巡检的范围）。
const List<String> _c74Files = <String>[
  'lib/domain/services/focus_level_service.dart',
  'lib/domain/entities/focus_level.dart',
  'lib/domain/repositories/focus_level_store.dart',
  'lib/data/local/focus_level_prefs_store.dart',
  'lib/presentation/child/widgets/focus_level_badge.dart',
  'lib/presentation/child/widgets/level_up_fx_overlay.dart',
  'lib/presentation/child/pages/child_today_page.dart',
  'lib/presentation/child/pages/child_sunlight_history_page.dart',
];

void main() {
  test('① C67 冻结常量未改动', () {
    expect(kTodayCardTopRatio, 0.40);
    expect(kTodayBgPanelTargetRatio, 0.37);
  });

  test('② 40 档门槛逐条 = C74 §2 小时表 × 60（且严格递增）', () {
    expect(kFocusLevelThresholdMinutes.length, 40);
    for (int i = 0; i < _c74Hours.length; i++) {
      expect(
        kFocusLevelThresholdMinutes[i],
        _c74Hours[i] * 60,
        reason: 'Lv.${i + 1} 门槛应为 ${_c74Hours[i]} 小时 = ${_c74Hours[i] * 60} 分钟',
      );
      if (i > 0) {
        expect(
          kFocusLevelThresholdMinutes[i],
          greaterThan(kFocusLevelThresholdMinutes[i - 1]),
        );
      }
    }
    expect(levelOfMinutes(_c74Hours.first * 60.0), 1);
    expect(levelOfMinutes(_c74Hours.last * 60.0), kFocusLevelMaxLevel);
    expect(levelOfMinutes(_c74Hours.last * 60.0 - 0.1), kFocusLevelMaxLevel - 1);
  });

  test('③ 9 个称号节点（C78：零阳光、零账本行，原 102☀ 阶梯废止）', () {
    expect(kFocusLevelTitleLevels, <int>[1, 5, 10, 15, 20, 25, 30, 35, 40]);
    expect(kFocusLevelTitles, _c74Titles);
    // C78：称号节点只解锁专属属性（节点判定仍在，供演出/属性派生用）。
    for (final int lv in kFocusLevelTitleLevels) {
      expect(isTitleLevelOf(lv), isTrue, reason: 'Lv.$lv 仍是称号节点');
    }
    final int ordinary = <int>[
      for (int lv = 1; lv <= kFocusLevelMaxLevel; lv++)
        if (!isTitleLevelOf(lv)) lv,
    ].length;
    expect(ordinary, 31);
  });

  test('④ 数值单点：门槛分钟 / 称号文案 / refType 只出现在 prd_params.dart', () {
    final List<File> files = _libDartFiles()
        .where((File f) => !f.path.endsWith('core/constants/prd_params.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final File f in files) {
      final String src = f.readAsStringSync();
      // 称号文案（9 个，唯一性强 → 全仓扫描不会假红）。
      for (final String title in _c74Titles) {
        expect(src.contains(title), isFalse,
            reason: '${f.path} 出现称号文案「$title」（必须引用常量）');
      }
      // refType 字符串值。
      expect(src.contains("'focus_level_up'"), isFalse,
          reason: '${f.path} 出现 refType 字面量（必须引用 kFocusLevelUpRefType）');
    }

    // 门槛分钟：只扫**本功能涉及的 lib 文件**（全仓扫会撞上既有无关数字，如花园页
    // 动画时长 900，属假红）。同样跳过 ≤ 480 的小档（与日上限 60/90/120 等撞号）。
    for (final String path in _c74Files) {
      final String src = _read(path);
      for (final int minutes in kFocusLevelThresholdMinutes) {
        if (minutes < 900) continue;
        // ⚠️ 必须**整数字匹配**：否则 900 会被 21900 这类数字的子串命中（假红）。
        expect(RegExp('(?<!\\d)$minutes(?!\\d)').hasMatch(src), isFalse,
            reason: '$path 出现阶梯分钟字面量 $minutes（必须引用常量）');
      }
    }
  });

  test('⑤ 只在今日页：结算页 / 我的页 / 家长端不引用等级组件与服务', () {
    final List<String> forbidden = <String>[
      'lib/presentation/child/pages/settle_page.dart',
      'lib/presentation/child/pages/child_profile_page.dart',
    ];
    // ⚠️ 2026-10-14 例外（玄参明确要）：**我的页**新增了 kDebugMode 调试区，里面
    // 有「+30 分钟 / 跳到下一个称号节点 / 重置锚点」三个按钮，必须调用真实的
    // `FocusLevelService.settle()` 才能测演出。这是**调试入口**，不是常驻等级展示
    // —— C74 §6「等级只在今日页展示」约束的是**展示**，不含调试按钮。
    // 故本页改判：允许 `FocusLevel*` 引用，但**必须**全部落在 `if (kDebugMode)` 里。
    const String profilePage =
        'lib/presentation/child/pages/child_profile_page.dart';
    for (final String path in forbidden) {
      final String src = _read(path);
      if (path == profilePage) {
        expect(src.contains('FocusLevelBadge'), isFalse,
            reason: '$path 不得引用等级徽章（调试区只允许结算/演出，不展示徽章）');
        // 调试 helper 可以**定义**在守卫之外（Dart 方法必须定义在类体里），
        // 但**调用点**必须全部落在 `if (kDebugMode)` 区块内 —— 否则 release 构建
        // 也会有代码路径触发结算/演出。
        final List<String> lines = src.split('\n');
        final int guardLine =
            lines.indexWhere((String l) => l.contains('if (kDebugMode)'));
        expect(guardLine, greaterThan(-1),
            reason: '$path 必须有 kDebugMode 守卫');
        // `Future<void> _debugXxx(` 起 → 进入某个调试 helper 的方法体；
        // 顶格两空格的 `}` → 方法结束。helper 之间的**互相调用**是允许的
        // （整条链只有 kDebugMode 区块里的按钮能触发）。
        bool insideDebugMethod = false;
        for (int i = 0; i < guardLine; i++) {
          final String t = lines[i].trimLeft();
          if (t.startsWith('Future<void> _debug')) insideDebugMethod = true;
          if (lines[i] == '  }') insideDebugMethod = false;
          if (t.startsWith('//')) continue; // 文档注释
          if (insideDebugMethod) continue; // helper 内部（含互相调用）不算调用点
          for (final String helper in <String>[
            '_debugAddFocusMinutes',
            '_debugJumpToNextTitleNode',
            '_debugResetLevelAnchor',
          ]) {
            if (!lines[i].contains(helper)) continue;
            // 允许且仅允许**方法声明行**出现在守卫之前。
            expect(t.startsWith('Future<void> $helper('), isTrue,
                reason: '$path:${i + 1} 的 $helper 调用点必须在 kDebugMode 区块内');
          }
        }
        continue;
      }
      expect(src.contains('FocusLevelBadge'), isFalse, reason: '$path 不得引用等级徽章');
      expect(src.contains('LevelUpFxOverlay'), isFalse, reason: '$path 不得引用升级演出');
      expect(src.contains('FocusLevelService'), isFalse, reason: '$path 不得引用等级服务');
      expect(src.contains('focusLevelServiceProvider'), isFalse,
          reason: '$path 不得引用等级 provider');
    }
    // 调试入口的**可见性**红线：三个按钮必须全部写在 kDebugMode 分支里。
    final String profile = _read(profilePage);
    expect(profile.contains('DEBUG 累计专注 +30 分钟（模拟）'), isTrue);
    expect(profile.contains('DEBUG 直接跳到下一个称号节点'), isTrue);
    expect(profile.contains('DEBUG 重置等级结算锚点'), isTrue);
    final List<File> parentFiles = _libDartFiles()
        .where((File f) => f.path.contains('/presentation/parent/'))
        .toList();
    expect(parentFiles, isNotEmpty);
    for (final File f in parentFiles) {
      final String src = f.readAsStringSync();
      expect(src.contains('FocusLevel'), isFalse,
          reason: '${f.path} 家长端不得引用任何等级组件');
      expect(src.contains('LevelUpFx'), isFalse, reason: '${f.path} 不得引用升级演出');
    }
  });

  test('⑥ C80 修订：等级/称号链路不做门控，仅 titlePerks 专属属性门控', () {
    // 🔴 C80 修订 C74 §4（原「全体系不做门控」）：等级/称号**本身**仍免费不做门控，
    //    仅「称号专属属性」（`FeatureKey.titlePerks`）为付费解锁 —— 故本巡检分两层：
    //  (a) 等级**数据 / 逻辑**链路（域 + 存储 + 今日页）：**零权益引用**（主体不变）；
    //  (b) 展示文件（徽章 / 演出卡）：允许为**锁标展示**读 `entitlementProvider`，但
    //      **只允许** `FeatureKey.titlePerks` 这一处门控，且绝不含 PremiumGate /
    //      EntitlementService / EntitlementTier（门控不散落）。
    final List<String> pureChain = <String>[
      'lib/domain/services/focus_level_service.dart',
      'lib/domain/entities/focus_level.dart',
      'lib/domain/repositories/focus_level_store.dart',
      'lib/data/local/focus_level_prefs_store.dart',
      'lib/presentation/child/pages/child_today_page.dart',
    ];
    for (final String path in pureChain) {
      final String src = _read(path);
      expect(src.contains('EntitlementService'), isFalse, reason: '$path 出现付费服务');
      expect(src.contains('PremiumGate'), isFalse, reason: '$path 出现付费门控');
      expect(src.contains('EntitlementTier'), isFalse, reason: '$path 出现权益档位');
      expect(src.contains('entitlementProvider'), isFalse, reason: '$path 出现权益 provider');
      expect(src.contains('FeatureKey'), isFalse, reason: '$path 等级逻辑链路不得读权益能力键');
    }

    // (b) 展示文件：允许 titlePerks 锁标，其余门控一律禁止。
    final List<String> displayChain = <String>[
      'lib/presentation/child/widgets/focus_level_badge.dart',
      'lib/presentation/child/widgets/level_up_fx_overlay.dart',
    ];
    for (final String path in displayChain) {
      final String src = _read(path);
      expect(src.contains('PremiumGate'), isFalse,
          reason: '$path 出现 PremiumGate（门控散落，应只读矩阵单点 featureAllowedFor）');
      expect(src.contains('EntitlementService'), isFalse, reason: '$path 出现付费服务');
      expect(src.contains('EntitlementTier'), isFalse, reason: '$path 出现权益档位');
      // 读 entitlementProvider 仅当用于 FeatureKey.titlePerks 锁标（C80 唯一允许的门控点）。
      if (src.contains('entitlementProvider')) {
        expect(src.contains('FeatureKey.titlePerks'), isTrue,
            reason: '$path 读 entitlementProvider 只允许用于 FeatureKey.titlePerks 锁标（C80）');
      }
    }
  });

  test('⑦ 分层纪律：domain 层等级文件零 flutter / 零插件 import', () {
    final List<String> domain = <String>[
      'lib/domain/services/focus_level_service.dart',
      'lib/domain/entities/focus_level.dart',
      'lib/domain/repositories/focus_level_store.dart',
    ];
    for (final String path in domain) {
      final List<String> imports = _read(path)
          .split('\n')
          .where((String line) => line.trimLeft().startsWith('import '))
          .toList();
      expect(
        imports.any((String l) => l.contains('package:flutter/')),
        isFalse,
        reason: '$path 不得 import flutter（纯 Dart 底线）',
      );
      expect(
        imports.any((String l) => l.contains('package:shared_preferences')),
        isFalse,
        reason: '$path 不得 import 插件（插件只收敛在 data/local）',
      );
    }
    // SharedPreferences 只允许出现在 data/local 的实现里。
    final String impl = _read('lib/data/local/focus_level_prefs_store.dart');
    expect(impl.contains('package:shared_preferences'), isTrue);
  });

  test('⑧ 账本映射：孩子端「阳光来源记录」已登记 kFocusLevelUpRefType', () {
    final String src =
        _read('lib/presentation/child/pages/child_sunlight_history_page.dart');
    expect(src.contains('kFocusLevelUpRefType'), isTrue,
        reason: '漏配会让孩子端显示「其他」，阳光来源对不上账');
    expect(src.contains("kFocusLevelUpRefType: '专注升级'"), isTrue);
  });
}
