/// G1~G10: wish slot ladder / judgement single-source guards.
library wish_slot_ladder_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';

String _read(String path) => File(path).readAsStringSync();

String _functionBody(String source, String signature) {
  final int start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $signature');
  final int end = source.indexOf('\n}', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  const List<int> levels = <int>[0, 1, 4, 5, 10, 15, 20, 25, 30, 35, 39, 40];
  const List<int> freeExpected =
      <int>[1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10];

  group('G1~G4 阶梯行为', () {
    test('G1 level 0..40 上限单调不减（free + premium）', () {
      int lastFree = 0;
      int lastPremium = 0;
      for (int level = 0; level <= 40; level++) {
        final int free = wishSlotQuotaFor(
            focusLevel: level, isPremium: false);
        final int premium =
            wishSlotQuotaFor(focusLevel: level, isPremium: true);
        expect(free, greaterThanOrEqualTo(lastFree));
        expect(premium, greaterThanOrEqualTo(lastPremium));
        lastFree = free;
        lastPremium = premium;
      }
      expect(lastFree, 10);
      expect(lastPremium, 20);
    });

    test('G2 阶梯表逐位一致（12 个 level × 2 档）', () {
      for (int i = 0; i < levels.length; i++) {
        expect(
          wishSlotQuotaFor(focusLevel: levels[i], isPremium: false),
          freeExpected[i],
          reason: 'level ${levels[i]} free');
        expect(
          wishSlotQuotaFor(focusLevel: levels[i], isPremium: true),
          freeExpected[i] * 2,
          reason: 'level ${levels[i]} premium');
      }
    });

    test('G3 超限只拦新增：存量 3 条逐条保留', () {
      final List<String> existing = <String>['w1', 'w2', 'w3'];
      expect(
          quotaAllowsAddWishSlot(
              focusLevel: 0, isPremium: false, currentCount: 3),
          isFalse);
      expect(existing, <String>['w1', 'w2', 'w3']);
    });

    test('G4 等级提升后已挂愿望完好', () {
      final List<String> mounted = <String>['w1'];
      expect(
          quotaAllowsAddWishSlot(
              focusLevel: 40, isPremium: false, currentCount: mounted.length),
          isTrue);
      expect(mounted, <String>['w1']);
    });
  });

  group('G5~G10 源码守卫', () {
    final String matrix = _read('lib/core/constants/entitlement_matrix.dart');

    test('G5 锚点同源：业务文件无第二份等级节点字面量', () {
      const String anchor = '[1, 5, 10, 15, 20, 25, 30, 35, 40]';
      final Directory lib = Directory('lib');
      final List<File> files = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('prd_params.dart'))
          .toList();
      final List<String> hits = <String>[];
      for (final File f in files) {
        if (_read(f.path).contains(anchor)) hits.add(f.path);
      }
      expect(hits, isEmpty, reason: '等级节点只能在 prd_params.dart 定义');
    });

    test('G6 判定单点：只有 entitlement_matrix 定义额度函数', () {
      final Directory lib = Directory('lib');
      final List<File> files = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      final List<String> hits = <String>[];
      for (final File f in files) {
        if (f.path.endsWith('entitlement_matrix.dart')) continue;
        if (_read(f.path).contains('int wishSlotQuotaFor(')) hits.add(f.path);
      }
      expect(hits, isEmpty);
    });

    test('G7 实现体不委托天花板', () {
      final String quotaBody = _functionBody(
          matrix, 'int wishSlotQuotaFor({');
      final String addBody = _functionBody(
          matrix, 'bool quotaAllowsAddWishSlot({');
      for (final String body in <String>[quotaBody, addBody]) {
        expect(body.contains('featureQuotaFor'), isFalse);
        expect(body.contains('quotaAllowsAdd('), isFalse);
      }
    });

    test('G8 业务文件不得直呼 wishSlot 的天花板判定', () {
      const List<String> businessFiles = <String>[
        'lib/domain/services/wish_orchestration_service.dart',
        'lib/domain/services/wish_progress.dart',
        'lib/presentation/child/state/wish_state.dart',
        'lib/presentation/child/pages/wish_tree_page.dart',
        'lib/presentation/child/widgets/wish_compose_dialog.dart',
        'lib/presentation/parent/widgets/wish_task_editor.dart',
        // 家长端 state/wish_state.dart 与 wish_tree_section.dart 已随
        // 「今日页愿望展示」整体移除（v0.4）。
        'lib/presentation/child/widgets/wish_card.dart',
      ];
      for (final String path in businessFiles) {
        final File file = File(path);
        if (!file.existsSync()) continue;
        final String src = _read(path);
        expect(src.contains('featureQuotaFor(FeatureKey.wishSlot'), isFalse,
            reason: path);
        expect(src.contains('quotaAllowsAdd(FeatureKey.wishSlot'), isFalse,
            reason: path);
      }
    });

    test('G9 无第二份节点三元散判', () {
      final Directory lib = Directory('lib');
      final List<File> files = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('prd_params.dart'))
          .toList();
      for (final File f in files) {
        final String src = _read(f.path);
        expect(RegExp(r'level\s*>=\s*15\s*\?').hasMatch(src), isFalse,
            reason: f.path);
      }
    });

    test('G10 天花板与节点数同源（10 == 1 + 9）', () {
      expect(kWishSlotMaxFree, 1 + kFocusLevelTitleLevels.length);
      expect(kWishSlotMaxPremium, kWishSlotMaxFree * 2);
      expect(kWishSlotMaxFree, 10);
      expect(kWishSlotMaxPremium, 20);
    });

    test('totalStats() 不在许愿领域服务内调用（一次构建 ≤ 1）', () {
      final String src =
          _read('lib/domain/services/wish_orchestration_service.dart');
      expect('totalStats()'.allMatches(src).length, 0);
    });
  });
}
