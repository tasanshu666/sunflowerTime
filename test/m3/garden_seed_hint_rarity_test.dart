/// F144 · B 项：**种子掉落 / 分解提示只讲档位（普通 / 精英）** 守卫。
///
/// ## 背景（bug）
/// `garden_page.dart::_outcomeParts` 原先把**物种名**拼进提示：
/// 「掉落「草莓」种子」/「重复的「草莓」种子已分解为 2 植物碎片」。
///  · 英文模式下会串出中文物种名（i18n 回归）；
///  · 与选种弹窗 / 左上角种子计数 chip 的「普通种子 / 精英种子」口径不一致。
///
/// ## 修法
/// 新增 `_rarityLabelOf(speciesId)`：按 `PlantSpecies.isPremium` 判档 →
/// `garden_rarity_common`（普通）/ `garden_rarity_premium`（精英）；
/// 找不到物种（历史已删物种 `species_star_flower` / `species_rainbow_fern`）→
/// **回落普通档**（普通是默认档，比裸「种子」信息更完整）。
/// 提示模板改名为 `{rarity}` 占位符（原 `{name}`）。
///
/// ⚠️ 发放事实**不动**：`BloomRewardOutcome.seedSpeciesId` 与
/// `unlockSpecies(speciesId)` 仍按物种 id 记账（动了破库存）。
///
/// ## 本文件锁三条
///  ① **文案形态**：zh「掉落普通种子」/「重复的普通种子已分解为 N 植物碎片」，
///     en 同义；两条模板在 zh / en 下都**不含任何物种名**；
///  ② **6 个物种全覆盖**：逐个物种 id 走一遍档位映射 → 输出只可能是
///     「普通」或「精英」，且不含 6 个物种的中英文名；
///  ③ **源码守卫**：`_outcomeParts` 必须调 `_rarityLabelOf`、不得再调
///     `_speciesNameById`（该私有方法已删 → 也必须搜不到）。
library garden_seed_hint_rarity_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// 6 个物种的中英文名 —— 提示文案里**一个都不许出现**。
const List<String> _speciesNames = <String>[
  '向日葵', '月光兰', '番茄', '草莓', '珊瑚岭兰', '翡翠绣球', '葡萄', //
  'Sunflower', 'Moon Orchid', 'Tomato', 'Strawberry',
  'Coral Ridge Orchid', 'Jade Hydrangea', 'Grape',
];

/// 覆盖**全部 7 个物种 id**（F151 起）+ 2 个历史已删物种 id（验证「找不到 → 普通档」）。
const List<String> _allSpeciesIds = <String>[
  'species_sunflower',
  'species_moon_orchid',
  'species_tomato',
  'species_strawberry',
  'species_coral_orchid',
  'species_jade_hydrangea',
  'species_grape',
  // 2026-10-08 玄参删除的两种（老库里仍可能有残留券/种子）。
  'species_star_flower',
  'species_rainbow_fern',
];

/// **与生产同源**的档位映射（`garden_page.dart::_rarityLabelOf` 的等价纯函数）。
///
/// 之所以在测试里重写一遍而不是反射私有方法：私有方法不可直接调用，
/// 但判据只有一条 `PlantSpecies.isPremium` + 「找不到 → 普通档」兜底，
/// 复制成本极低；真正的防漂移由第 ③ 组源码守卫承担。
String _rarityLabelFor(String speciesId, AppLocalizations t) {
  for (final PlantSpecies sp in kSeedPlantSpecies) {
    if (sp.id == speciesId) {
      return sp.isPremium ? t.garden_rarity_premium : t.garden_rarity_common;
    }
  }
  return t.garden_rarity_common;
}

void _expectNoSpeciesName(String text) {
  for (final String name in _speciesNames) {
    expect(text.contains(name), isFalse,
        reason: '提示文案不得点物种名「$name」（当前：「$text」）');
  }
}

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  group('① 文案形态（占位符已改名 rarity，zh 逐字节目标）', () {
    test('zh：掉落 / 分解两条模板逐字节', () {
      expect(zh.garden_seed_dropped(zh.garden_rarity_common), '掉落普通种子');
      expect(zh.garden_seed_dropped(zh.garden_rarity_premium), '掉落精英种子');
      expect(zh.garden_seed_decomposed(2, zh.garden_rarity_common),
          '重复的普通种子已分解为 2 植物碎片');
      expect(zh.garden_seed_decomposed(3, zh.garden_rarity_premium),
          '重复的精英种子已分解为 3 植物碎片');
      // 旧口径的「」书名号必须消失。
      expect(zh.garden_seed_dropped(zh.garden_rarity_common).contains('「'),
          isFalse);
    });

    test('en：同义且不含任何物种名 / 不含书名号', () {
      final String dropEn = en.garden_seed_dropped(en.garden_rarity_common);
      final String decompEn = en.garden_seed_decomposed(2, en.garden_rarity_premium);
      expect(dropEn, 'Dropped a Common seed');
      expect(decompEn, 'Duplicate Premium seed turned into 2 fragments');
      _expectNoSpeciesName(dropEn);
      _expectNoSpeciesName(decompEn);
    });

    test('稀有度两条既有 key 值未被改动（普通 / 精英 · Common / Premium）', () {
      expect(zh.garden_rarity_common, '普通');
      expect(zh.garden_rarity_premium, '精英');
      expect(en.garden_rarity_common, 'Common');
      expect(en.garden_rarity_premium, 'Premium');
    });
  });

  group('② 7 个物种全覆盖：输出只有档位、不含物种名', () {
    test('每个物种 id 的档位标签 ∈ {普通, 精英}（历史已删物种 → 普通）', () {
      for (final String id in _allSpeciesIds) {
        final String label = _rarityLabelFor(id, zh);
        expect(label == zh.garden_rarity_common ||
            label == zh.garden_rarity_premium, isTrue,
            reason: '$id 的档位标签必须是「普通」或「精英」，实际「$label」');
      }
      // 已删物种显式回落普通档（不是空串、不是 id）。
      expect(_rarityLabelFor('species_star_flower', zh), zh.garden_rarity_common);
      expect(_rarityLabelFor('species_rainbow_fern', zh), zh.garden_rarity_common);
    });

    test('每个物种生成的掉落 / 分解提示都不含 7 个物种名（zh + en）', () {
      for (final String id in _allSpeciesIds) {
        final String dropZh = zh.garden_seed_dropped(_rarityLabelFor(id, zh));
        final String decompZh =
            zh.garden_seed_decomposed(2, _rarityLabelFor(id, zh));
        final String dropEn = en.garden_seed_dropped(_rarityLabelFor(id, en));
        final String decompEn =
            en.garden_seed_decomposed(2, _rarityLabelFor(id, en));
        for (final String text in <String>[dropZh, decompZh, dropEn, decompEn]) {
          _expectNoSpeciesName(text);
        }
      }
    });

    test('档位映射与 isPremium 严格同源（普通 3 种 / 精英 4 种，F151 起为 7 种）', () {
      int common = 0;
      int premium = 0;
      for (final PlantSpecies sp in kSeedPlantSpecies) {
        expect(_rarityLabelFor(sp.id, zh),
            sp.isPremium ? zh.garden_rarity_premium : zh.garden_rarity_common,
            reason: '${sp.id} 档位必须由 isPremium 单点派生');
        if (sp.isPremium) {
          premium++;
        } else {
          common++;
        }
      }
      expect(common, 3);
      expect(premium, 4, reason: 'F151：葡萄入精英档（月光兰/珊瑚岭兰/翡翠绣球/葡萄）');
      // 兜底常量仍在（kStarterSpeciesId = 免费向日葵，不进本提示）。
      expect(kStarterSpeciesId, 'species_sunflower');
    });
  });

  group('③ 源码守卫：garden_page 只讲档位', () {
    final String src = File('lib/presentation/child/pages/garden_page.dart')
        .readAsStringSync();

    test('_outcomeParts 调 _rarityLabelOf，且不再出现 _speciesNameById', () {
      expect(src.contains('_rarityLabelOf'), isTrue,
          reason: '提示串必须经档位映射取文案');
      expect(src.contains('_speciesNameById'), isFalse,
          reason: '按物种名拼提示的旧私有方法必须整体删除（零消费点）');
      // 两条模板的调用点都必须传档位。
      expect(src.contains('_t.garden_seed_dropped(_rarityLabelOf('), isTrue,
          reason: '掉落提示必须传档位标签');
      expect(src.contains('_rarityLabelOf(o.decomposedSeedSpeciesId!)'), isTrue,
          reason: '分解提示必须传档位标签');
    });

    test('_rarityLabelOf 判据 = isPremium + 两档 ARB + 兜底普通', () {
      final int start = src.indexOf('String _rarityLabelOf(');
      expect(start, greaterThan(0), reason: 'garden_page 必须有 _rarityLabelOf');
      final String body = src.substring(start, start + 900);
      expect(body.contains('isPremium'), isTrue,
          reason: '档位判据必须单点取 PlantSpecies.isPremium');
      expect(body.contains('garden_rarity_premium'), isTrue);
      expect(body.contains('garden_rarity_common'), isTrue,
          reason: '找不到物种时兜底普通档也要用 garden_rarity_common');
    });

    test('不动发放事实：BloomRewardOutcome.seedSpeciesId / unlockSpecies 未被改签名', () {
      const String outcomePath =
          'lib/domain/entities/bloom_reward_outcome.dart';
      expect(File(outcomePath).existsSync(), isTrue,
          reason: '发放事实实体 $outcomePath 必须存在（本批次不碰 domain）');
      final String domain = File(outcomePath).readAsStringSync();
      expect(domain.contains('seedSpeciesId'), isTrue,
          reason: '发放事实字段 seedSpeciesId 必须保留（按 id 记券）');
      expect(domain.contains('decomposedSeedSpeciesId'), isTrue,
          reason: '分解事实字段也必须保留');

      const String repoPath =
          'lib/domain/repositories/bloom_reward_repository.dart';
      if (File(repoPath).existsSync()) {
        final String repo = File(repoPath).readAsStringSync();
        expect(repo.contains('unlockSpecies'), isTrue,
            reason: 'unlockSpecies(speciesId) 签名不得变（动了破库存）');
      }
      // 本批次不碰 domain：garden_page 里不得出现「改写发放」的字样。
      expect(src.contains('seedSpeciesId ='), isFalse);
    });
  });
}
