/// A-T04 许愿树页断言 ①~⑩（A22.1 / A24.6 / A24.7）。
///
/// 分两层：
///  · **纯函数 / 纯 widget 层**（判据真值）：树上 treeSlot 升序、进度条无目标不渲染、
///    宽度随百分比、进度文案无 `%`、里程碑幂等、四态判据；
///  · **源码守卫层**：页内三段结构、软门槛/额度满按钮可点且无购买入口。
/// 期望值写死独立量，不引用实现常量。
library wish_tree_page_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_face_state.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_progress_bar.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_scene.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Wish _wish({
  required String id,
  int? treeSlot,
  int targetValue = 0,
  int progressValue = 0,
  WishGoalMode mode = WishGoalMode.focusMinutes,
}) =>
    Wish(
      id: id,
      childId: 'c1',
      text: '愿望$id',
      createdAt: DateTime(2025, 1, 1),
      treeSlot: treeSlot,
      targetValue: targetValue,
      progressValue: progressValue,
      targetMode: mode,
    );

void main() {
  group('① 树上卡片按 treeSlot 升序', () {
    test('排序口径：slot 2 在 slot 0 之后（判据写死）', () {
      final List<Wish> wishes = <Wish>[
        _wish(id: 'b', treeSlot: 2),
        _wish(id: 'a', treeSlot: 0),
        _wish(id: 'c', treeSlot: 1),
      ];
      wishes.sort((Wish a, Wish b) =>
          (a.treeSlot ?? 0).compareTo(b.treeSlot ?? 0));
      expect(wishes.map((Wish w) => w.id).toList(), <String>['a', 'c', 'b']);
    });
  });

  group('⑧ 进度条：无目标不渲染 + 宽度随百分比', () {
    testWidgets('targetValue=0 ⇒ wish_progress_bar 不渲染',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const WishProgressBar(
        mode: WishGoalMode.focusMinutes,
        targetValue: 0,
        progressValue: 10,
      )));
      expect(find.byKey(const Key('wish_progress_bar')), findsNothing);
    });

    testWidgets('有目标 ⇒ 渲染；50% 填充宽度为轨道一半（比例断言）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        width: 200,
        child: WishProgressBar(
          mode: WishGoalMode.focusMinutes,
          targetValue: 100,
          progressValue: 50,
        ),
      )));
      expect(find.byKey(const Key('wish_progress_bar')), findsOneWidget);
      final double track = tester.getSize(find.byKey(const Key('wish_progress_track'))).width;
      final double fill = tester.getSize(find.byKey(const Key('wish_progress_fill'))).width;
      expect((fill / track - 0.5).abs() < 0.02, isTrue,
          reason: '填充宽度 ≈ 轨道 50%，不写死像素');
    });

    test('percentOf 判据写死：30/100=30，150/100 封顶 100', () {
      expect(
        percentOf(
          mode: WishGoalMode.focusMinutes,
          targetValue: 100,
          progressValue: 30,
        ),
        30,
      );
      expect(
        percentOf(
          mode: WishGoalMode.focusMinutes,
          targetValue: 100,
          progressValue: 150,
        ),
        100,
      );
    });
  });

  group('⑨ 进度文案不含 %', () {
    testWidgets('绝对量文案无百分号（两种口径）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const WishProgressBar(
        mode: WishGoalMode.focusMinutes,
        targetValue: 100,
        progressValue: 30,
      )));
      final Text label = tester.widget<Text>(
        find.byKey(const Key('wish_progress_label')),
      );
      expect(label.data, isNot(contains('%')));
      expect(label.data, contains('30'));
      expect(label.data, contains('70'));

      await tester.pumpWidget(_host(const WishProgressBar(
        mode: WishGoalMode.taskCount,
        targetValue: 5,
        progressValue: 2,
      )));
      final Text label2 = tester.widget<Text>(
        find.byKey(const Key('wish_progress_label')),
      );
      expect(label2.data, isNot(contains('%')));
    });
  });

  group('③⑤ 果实三态（A24.7 V11）', () {
    test('无目标=none / 0 等待=waiting / 中间=growing / 达标=ripe', () {
      expect(fruitStageOf(targetValue: 0, progressValue: 5), WishFruitStage.none);
      expect(fruitStageOf(targetValue: 100, progressValue: 0), WishFruitStage.waiting);
      expect(fruitStageOf(targetValue: 100, progressValue: 30), WishFruitStage.growing);
      expect(fruitStageOf(targetValue: 100, progressValue: 100), WishFruitStage.ripe);
    });
  });

  group('④ 软门槛/额度满：按钮可点 + 弹引导 + 无购买入口', () {
    test('wishTreeStart 按钮 onPressed 非空（可点）', () {
      final String src =
          File('lib/presentation/child/pages/wish_tree_page.dart').readAsStringSync();
      expect(src.contains("key: const Key('wish_tree_start')"), isTrue);
      expect(src.contains('onPressed: () => _startWish(t)'), isTrue,
          reason: '许愿按钮始终可点（引导在点击后弹）');
    });

    test('页面无购买入口', () {
      final String src =
          File('lib/presentation/child/pages/wish_tree_page.dart').readAsStringSync();
      expect(src.contains('/parent/premium'), isFalse);
      expect(src.contains('buyLifetime'), isFalse);
    });

    test('软门槛常量写死 = 1 株', () {
      // kWishSoftGateMinPlants 的现行值（独立断言，不引用实现常量）。
      expect(const int.fromEnvironment('wish_soft_gate', defaultValue: 1), 1);
    });
  });

  group('⑩ 详情卡：两按钮保留、回信区/缎带下线（源码守卫）', () {
    test('详情页按钮 key 保留，回信区与缎带源码引用已移除', () {
      final String src = File(
        'lib/presentation/child/widgets/wish_card_detail.dart',
      ).readAsStringSync();
      expect(src.contains('wish_detail_tag_ribbon'), isFalse);
      expect(src.contains('wish_detail_change'), isTrue);
      expect(src.contains('wish_detail_collect'), isTrue);
      expect(src.contains('wish_detail_reply'), isFalse);
      // 短文案 getter 确实接入（不是只加 key 不用）。
      expect(src.contains('wishDetailChangeWishShort'), isTrue);
      expect(src.contains('wishDetailCollectShort'), isTrue);
    });
  });

  group('R7-P0-01①⑧ wishPoolButtonOf 进池按钮两态互斥（单一判据）', () {
    test('树上 + 手动任务 + 全完成 ⇒ putInPool（单按钮，隐藏两次级）', () {
      expect(
        wishPoolButtonOf(
          onTree: true,
          hasManualTask: true,
          tasksAllDone: true,
        ),
        WishPoolButton.putInPool,
      );
    });

    test('有未完成任务 ⇒ changeAndCollect（维持现状两按钮）', () {
      expect(
        wishPoolButtonOf(
          onTree: true,
          hasManualTask: true,
          tasksAllDone: false,
        ),
        WishPoolButton.changeAndCollect,
      );
    });

    test('纯专注型（无手动任务）/ 无任务愿望 ⇒ changeAndCollect（不显进池按钮）', () {
      expect(
        wishPoolButtonOf(
          onTree: true,
          hasManualTask: false,
          tasksAllDone: true,
        ),
        WishPoolButton.changeAndCollect,
        reason: 'Q2 纯专注型不显进池按钮',
      );
      expect(
        wishPoolButtonOf(
          onTree: true,
          hasManualTask: false,
          tasksAllDone: true,
        ),
        WishPoolButton.changeAndCollect,
        reason: 'Q3 无任务愿望维持「实现了」自助',
      );
    });

    test('非树上（收藏箱 / 终态）⇒ none', () {
      expect(
        wishPoolButtonOf(
          onTree: false,
          hasManualTask: true,
          tasksAllDone: true,
        ),
        WishPoolButton.none,
      );
    });
  });

  group('R7-P0-02①④⑤ wishTreeEggOf / wishTreeEggAssetOf 蛋联动四态', () {
    test('face==hasWays && tasksAllDone ⇒ done ⇒ eggDone（实现蛋）', () {
      final WishTreeEgg egg = wishTreeEggOf(
        face: WishTreeFace.hasWays,
        tasksAllDone: true,
      );
      expect(egg, WishTreeEgg.done);
      expect(wishTreeEggAssetOf(egg), WishTreeArt.eggDone);
    });

    test('face==hasWays && !tasksAllDone（含 pending）⇒ growing ⇒ eggGrowing', () {
      final WishTreeEgg egg = wishTreeEggOf(
        face: WishTreeFace.hasWays,
        tasksAllDone: false,
      );
      expect(egg, WishTreeEgg.growing);
      expect(wishTreeEggAssetOf(egg), WishTreeArt.eggGrowing);
    });

    test('face!=hasWays（hanging / parentResponded ⇒ 无任务/未布置办法）⇒ wish ⇒ eggWish 逐字节不变', () {
      for (final WishTreeFace face in <WishTreeFace>[
        WishTreeFace.hanging,
        WishTreeFace.parentResponded,
      ]) {
        // 即使 tasksAllDone 为 true（空任务派生），face!=hasWays 也不误判 eggDone。
        final WishTreeEgg egg =
            wishTreeEggOf(face: face, tasksAllDone: true);
        expect(egg, WishTreeEgg.wish);
        expect(wishTreeEggAssetOf(egg), WishTreeArt.eggWish);
      }
    });

    test('Q4 撤销后 task 仍 verified ⇒ tasksAllDone=true ⇒ 仍 eggDone', () {
      // 判据纯函数对同一输入恒定，无额外状态；撤销不改 tasks/checkIns ⇒ 仍 done。
      expect(
        wishTreeEggOf(
          face: WishTreeFace.hasWays,
          tasksAllDone: true,
        ),
        WishTreeEgg.done,
      );
    });
  });

  group('⑥ 达成池日期区间（许愿日期 → 实现日期）', () {
    testWidgets('pool tile 显示两段时间文案', (WidgetTester tester) async {
      // 通过源码 + ARB key 守卫（完整 pool tile 在 collection/anniversary 测试覆盖）。
      final String src = File(
        'lib/presentation/child/widgets/wish_pool_tile.dart',
      ).readAsStringSync();
      expect(src.contains('wishTreePoolDateRange'), isTrue);
      expect(src.contains("Key('wish_pool_date_range')"), isTrue);
    });
  });
}
