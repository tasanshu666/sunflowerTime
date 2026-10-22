/// F144 · D 项：**专注称号 9 条 ARB 化**守卫。
///
/// ## 背景
/// 迁移前 9 条称号（专注小萌芽 … 时光大贤者）是 `prd_params.dart::kFocusLevelTitles`
/// 里的**中文常量**，经 `titleOfLevel` 派生到今日页徽章 / 等级详情卡 / 升级演出卡 ——
/// 英文模式下这三处**仍显示中文**（i18n B3 之后重点残留）。
///
/// 修法与 `domain_text_l10n.dart::perkNameOfTitleNodeL10n` **同构**：文案进 ARB
/// （`shared_title_lv1` … `shared_title_lv40`），领域层只留纯语义节点等级，
/// UI 统一经 `core/i18n/title_l10n.dart` 取。
///
/// ## 本文件锁五条
///  ① **zh 逐字节不变**：9 条 ARB zh 值 == C74 §3 宪法原文（零回归硬门槛）；
///  ② **en 无 CJK**：9 条英文里不得出现任何汉字（英文模式不再显中文）；
///  ③ **en 长度预算**：每条 ≤ 18 字符（玄参口径），且 ≤ **12** 字符 —— 12 是
///     今日页徽章胶囊在 iPad13（1032×1376）上的实测容量上限（胶囊预算
///     137.6pt ÷（测试字体 21.36pt/char × 缩放下限 0.52）≈ 12.4 → 12；见
///     `test/m3/badge_title_fit_ipad13_test.dart`，超 12 会被 ellipsis 成
///     `Title not u…` 那类截断。F144 玄参终审采纳 `Focus Knight`（12 字符）
///     后由 11 上调 —— 真机 SF/Roboto ≈0.5em/char ≈ 125pt，缩放比 ≈1.0，
///     **完全不缩**；11 的旧值是按 10 字符的 `Sun Knight` 校准的设计值）；
///  ④ **节点映射**：`focusLevelTitleL10n(level, t)` 按「已解锁的最高节点」取文案；
///     `focusLevelTitleRowL10n(node, t)` 只接受 9 个节点、非节点返回空串；
///  ⑤ **源码守卫**：`prd_params.dart` 里不得再出现 `kFocusLevelTitles`（防止有人
///     把中文常量加回来，导致「迁了 ARB 但 UI 仍读常量」的假迁移）。
library title_l10n_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/title_l10n.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// C74 §3 的 9 条称号**宪法原文**（zh，逐字节）。
const List<String> _c74Titles = <String>[
  '专注小萌芽', // Lv.1
  '专注小苗苗', // Lv.5
  '静心小书童', // Lv.10
  '时光小卫士', // Lv.15
  '专心小骑士', // Lv.20
  '守时小星使', // Lv.25
  '专注小法师', // Lv.30
  '星辰守护者', // Lv.35
  '时光大贤者', // Lv.40（满级）
];

/// 汉字（CJK 统一表意文字）。
final RegExp _han = RegExp(r'[\u4e00-\u9fff]');

/// 9 条英文的**长度硬上限**（玄参口径 ≤ 18，徽章胶囊实测 ≤ 12 —— 取小者）。
const int _kEnMaxChars = 12;

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  group('① zh 逐字节不变（零回归）', () {
    test('9 条 zh == C74 §3 宪法原文，且顺序 == kFocusLevelTitleLevels', () {
      expect(kFocusLevelTitleLevels.length, 9);
      expect(_c74Titles.length, 9);
      for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
        final int node = kFocusLevelTitleLevels[i];
        expect(focusLevelTitleRowL10n(node, zh), _c74Titles[i],
            reason: 'Lv.$node 的 zh 文案必须与迁移前 kFocusLevelTitles 逐字节一致');
      }
    });
  });

  group('②③ en 译文：无 CJK + 长度预算', () {
    test('9 条 en 全部不含汉字（英文模式不再显中文）', () {
      for (final int node in kFocusLevelTitleLevels) {
        final String t = focusLevelTitleRowL10n(node, en);
        expect(t, isNotEmpty, reason: 'Lv.$node 的 en 文案不得为空（缺 ARB 会回落 key 名）');
        expect(_han.hasMatch(t), isFalse, reason: 'Lv.$node 的 en 文案含汉字：「$t」');
      }
    });

    test('9 条 en 每条 ≤ $_kEnMaxChars 字符（徽章胶囊 iPad13 实测量上限）', () {
      for (final int node in kFocusLevelTitleLevels) {
        final String t = focusLevelTitleRowL10n(node, en);
        expect(t.length, lessThanOrEqualTo(_kEnMaxChars),
            reason: 'Lv.$node 的 en「$t」长 ${t.length} 字符，超过徽章胶囊可容纳的 '
                '$_kEnMaxChars（会被 ellipsis 截断）');
      }
    });

    test('9 条 en 两两不重名（防复制粘贴漏改）', () {
      final List<String> all = <String>[
        for (final int node in kFocusLevelTitleLevels)
          focusLevelTitleRowL10n(node, en),
      ];
      expect(all.toSet().length, all.length, reason: '9 条英文称号必须互不相同');
    });
  });

  group('④ 等级 → 称号映射（与已删除的 titleOfLevel 逐条等价）', () {
    test('节点上：level == node → 该节点称号', () {
      for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
        expect(focusLevelTitleL10n(kFocusLevelTitleLevels[i], zh), _c74Titles[i]);
      }
    });

    test('非节点：取「已解锁的最高称号节点」（Lv.7 → Lv.5 的称号）', () {
      expect(focusLevelTitleL10n(2, zh), '专注小萌芽');
      expect(focusLevelTitleL10n(4, zh), '专注小萌芽');
      expect(focusLevelTitleL10n(7, zh), '专注小苗苗');
      expect(focusLevelTitleL10n(9, zh), '专注小苗苗');
      expect(focusLevelTitleL10n(14, zh), '静心小书童');
      expect(focusLevelTitleL10n(23, zh), '专心小骑士');
      expect(focusLevelTitleL10n(39, zh), '星辰守护者');
    });

    test('边界：level < 1 → 空串；level > 40 → 上钳到满级称号', () {
      expect(focusLevelTitleL10n(0, zh), '');
      expect(focusLevelTitleL10n(-5, zh), '');
      expect(focusLevelTitleL10n(99, zh), '时光大贤者');
      // en 侧同口径（不是兜底到中文）。
      expect(focusLevelTitleL10n(0, en), '');
      expect(focusLevelTitleL10n(99, en), focusLevelTitleRowL10n(40, en));
      expect(_han.hasMatch(focusLevelTitleL10n(99, en)), isFalse);
    });

    test('focusLevelTitleRowL10n：非节点返回空串（详情卡 9 行按节点取）', () {
      for (final int bad in <int>[0, -1, 2, 4, 7, 12, 41, 999]) {
        expect(focusLevelTitleRowL10n(bad, zh), '',
            reason: 'Lv.$bad 不是称号节点 → 必须返回空串（不是就近取档）');
      }
    });
  });

  group('⑤ 源码守卫：中文常量不得回流', () {
    test('prd_params.dart 不再出现 kFocusLevelTitles', () {
      final String src =
          File('lib/core/constants/prd_params.dart').readAsStringSync();
      expect(src.contains('kFocusLevelTitles'), isFalse,
          reason: '称号文案已迁 ARB —— prd_params 里不得再出现 kFocusLevelTitles'
              '（否则 UI 可能仍读中文常量，等于假迁移）');
      // 节点等级表必须还在（它是纯语义，不许一起删）。
      expect(src.contains('kFocusLevelTitleLevels'), isTrue,
          reason: 'kFocusLevelTitleLevels 是纯语义节点表，必须保留');
    });

    test('lib/ 下除「生成代码 / 注释」外，无任何 .dart 文件内联 9 条 zh 称号', () {
      final List<File> files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          // `lib/l10n/generated/**` 是 gen-l10n 产物，zh 文案本来就该在那里。
          .where((File f) => !f.path.contains('l10n/generated/'))
          .toList();
      expect(files, isNotEmpty);
      for (final File f in files) {
        // 注释里出现称号是**允许**的（口径文档化，如 prd_params 的 9 条属性说明）；
        // 只有「代码行」内联文案才是回归。
        final List<String> codeLines = f
            .readAsLinesSync()
            .where((String line) {
              final String s = line.trimLeft();
              return !s.startsWith('//') && !s.startsWith('*');
            })
            .toList();
        final String code = codeLines.join('\n');
        for (final String title in _c74Titles) {
          expect(code.contains(title), isFalse,
              reason: '${f.path} 的代码行内联了中文称号「$title」—— 必须走 ARB');
        }
      }
    });
  });
}
