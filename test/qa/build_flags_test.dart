/// 编译期构建开关守卫（C88）。
///
/// 背景：为自家平板出「装上即永久会员」的验收包，新增了
/// `--dart-define=FORCE_UNLOCK_ALL=true` 这一编译期开关。
///
/// 🔴 本文件守的是**正式包的安全底线**：默认值必须为 `false`。
/// 一旦有人手滑把 `defaultValue` 改成 `true`，所有上架包会变成全解锁 ——
/// 这是比任何 UI bug 都严重的资损 / 审核风险，所以用测试钉住。
///
/// ⚠️ 如果你正带着 `FORCE_UNLOCK_ALL=true` 跑全量测试，本文件第一条会红 ——
/// 这是**预期行为**（那一轮的产物是内部验收包，本就不该被当成正式包验收）。
library build_flags_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/build_flags.dart';

String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/qa') || cwd.endsWith('\\test\\qa')
      ? Directory.current.parent.parent.path
      : cwd;
}

void main() {
  group('构建开关：强制解锁', () {
    test('默认构建必须为 false（正式包不得全解锁）', () {
      expect(
        kForceUnlockAll,
        isFalse,
        reason: '正式包安全底线：不传 --dart-define=FORCE_UNLOCK_ALL=true 时必须关闭。'
            '若此条变红，先检查 build_flags.dart 的 defaultValue 是否被改成了 true。',
      );
    });

    test('开关声明必须是 const + bool.fromEnvironment（可被 release 常量折叠）', () {
      // 非 const 的 fromEnvironment 在 AOT 下无法被 tree-shake / 常量折叠，
      // 且容易被误改成读运行时配置 —— 那样「默认关闭」的保证就没了。
      final String src = File(
        '${_projectRoot()}/lib/core/constants/build_flags.dart',
      ).readAsStringSync();
      expect(
        src.contains("const bool kForceUnlockAll = bool.fromEnvironment("),
        isTrue,
        reason: '必须写成 const bool = bool.fromEnvironment(...)，否则默认关闭无法保证',
      );
      expect(src.contains("'FORCE_UNLOCK_ALL'"), isTrue,
          reason: 'define 键名固定为 FORCE_UNLOCK_ALL（构建脚本与文档均引用此名）');
    });

    test('冷启动回填：强制分支必须在读票据之前（否则会被真实票据覆盖）', () {
      final String src =
          File('${_projectRoot()}/lib/main.dart').readAsStringSync();

      final int forceAt = src.indexOf('kForceUnlockAll');
      final int loadAt = src.indexOf('entitlementServiceProvider).load()');
      expect(forceAt, greaterThan(0), reason: 'main.dart 必须引用该开关');
      expect(loadAt, greaterThan(0), reason: 'main.dart 必须仍有读票据的正常路径');
      expect(
        forceAt,
        lessThan(loadAt),
        reason: '🔴 强制解锁分支必须写在读票据之前：写在后面会被真实票据（free）覆盖，'
            '表现为「装了会员包却仍是免费档」',
      );
    });
  });
}
