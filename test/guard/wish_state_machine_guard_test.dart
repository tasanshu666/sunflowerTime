/// State-machine guard: transitions are centralized in the orchestration service.
library wish_state_machine_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  final String service =
      _read('lib/domain/services/wish_orchestration_service.dart');

  test('6 态 index 冻结', () {
    expect(WishStatus.pending.index, 0);
    expect(WishStatus.tagged.index, 1);
    expect(WishStatus.committed.index, 2);
    expect(WishStatus.fulfilled.index, 3);
    expect(WishStatus.replaced.index, 4);
    expect(WishStatus.abandoned.index, 5);
    expect(WishStatus.values.length, 6);
  });

  test('assertTransition 6 条合法边', () {
    const List<List<WishStatus>> legal = <List<WishStatus>>[
      <WishStatus>[WishStatus.pending, WishStatus.tagged],
      <WishStatus>[WishStatus.tagged, WishStatus.pending],
      <WishStatus>[WishStatus.pending, WishStatus.fulfilled],
      <WishStatus>[WishStatus.tagged, WishStatus.fulfilled],
      <WishStatus>[WishStatus.tagged, WishStatus.abandoned],
      <WishStatus>[WishStatus.fulfilled, WishStatus.pending],
    ];
    for (final List<WishStatus> edge in legal) {
      expect(
        () => WishOrchestrationService.assertTransition(
          edge[0],
          edge[1],
          parentUndo: edge[0] == WishStatus.fulfilled,
        ),
        returnsNormally,
        reason: '${edge[0]} -> ${edge[1]}',
      );
    }
  });

  test('反向边只在 parentUndo 开关下合法', () {
    expect(
        () => WishOrchestrationService.assertTransition(
            WishStatus.fulfilled, WishStatus.pending),
        throwsA(isA<StateError>()));
  });

  test('异常消息 ASCII（无中文上屏）', () {
    try {
      WishOrchestrationService.assertTransition(
          WishStatus.abandoned, WishStatus.pending);
      fail('expected StateError');
    } on StateError catch (e) {
      expect(e.message.codeUnits.every((int c) => c < 128), isTrue);
    }
  });

  test('UI / 数据层不得直接写 status（wish 文件源码扫描）', () {
    final Directory lib = Directory('lib');
    final List<File> files = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) =>
            f.path.endsWith('.dart') &&
            f.path.contains('wish') &&
            !f.path.contains('wish_orchestration_service.dart') &&
            !f.path.endsWith('wish_local_repository.dart'))
        .toList();
    final List<String> hits = <String>[];
    for (final File f in files) {
      final String src = _read(f.path);
      if (f.path.endsWith('wish_local_repository.dart')) continue;
      if (RegExp(r'copyWith\(\s*status\s*:').hasMatch(src)) hits.add(f.path);
    }
    expect(hits, isEmpty, reason: 'status writes must go through the service');
  });

  test('状态写入集中在编排服务', () {
    expect('status: WishStatus.'.allMatches(service).length,
        greaterThanOrEqualTo(5));
  });
}
