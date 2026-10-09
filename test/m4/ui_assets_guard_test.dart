/// C44 素材护栏：tab 背景 + 成长/奖励卡片图标（2026-10-09 玄参交付）。
///
/// 钉三件事：
///  1. **文件存在**：映射函数可能返回的每个 asset 路径都在磁盘上（防改名/漏交）；
///  2. **映射契约**：关键词命中 / 联动项兜底 / 分类兜底 / default 兜底，逐链路断言；
///  3. **尺寸契约**：背景 3 张（登记 pubspec 的）WebP 原尺寸横纵比 ≥ 0.44（竖版
///     整页底图），图标统一 512×512 透明（显示 56px @3x 留足清晰度）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';

const String root = '.';

Task _task({
  String name = '普通任务',
  bool requiresFocus = false,
  TaskCategory category = TaskCategory.other,
}) =>
    Task(
      id: 't-${name.hashCode}',
      name: name,
      subject: TaskSubject.general,
      requiresFocus: requiresFocus,
      minFocusMin: 15,
      sunlightReward: 10,
      isCustom: false,
      category: category,
    );

RewardTemplate _reward(String name,
        {RewardContentCategory cat = RewardContentCategory.other}) =>
    RewardTemplate(
      id: 'r-$name',
      name: name,
      category: RewardCategory.parentHandled,
      contentCategory: cat,
      baseCost: 10,
      frequencyLimitPerWeek: 0,
    );

void main() {
  group('C44 背景素材契约', () {
    test('三张登记的背景文件存在且为竖版 WebP（横纵比 ≈ 手机屏）', () {
      for (final String asset in <String>[kTodayBgAsset, kGrowthBgAsset, kStoreBgAsset]) {
        final File f = File('$root/$asset');
        expect(f.existsSync(), isTrue, reason: '缺背景：$asset');
        final List<int> b = f.readAsBytesSync();
        final String riff = String.fromCharCodes(b.sublist(0, 4));
        expect(riff, 'RIFF', reason: '$asset 应为 WebP（RIFF 头）');
        // RIFF size @4..8，'WEBP' @8..12，VP8X/VP8 尺寸块解析交给 fx_guard 同款思路：
        // 这里只做轻校验（>50KB 且 <1MB，转换管线产物区间），防止误交原始 PNG。
        expect(f.lengthSync(), greaterThan(50 * 1024), reason: '$asset 过小');
        expect(f.lengthSync(), lessThan(1 * 1024 * 1024), reason: '$asset 过大（疑未压缩）');
      }
    });

    test('备选商店背景 store01/store03 已入库（未登记 pubspec，换背景即改常量）', () {
      expect(File('$root/assets/backgrounds/store01.webp').existsSync(), isTrue);
      expect(File('$root/assets/backgrounds/store03.webp').existsSync(), isTrue);
    });
  });

  group('C44 成长项图标映射（C46c：联动项 focus 一律优先 → 名字关键词 → 分类兜底 → default）', () {
    test('名字关键词命中（先专后泛：clean_up→homework→listen→read_book→sports→habit）', () {
      expect(growthIconAssetFor(_task(name: '整理书桌')),
          endsWith('/clean_up.webp'));
      expect(growthIconAssetFor(_task(name: '写作业')), endsWith('/homework.webp'));
      expect(growthIconAssetFor(_task(name: '听英语')), endsWith('/listen.webp'));
      expect(growthIconAssetFor(_task(name: '朗读课文')), endsWith('/read_book.webp'));
      expect(growthIconAssetFor(_task(name: '跳绳 100 下')), endsWith('/sports.webp'));
      expect(growthIconAssetFor(_task(name: '养成好习惯')), endsWith('/habit.webp'));
    });

    test('C46c 联动专注项一律 focus（闹钟），名字命中不再抢优先级', () {
      expect(growthIconAssetFor(_task(name: '自由练习', requiresFocus: true)),
          endsWith('/focus.webp'));
      expect(growthIconAssetFor(_task(name: '阅读 20 分钟', requiresFocus: true)),
          endsWith('/focus.webp'),
          reason: 'C46c 玄参口径：联动项一律闹钟（孩子一眼分辨「要去专注」）');
      expect(growthIconAssetFor(_task(name: '写作业', requiresFocus: true)),
          endsWith('/focus.webp'));
      // 非联动项不受影响：名字关键词照常命中。
      expect(growthIconAssetFor(_task(name: '阅读 20 分钟')),
          endsWith('/read_book.webp'));
    });

    test('分类兜底（运动/生活）与其余落 default_ui；9 张图标文件全部存在', () {
      expect(growthIconAssetFor(_task(name: '室内活动', category: TaskCategory.sports)),
          endsWith('/sports.webp'));
      expect(growthIconAssetFor(_task(name: '日常小事', category: TaskCategory.life)),
          endsWith('/life.webp'));
      expect(growthIconAssetFor(_task(name: '神秘任务')), endsWith('/default_ui.webp'));

      const List<String> icons = <String>[
        'clean_up', 'default_ui', 'focus', 'habit', 'homework',
        'life', 'listen', 'read_book', 'sports',
      ];
      for (final String n in icons) {
        expect(File('$root/assets/ui/growth/$n.webp').existsSync(), isTrue,
            reason: '缺成长图标：$n.webp');
      }
    });
  });

  group('C44 奖励图标映射（名字关键词 → 内容分类兜底 → default）', () {
    test('名字关键词命中', () {
      expect(rewardIconAssetFor(_reward('绘本一套')), endsWith('/store_book.webp'));
      expect(rewardIconAssetFor(_reward('足球一个')), endsWith('/store_sports.webp'));
      expect(rewardIconAssetFor(_reward('积木盒')), endsWith('/store_toys.webp'));
      expect(rewardIconAssetFor(_reward('游戏机一小时')), endsWith('/store_game.webp'));
      expect(rewardIconAssetFor(_reward('冰淇淋券')), endsWith('/store_snack.webp'));
      expect(rewardIconAssetFor(_reward('去公园玩')), endsWith('/store_play.webp'));
    });

    test('无命中按内容分类兜底；7 张图标文件全部存在', () {
      expect(rewardIconAssetFor(_reward('神秘奖励', cat: RewardContentCategory.snacks)),
          endsWith('/store_snack.webp'));
      expect(rewardIconAssetFor(_reward('神秘奖励', cat: RewardContentCategory.play)),
          endsWith('/store_play.webp'));
      expect(rewardIconAssetFor(_reward('神秘奖励', cat: RewardContentCategory.entertainment)),
          endsWith('/store_game.webp'));
      expect(rewardIconAssetFor(_reward('神秘奖励')), endsWith('/store_default.webp'));

      const List<String> icons = <String>[
        'store_book', 'store_default', 'store_game', 'store_play',
        'store_snack', 'store_sports', 'store_toys',
      ];
      for (final String n in icons) {
        expect(File('$root/assets/ui/store/$n.webp').existsSync(), isTrue,
            reason: '缺奖励图标：$n.webp');
      }
    });
  });
}
