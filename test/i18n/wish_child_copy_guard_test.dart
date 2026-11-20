/// 许愿树孩子端文案纪律（v0.3.0 / R3-P0-06④、D2）+ 三态文案 ARB 齐备（R3-P0-06①）。
///
/// ## 守什么
///  ① **孩子端一律「小办法」**：许愿树相关、孩子可见的 ARB 键，值里**不得含
///     「任务」二字**；家长端键仍然叫「任务」（成人语境）。
///  ② **三态文案齐备**：`wishStateHangingHint` / `wishStateParentWorking` /
///     `wishWayTitle` / `wishGoGrowthHint` / `wishWayLabel` / `wishWayCountBadge`
///     在 zh + en 都存在且非空，且 **en 值零 CJK**（切英文不回落中文）。
///  ③ **改写对**：`wishTreeTaskBadge` / `wishProgressTaskCount` 已改成「小办法」措辞。
///
/// ⚠️ 口径说明（已报备）：`grep 任务` 全量清零**不可能** —— 既有成长任务体系
/// （`child_shell_task_title` / `ghelp_task_detail` 等 17 个键）本来就叫「任务」，
/// 那是另一条玩法的既定文案，不属于本批「愿望任务改名」的范围。故本守卫的
/// 强约束落在**许愿树相关键**上（下方清单），成长任务键不纳入。
library wish_child_copy_guard_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// 孩子端（许愿树）可见的 ARB 键 —— 这些键的值不许出现「任务」。
const List<String> _childWishKeys = <String>[
  'wishTreeTaskBadge',
  'wishProgressTaskCount',
  'wishWayLabel',
  'wishWayTitle',
  'wishGoGrowthHint',
  'wishWayCountBadge',
  'wishStateHangingHint',
  'wishStateParentWorking',
  'wishTreeWaitDays',
  'wishTreeStaleHint',
  'wishTreeReplyEmpty',
  'wishTreeTagRibbon',
  'wishCollectToBox',
  'wishRestoreFromBox',
  'wishSelfFulfill',
  'wishFruitGrowing',
  'wishFruitWaiting',
  'wishComposeTitle',
  'wishComposeHint',
];

final RegExp _cjk = RegExp(
  r'[\u3000-\u303F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]',
);

void main() {
  final Map<String, dynamic> zh = _arb('lib/l10n/app_zh.arb');
  final Map<String, dynamic> en = _arb('lib/l10n/app_en.arb');

  group('① 孩子端不含「任务」（D2）', () {
    test('许愿树孩子端键的值一律不含「任务」', () {
      for (final String key in _childWishKeys) {
        final String value = zh[key] as String;
        expect(value.contains('任务'), isFalse,
            reason: '孩子端键 $key="$value" 仍含「任务」，应改为「小办法」');
      }
    });

    test('英文侧同理：不含 "task" 字样（小写比较）', () {
      for (final String key in _childWishKeys) {
        final dynamic value = en[key];
        if (value == null) continue; // en 允许缺省（回落 zh 模板）
        expect((value as String).toLowerCase().contains('task'), isFalse,
            reason: '孩子端键 $key 的英文仍含 task');
      }
    });

    test('家长端保留「任务」措辞（不被误改）', () {
      expect(zh['wishTaskBadgeLabel'], '愿望任务');
      expect(zh['parent_wish_tab_tasks'], '任务');
      expect((zh['wishTaskBadgeOfWish'] as String).contains('愿望任务'), isTrue);
    });
  });

  group('② 三态文案齐备（zh + en 非空，en 零 CJK）', () {
    const List<String> stateKeys = <String>[
      'wishStateHangingHint',
      'wishStateParentWorking',
      'wishWayTitle',
      'wishGoGrowthHint',
      'wishWayLabel',
      'wishWayCountBadge',
    ];

    test('zh 存在且非空', () {
      for (final String key in stateKeys) {
        expect(zh.containsKey(key), isTrue, reason: 'zh 缺键 $key');
        expect((zh[key] as String).trim(), isNotEmpty, reason: 'zh 键 $key 为空');
      }
    });

    test('en 存在、非空、且零 CJK（切英文不回落中文）', () {
      for (final String key in stateKeys) {
        expect(en.containsKey(key), isTrue, reason: 'en 缺键 $key');
        final String value = en[key] as String;
        expect(value.trim(), isNotEmpty, reason: 'en 键 $key 为空');
        expect(_cjk.hasMatch(value), isFalse,
            reason: 'en 键 $key="$value" 含 CJK（英文模式会露中文）');
      }
    });

    test('S1 / S2 文案与 PRD D5 语义一致（关键词）', () {
      expect(zh['wishStateHangingHint'], contains('爸爸妈妈'));
      expect(zh['wishStateHangingHint'], contains('愿望'));
      expect(zh['wishStateParentWorking'], contains('想办法'));
      expect(zh['wishWayTitle'], contains('小办法'));
    });

    test('S3 单句成长引导文案固定（v0.4 两行合并口径）', () {
      expect(zh['wishGoGrowthHint'], '去成长里面实现你的愿望吧');
      expect(zh['wishGoGrowthHint'], isNot(contains('任务')));
      expect(en['wishGoGrowthHint'], isNot(contains('task')));
    });
  });

  group('④ 详情「实现了」专用文案（玄参 iPad13 拍板）', () {
    test('zh/en ARB 齐备且 getter 已生成（旧 key 不删）', () {
      expect(zh['wishDetailRealized'], '实现了');
      expect(en['wishDetailRealized'], 'Done it');
      expect(_cjk.hasMatch(en['wishDetailRealized'] as String), isFalse);
      expect(zh.containsKey('wishSelfFulfill'), isTrue);
      expect(en.containsKey('wishSelfFulfill'), isTrue);
      for (final String path in <String>[
        'lib/l10n/generated/app_localizations.dart',
        'lib/l10n/generated/app_localizations_zh.dart',
        'lib/l10n/generated/app_localizations_en.dart',
      ]) {
        expect(File(path).readAsStringSync(), contains('wishDetailRealized'),
            reason: '$path 缺 generated getter');
      }
    });
  });

  group('⑤ 达成确认单句文案（玄参 2026-11-20 iPad13 拍板）', () {
    test('zh/en ARB 值固定、英文零 CJK，三个 generated getter 存在且旧键不删', () {
      expect(zh['wishRealizedCongrats'], '恭喜，愿望实现啦！');
      expect(en['wishRealizedCongrats'], 'Congrats, your wish came true!');
      expect(_cjk.hasMatch(en['wishRealizedCongrats'] as String), isFalse);

      expect(zh.containsKey('wishTreeSelfFulfillConfirm'), isTrue);
      expect(zh.containsKey('wishSelfFulfillConfirm'), isTrue);
      expect(en.containsKey('wishTreeSelfFulfillConfirm'), isTrue);
      expect(en.containsKey('wishSelfFulfillConfirm'), isTrue);

      for (final String path in <String>[
        'lib/l10n/generated/app_localizations.dart',
        'lib/l10n/generated/app_localizations_zh.dart',
        'lib/l10n/generated/app_localizations_en.dart',
      ]) {
        expect(File(path).readAsStringSync(), contains('wishRealizedCongrats'),
            reason: '$path 缺 generated getter');
      }
    });
  });

  group('③ 改写对（旧「任务」措辞已下线）', () {
    test('wishTreeTaskBadge = 「小办法 {count} 个」', () {
      expect(zh['wishTreeTaskBadge'], contains('小办法'));
      expect(zh['wishTreeTaskBadge'], isNot(contains('任务')));
    });

    test('wishProgressTaskCount = 「已完成 … 个小办法 …」', () {
      expect(zh['wishProgressTaskCount'], contains('小办法'));
      expect(zh['wishProgressTaskCount'], isNot(contains('任务')));
    });
  });
}
