/// F147：**物种图鉴文案 ARB 化**（英文物种卡背面仍显示中文）守卫。
///
/// ## 背景
/// 迁移前 6 个物种的**简短介绍 + 小故事**（C29 选种卡「翻面」背面文案）硬编码
/// 中文在 `core/constants/species_lore.dart`，唯一消费点
/// `garden_page.dart::_backFace`。英文模式下选种卡翻面后标题已英文
/// （`speciesNameOr`），介绍和故事**仍是中文** —— i18n 残留。
///
/// 修法与 `core/i18n/title_l10n.dart` 同构：文案整体迁 ARB
/// （`species_lore_{id}_intro/_story` + `species_lore_fallback_intro/_story`，
/// 共 14 条），`core/constants/species_lore.dart` 整体删除（防双真源），
/// UI 经 `core/i18n/species_lore_l10n.dart::speciesLoreL10n` 取用。
///
/// ## 本文件锁四条
///  ① **zh 逐字节不变**：8 物种 × 2（intro/story）+ 2 条兜底 = 18 条 ARB zh 值
///     与迁移前 `kSpeciesLore` / `kFallbackSpeciesLore` 宪法原文完全一致（F151
///     增葡萄、F153 增玫瑰时按当时 ARB 原文追加锚点）；
///  ② **en 无 CJK**：14 条英文全部非空且不含任何汉字（英文模式不再显中文）；
///  ③ **未知 id 回退**：已删物种（star_flower / rainbow_fern）与自造 id →
///     fallback 文案，不抛异常；
///  ④ **源码守卫**：`garden_page.dart` 不得再 import `species_lore.dart` /
///     调 `speciesLoreOf`（防止有人把删掉的中文常量加回来形成双真源）。
library species_lore_l10n_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/species_lore_l10n.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// 迁移前 `kSpeciesLore` / `kFallbackSpeciesLore` 的**宪法原文**（zh，逐字节）。
const Map<String, List<String>> _constitutionZh = <String, List<String>>{
  'species_sunflower': <String>[
    '跟着太阳转头的金脸盘',
    '小向日葵每天仰着头看太阳，太阳去哪儿它就看哪儿，慢慢就长出了金灿灿的圆脸盘，成了花园里最亮的小太阳。',
  ],
  'species_tomato': <String>[
    '一串串红红的小灯笼',
    '番茄小时候是绿色的，晒着晒着就害羞起来，脸越来越红，熟透了就像小灯笼一样挂在枝头。',
  ],
  'species_strawberry': <String>[
    '带芝麻点的心形果子',
    '草莓身上布满了小芝麻——其实每粒「芝麻」都是一颗真正的小种子，一颗草莓能藏两百粒种子呢！',
  ],
  'species_moon_orchid': <String>[
    '月光下才肯开放',
    '月光兰白天呼呼大睡，月亮升起才轻轻张开花瓣，把月光酿成淡淡的香气，陪小朋友甜甜入睡。',
  ],
  'species_coral_orchid': <String>[
    '像海底珊瑚一样粉',
    '传说它是海里的珊瑚上岸做的梦，梦里开出了粉色的花，从此叶子间总藏着小海螺的悄悄话。',
  ],
  'species_jade_hydrangea': <String>[
    '许多小花抱成一个大球',
    '翡翠绣球由几十朵小花手拉手抱成一团，风再大也吹不散，因为它相信：团结的花最漂亮。',
  ],
  'species_grape': <String>[
    '一串串紫珍珠',
    '葡萄是爬藤小能手，天生带着「小卷须」当抓手，一格一格往上爬。它结果不像别的花先开花后长果——葡萄的小花还没张开，果子就悄悄冒出来啦。',
  ],
  'species_rose': <String>[
    '带刺的小卫士',
    '玫瑰身上的小刺是它的「铠甲」，专门保护软软的花瓣不被小动物一口吃掉。我们闻到的玫瑰香，是花瓣里藏着的小油滴在悄悄散发——要好多好多花瓣，才能收满一小瓶玫瑰香水呢。',
  ],
  '__fallback__': <String>[
    '花园里的小植物',
    '每种植物都有自己的小故事，等着你去发现哦。',
  ],
};

/// 汉字（CJK 统一表意文字）。
final RegExp _han = RegExp(r'[\u4e00-\u9fff]');

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  group('① zh 逐字节不变（零回归）', () {
    test('8 物种 × 2 + 兜底 2 = 18 条 zh 值与宪法原文逐字节一致', () {
      for (final MapEntry<String, List<String>> entry
          in _constitutionZh.entries) {
        final SpeciesLore lore = entry.key == '__fallback__'
            ? speciesLoreL10n('no_such_species', zh)
            : speciesLoreL10n(entry.key, zh);
        expect(lore.intro, entry.value[0],
            reason: '${entry.key} 的 zh intro 必须与迁移前 species_lore.dart 逐字节一致');
        expect(lore.story, entry.value[1],
            reason: '${entry.key} 的 zh story 必须与迁移前 species_lore.dart 逐字节一致');
      }
    });
  });

  group('② en 译文：非空 + 无 CJK', () {
    test('18 条 en 全部不含汉字且非空（英文模式不再显中文）', () {
      for (final String id in _constitutionZh.keys) {
        final SpeciesLore lore = speciesLoreL10n(
            id == '__fallback__' ? 'no_such_species' : id, en);
        expect(lore.intro, isNotEmpty, reason: '$id 的 en intro 不得为空');
        expect(lore.story, isNotEmpty, reason: '$id 的 en story 不得为空');
        expect(_han.hasMatch(lore.intro), isFalse,
            reason: '$id 的 en intro 含汉字：「${lore.intro}」');
        expect(_han.hasMatch(lore.story), isFalse,
            reason: '$id 的 en story 含汉字：「${lore.story}」');
      }
    });

    test('8 条 en intro 简短（≤ 8 词，儿童友好口径）', () {
      const List<String> ids = <String>[
        'species_sunflower',
        'species_tomato',
        'species_strawberry',
        'species_moon_orchid',
        'species_coral_orchid',
        'species_jade_hydrangea',
        'species_grape',
        'species_rose',
      ];
      for (final String id in ids) {
        final String intro = speciesLoreL10n(id, en).intro;
        expect(intro.trim().split(RegExp(r'\s+')).length, lessThanOrEqualTo(8),
            reason: '$id 的 en intro「$intro」超过 8 词，选种卡背面一行放不下');
      }
    });

    test('en story ≤ 3 句（儿童友好口径）', () {
      for (final String id in _constitutionZh.keys) {
        final String story =
            speciesLoreL10n(id == '__fallback__' ? 'no_such_species' : id, en)
                .story;
        final int sentences =
            RegExp(r'[.!?](\s|$)').allMatches(story).length;
        expect(sentences, lessThanOrEqualTo(3),
            reason: '$id 的 en story 超过 3 句：「$story」');
      }
    });
  });

  group('③ 未知 id 回退 fallback', () {
    test('已删物种（star_flower / rainbow_fern）与自造 id → fallback 文案', () {
      final SpeciesLore fallback = speciesLoreL10n('no_such_species', zh);
      for (final String unknownId in <String>[
        'species_star_flower', // 2026-10-08 玄参删除。
        'species_rainbow_fern', // 2026-10-08 玄参删除。
        'species_old_custom',
        '',
      ]) {
        final SpeciesLore lore = speciesLoreL10n(unknownId, zh);
        expect(lore.intro, fallback.intro,
            reason: '未知 id「$unknownId」必须回退兜底 intro');
        expect(lore.story, fallback.story,
            reason: '未知 id「$unknownId」必须回退兜底 story');
      }
    });
  });

  group('④ 源码守卫：garden_page 只走 ARB 出口', () {
    final String src = File('lib/presentation/child/pages/garden_page.dart')
        .readAsStringSync();

    test('garden_page 不得 import species_lore.dart / 调 speciesLoreOf', () {
      expect(src.contains("core/constants/species_lore.dart"), isFalse,
          reason: 'garden_page 不得再 import 已删除的中文硬编码常量文件（双真源防线）');
      expect(src.contains('speciesLoreOf'), isFalse,
          reason: '旧入口 speciesLoreOf 必须整体消失，一律走 speciesLoreL10n');
    });

    test('garden_page 背面文案调 speciesLoreL10n 且传 AppLocalizations', () {
      expect(src.contains('speciesLoreL10n(species.id, l10n)'), isTrue,
          reason: '背面文案必须经 speciesLoreL10n(id, t) 取 ARB 文案');
    });

    test('species_lore.dart 常量文件已整体删除（单点真源）', () {
      expect(
        File('lib/core/constants/species_lore.dart').existsSync(),
        isFalse,
        reason: '中文硬编码真源必须删除，防止「迁了 ARB 但常量还在」的假迁移',
      );
      expect(File('lib/core/i18n/species_lore_l10n.dart').existsSync(), isTrue,
          reason: 'ARB 出口文件必须存在');
    });
  });
}
