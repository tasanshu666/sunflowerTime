/// F128（玄参 2026-10-19）：截商店图时须能隐藏调试 UI。
///
/// 背景：调试入口本来由 `kDebugMode` 守卫，release 包天然不渲染；但**截图用的是
/// debug 包**，于是「我的」页的 `DEBUG 加1000阳光` 等按钮、家长端「今日」页的
/// `🧪 调试：跳过 30 分钟限时` 会入镜，等于把内部信息暴露在商店图里。
///
/// 修法：新增构建期开关 `HIDE_DEBUG_UI`（[kHideDebugUi]），三处显示条件统一走
/// [shouldShowDebugUi] 单点判据（我的页 / 家长今日页 / 家长设置页）；截图构建加
/// `--dart-define=HIDE_DEBUG_UI=true` 即可隐藏，默认构建不受影响。
///
/// 本测试两层：
///  1. **真值表**（行为层）：判据抽成纯函数后可直接验证 4 种组合，不依赖编译期常量；
///  2. **源码守卫**：防止后人把某页改回内联 `kDebugMode && !kHideDebugUi`，
///     漏掉单点（本项目的高复发模式：同一判断在两处各写一份，改一处漏一处）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';

void main() {
  group('调试 UI 显示判据 shouldShowDebugUi · 真值表', () {
    test('release（debugMode=false）：无论截图开关如何，一律不显示', () {
      expect(
        shouldShowDebugUi(debugMode: false, hideForScreenshots: false),
        isFalse,
        reason: 'release 包不得渲染调试区',
      );
      expect(
        shouldShowDebugUi(debugMode: false, hideForScreenshots: true),
        isFalse,
        reason: 'release 包不得渲染调试区（截图开关不能反过来打开它）',
      );
    });

    test('debug 默认（未加 define）：照常显示，不破坏现有调试能力', () {
      expect(
        shouldShowDebugUi(debugMode: true, hideForScreenshots: false),
        isTrue,
        reason: '日常 debug 构建必须保留调试入口',
      );
    });

    test('debug + 截图开关：隐藏', () {
      expect(
        shouldShowDebugUi(debugMode: true, hideForScreenshots: true),
        isFalse,
        reason: '--dart-define=HIDE_DEBUG_UI=true 时必须隐藏',
      );
    });

    test('默认构建不隐藏（kHideDebugUi 的 fromEnvironment 默认值为 false）', () {
      expect(kHideDebugUi, isFalse,
          reason: '未显式加 define 时不得隐藏调试入口');
    });
  });

  group('三处调试入口必须走统一判据（源码守卫）', () {
    test('我的页 + 家长端今日页 + 家长设置页 均调用 shouldShowDebugUi', () {
      const Map<String, String> files = <String, String>{
        '孩子端「我的」页': 'lib/presentation/child/pages/child_profile_page.dart',
        '家长端「今日」页': 'lib/presentation/parent/pages/parent_today_page.dart',
        '家长端「设置」页': 'lib/presentation/parent/pages/parent_settings_page.dart',
      };

      files.forEach((String label, String path) {
        final String src = File(path).readAsStringSync();
        expect(src.contains('shouldShowDebugUi('), isTrue,
            reason: '$label（$path）未走统一判据：截图时无法隐藏调试 UI');
        expect(src.contains('kDebugMode && !kHideDebugUi'), isFalse,
            reason: '$label（$path）仍存在内联判据，应改为 shouldShowDebugUi 单点');
      });
    });
  });
}
