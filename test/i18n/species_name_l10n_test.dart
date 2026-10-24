/// 植物物种名本地化守卫（i18n B3 · T04）。
///
/// ## 迁移动机
/// 迁移前物种中文名**就是种子数据**（`plant_seed.dart` 的
/// `kSeedPlantSpecies[i].name`），UI 各处直接读 `species.name` → 英文环境下花园里
/// 仍是「向日葵 / 月光兰」，报告与奖励文案串同理。
///
/// ## 本文件守什么
/// ① **zh 逐字节等价**：6 个物种在 zh 下必须与迁移前的种子名一字不差（否则老用户
///    看到的名字被悄悄改了）；
/// ② **en 真英文且无 CJK**：这是本批的目的；
/// ③ **未知 id → `null`**（不是空串、不是 id、不是「未知植物」）：兜底口径留在
///    调用点 —— 花盆格要「未知植物」、奖励串要原始 id，两者不同，映射层不许统一；
/// ④ **真实组件取证**：`GardenPot` / `PlantCard` 在 en 下必须渲染 `Sunflower`
///    且「向日葵」消失。只在映射函数单测里断言 `speciesNameOrNull` 是**不够**的：
///    漏接线（UI 仍读 `species.name`）时单测照样绿，只有泵真组件才能证伪；
/// ⑤ **反向守卫**：两个组件源码里不得再出现裸 `species.name` 直渲染。
library species_name_l10n_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/i18n/species_l10n.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_card.dart';

/// zh / en 期望表（顺序与 [kKnownSpeciesIds] 一致）。
///
/// zh 列是**迁移前种子数据里的原文**，逐字节抄自 `plant_seed.dart`（T04 时点）。
const Map<String, String> _zhExpected = <String, String>{
  'species_sunflower': '向日葵',
  'species_moon_orchid': '月光兰',
  'species_tomato': '番茄',
  'species_strawberry': '草莓',
  'species_coral_orchid': '珊瑚岭兰',
  'species_jade_hydrangea': '翡翠绣球',
  'species_grape': '葡萄', // F151（2026-10-23 精英档）
};

const Map<String, String> _enExpected = <String, String>{
  'species_sunflower': 'Sunflower',
  'species_moon_orchid': 'Moon Orchid',
  'species_tomato': 'Tomato',
  'species_strawberry': 'Strawberry',
  'species_coral_orchid': 'Coral Ridge Orchid',
  'species_jade_hydrangea': 'Jade Hydrangea',
  'species_grape': 'Grape', // F151（2026-10-23 精英档）
};

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');

PlantSpecies _speciesOf(String id, String name) => PlantSpecies(
      id: id,
      name: name,
      rarity: Rarity.common,
      baseCostHigh: 40,
      baseCostLow: 20,
      growthHoursPerStage: 240,
    );

Plant _plantOf(String speciesId, {PlantStatus status = PlantStatus.growing}) {
  final DateTime t = DateTime(2026, 2, 2, 8);
  return Plant(
    id: 'p1',
    speciesId: speciesId,
    potIndex: 0,
    stage: PlantStage.sprout,
    stageStartedAt: t,
    growthProgress: 0.4,
    growthFactor: 1.0,
    status: status,
    plantedAt: t,
  );
}

/// 裸宿主 + 页级 `L10nScope`（locale 由 `AppLocaleController.init` 决定）。
///
/// 故意不接 ProviderScope：`GardenPot` / `PlantCard` 是纯组件（无业务依赖），
/// 接容器只会掩盖「组件偷偷依赖 provider」这类问题。
Widget _host(Widget child) => MaterialApp(
      home: L10nScope(
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 360, child: child),
          ),
        ),
      ),
    );

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  tearDown(() => AppLocaleController.init(AppLanguage.system));

  // ─────────────────────── ① zh 逐字节等价 ───────────────────────
  group('① speciesNameOrNull · zh 逐字节等价', () {
    test('7 个已知物种全部命中既有中文名', () {
      expect(kKnownSpeciesIds.length, 7, reason: 'F151 起为 7 种（+葡萄）');
      for (final String id in kKnownSpeciesIds) {
        expect(_zhExpected.containsKey(id), isTrue, reason: '缺期望值：$id');
        expect(
          speciesNameOrNull(id, zh),
          _zhExpected[id],
          reason: 'zh 下 $id 必须与种子数据原文一字不差',
        );
      }
    });

    test('kKnownSpeciesIds 无重复、无空值', () {
      expect(kKnownSpeciesIds.toSet().length, kKnownSpeciesIds.length);
      for (final String id in kKnownSpeciesIds) {
        expect(id, isNotEmpty);
      }
    });
  });

  // ─────────────────────── ② en 真英文 ───────────────────────
  group('② speciesNameOrNull · en 生效（本批目的）', () {
    test('6 个物种全部 output 英文且无 CJK', () {
      for (final String id in kKnownSpeciesIds) {
        final String? name = speciesNameOrNull(id, en);
        expect(name, _enExpected[id], reason: 'en 下 $id');
        expect(name, isNotNull);
        expect(_cjk.hasMatch(name!), isFalse, reason: 'en 物种名含 CJK：$name');
      }
    });

    test('6 个英文名互不相同（防复制粘贴成同名）', () {
      final Set<String> names = <String>{
        for (final String id in kKnownSpeciesIds) speciesNameOrNull(id, en)!,
      };
      expect(names.length, kKnownSpeciesIds.length);
    });
  });

  // ─────────────────────── ③ 未知 id 兜底口径 ───────────────────────
  group('③ 未知 id → null（兜底留在调用点）', () {
    test('历史上被删 / 拼错的 id 一律 null，不返回 id 也不返回「未知植物」', () {
      const List<String> unknown = <String>[
        'species_star_flower', // 历史被删的星辰花
        'species_rainbow_fern', // 历史被删的虹影蕨
        '',
        'SPECIES_SUNFLOWER', // 大小写敏感
        ' species_sunflower', // 前导空格
      ];
      for (final String id in unknown) {
        expect(speciesNameOrNull(id, zh), isNull, reason: 'zh 未知 id：`$id`');
        expect(speciesNameOrNull(id, en), isNull, reason: 'en 未知 id：`$id`');
      }
    });

    test('speciesNameOr 回退到 fallback（花盆格 / 植物卡口径）', () {
      expect(speciesNameOr('species_sunflower', '回退值', zh), '向日葵',
          reason: '已知 id 不该用 fallback');
      expect(speciesNameOr('species_x', '未知植物', zh), '未知植物');
      expect(speciesNameOr('species_x', 'Unknown plant', en), 'Unknown plant');
    });

    test('speciesNameOr 的 fallback 口径可与 speciesNameOrNull 不同（奖励串用 id）', () {
      // 奖励文案串的兜底是「原始 id」—— 证明这层不带自己的兜底是必要的。
      expect(speciesNameOr('species_x', 'species_x', zh), 'species_x');
    });
  });

  // ─────────────────────── ④ 真实组件取证 ───────────────────────
  group('④ 真实组件 en 下渲染英文', () {
    testWidgets('GardenPot（growing）en → Sunflower，中文消失',
        (WidgetTester tester) async {
      AppLocaleController.init(AppLanguage.en);
      await tester.pumpWidget(
        _host(
          GardenPot(
            plant: _plantOf('species_sunflower'),
            species: _speciesOf('species_sunflower', '向日葵'),
            onTap: () {},
            onClearWeed: () {},
            onClearPest: () {},
          ),
        ),
      );
      // 无害虫 → 无无限动画，但仍用定量 pump（花园子树有呼吸动画的历史坑）。
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Sunflower'), findsOneWidget,
          reason: '花盆格标签必须走 ARB（growing 态裸标签 = 物种名）');
      expect(find.text('向日葵'), findsNothing,
          reason: 'en 下不许出现中文物种名（说明 UI 仍读 species.name）');
    });

    testWidgets('GardenPot（bloomed）en → 带参标签也是英文',
        (WidgetTester tester) async {
      AppLocaleController.init(AppLanguage.en);
      await tester.pumpWidget(
        _host(
          GardenPot(
            plant: _plantOf('species_moon_orchid', status: PlantStatus.bloomed),
            species: _speciesOf('species_moon_orchid', '月光兰'),
            onTap: () {},
            onClearWeed: () {},
            onClearPest: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // `pot_label_bloomed(name)` 的 en 正文含 Moon Orchid。
      expect(
        find.textContaining('Moon Orchid', findRichText: true),
        findsWidgets,
        reason: '盛开态标签走 pot_label_bloomed(name)，name 必须是英文',
      );
      expect(find.textContaining('月光兰', findRichText: true), findsNothing);
    });

    testWidgets('GardenPot zh 下行為不变（逐字等价兜底）',
        (WidgetTester tester) async {
      AppLocaleController.init(AppLanguage.zh);
      await tester.pumpWidget(
        _host(
          GardenPot(
            plant: _plantOf('species_sunflower'),
            species: _speciesOf('species_sunflower', '向日葵'),
            onTap: () {},
            onClearWeed: () {},
            onClearPest: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('向日葵'), findsOneWidget);
      expect(find.text('Sunflower'), findsNothing);
    });

    testWidgets('PlantCard en → Sunflower，中文消失', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      AppLocaleController.init(AppLanguage.en);
      await tester.pumpWidget(
        _host(
          PlantCard(
            plant: _plantOf('species_sunflower'),
            species: _speciesOf('species_sunflower', '向日葵'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Sunflower'), findsOneWidget, reason: '卡片标题 = 物种名');
      expect(find.text('向日葵'), findsNothing);
    });

    testWidgets('PlantCard zh → 向日葵', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      AppLocaleController.init(AppLanguage.zh);
      await tester.pumpWidget(
        _host(
          PlantCard(
            plant: _plantOf('species_sunflower'),
            species: _speciesOf('species_sunflower', '向日葵'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('向日葵'), findsOneWidget);
    });
  });

  // ─────────────────────── ⑤ 反向守卫 ───────────────────────
  group('⑤ 反向守卫（UI 不得直读 species.name 上屏）', () {
    /// 允许 `species.name` 的**唯一**用法：作 `speciesNameOr(...)` 的 fallback 实参。
    ///
    /// 先剥注释：这些文件的文档正当地写着「`species.name` 已被兜成…」。
    void assertNoBareSpeciesName(String path) {
      final String src = _stripComments(File(path).readAsStringSync());
      final RegExp bare = RegExp(r'species\.name');
      final Iterable<RegExpMatch> hits = bare.allMatches(src);
      for (final RegExpMatch m in hits) {
        final int lineStart = src.lastIndexOf('\n', m.start) + 1;
        int lineEnd = src.indexOf('\n', m.end);
        if (lineEnd < 0) {
          lineEnd = src.length;
        }
        final String line = src.substring(lineStart, lineEnd);
        expect(
          line.contains('speciesNameOr('),
          isTrue,
          reason: '$path 出现裸 `species.name` 上屏：$line\n'
              '物种名必须走 core/i18n/species_l10n.dart',
        );
      }
    }

    test('GardenPot / PlantCard 无裸 species.name 渲染', () {
      assertNoBareSpeciesName('lib/presentation/child/widgets/garden_pot.dart');
      assertNoBareSpeciesName('lib/presentation/child/widgets/plant_card.dart');
    });

    test('其余接线点同样走 species_l10n', () {
      for (final String path in <String>[
        'lib/presentation/child/widgets/plant_confirm_dialog.dart',
        'lib/presentation/child/widgets/child_avatar.dart',
        'lib/presentation/child/widgets/plant_care_sheet.dart',
      ]) {
        final String src = _stripComments(File(path).readAsStringSync());
        expect(src.contains('speciesNameOr'), isTrue,
            reason: '$path 必须经 species_l10n 取物种名');
      }
    });

    test('映射层只做 switch、不含兜底文案', () {
      final String code =
          _stripComments(File('lib/core/i18n/species_l10n.dart').readAsStringSync());
      // 兜底口径留在调用点：映射层不许自己造「未知植物」「Unknown plant」。
      expect(code.contains('unknown'), isFalse,
          reason: '未知物种的兜底留在调用点，映射层不许自带「未知」文案');
      expect(code.contains('未知'), isFalse);
      expect(code.contains('?? speciesId'), isFalse);
      // 反向：确认它确实只有 switch + null（不是把兜底搬进来后仍叫这个名字）。
      expect(code.contains('return null;'), isTrue);
    });
  });
}

/// 剥掉 `//` 行注释与 `/* */` 块注释（字符串字面量不特殊处理，宁可误红）。
String _stripComments(String src) {
  final List<String> out = <String>[];
  bool inBlock = false;
  for (final String raw in src.split('\n')) {
    String line = raw;
    if (inBlock) {
      final int end = line.indexOf('*/');
      if (end < 0) {
        out.add('');
        continue;
      }
      line = line.substring(end + 2);
      inBlock = false;
    }
    final int lineComment = line.indexOf('//');
    final int blockComment = line.indexOf('/*');
    if (lineComment >= 0 && (blockComment < 0 || lineComment < blockComment)) {
      line = line.substring(0, lineComment);
    } else if (blockComment >= 0) {
      final int end = line.indexOf('*/', blockComment + 2);
      if (end < 0) {
        inBlock = true;
        line = line.substring(0, blockComment);
      } else {
        line = line.substring(0, blockComment) + line.substring(end + 2);
      }
    }
    out.add(line);
  }
  return out.join('\n');
}
