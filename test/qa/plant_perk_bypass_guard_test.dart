/// C80 · **称号属性「当前属性」旁路守卫**（源码守卫 · 付费墙阶段 5 · T05）。
///
/// ## 为什么存在（🔴 代码红线）
/// C80 把「当前称号专属属性」的判定收敛到**两个单点**：
///  1. `currentPlantPerkProvider`（`providers.dart`，读 `FeatureKey.titlePerks` 门控后
///     走 `perkOfLevel`，**唯一生产出口**）；
///  2. `PlantGrowthService.currentPerk()`（`plant_growth_service.dart`，域层防线缺省）。
///
/// 若**其它**文件各写一份 `perkOfLevel(levelOfMinutes(totalStats()))`，就会出现
/// 「孪生判定」——某处漏读 entitlement 门控 → 免费用户在某个入口误享付费属性
/// （G3「展示与发放一致」被击穿）。本测试直读 `lib/**.dart` 源码，把 `perkOfLevel`
/// **钉死在 4 个白名单文件内**，其它任何文件出现即红。
///
/// ## 白名单（`lib/**` 内**恰好 4 文件**，逐个注释用途）
///  · `plant_perk.dart`：定义本体（[perkOfLevel]）+ `kPlantPerkPerTitleNode` 累积内部；
///  · `providers.dart`：provider 单点 —— **唯一生产出口**；
///  · `plant_growth_service.dart`：域层防线缺省（`currentPerk()`，C80 门控版）；
///  · `level_up_fx_overlay.dart`：**演出展示特例**（按 `shownLevel` 派生展示内容，
///    非「当前属性」语义；C80 免费锁标即基于该行渲染）。
///
/// ## 附加断言（PRD 验收 A-1）
///  · `kLevelPerkLegendText` 在 `lib/**` **零出现**（详情卡图例区已删，防常量复活）。
///
/// 范式参照 `entitlement_gate_guard_test.dart`（读源码 + 白名单 + 整行注释豁免）。
library plant_perk_bypass_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/qa') || cwd.endsWith('\\test\\qa')
      ? Directory.current.parent.parent.path
      : cwd;
}

/// 允许出现 `perkOfLevel` 的白名单（相对工程根，使用 `/` 分隔，**恰好 4 文件**）。
final Set<String> _whitelist = <String>{
  // 定义本体：`perkOfLevel` 函数声明 + `kPlantPerkPerTitleNode` 累积内部。
  'lib/domain/services/plant_perk.dart',
  // provider 单点：`currentPlantPerkProvider`，**唯一生产出口**。
  'lib/core/di/providers.dart',
  // 域层防线缺省：`PlantGrowthService.currentPerk()`（C80 门控版）。
  'lib/domain/services/plant_growth_service.dart',
  // 演出展示特例：`_LevelUpContent` 按 `shownLevel` 派生展示内容（非「当前属性」语义）。
  'lib/presentation/child/widgets/level_up_fx_overlay.dart',
};

/// 旁路禁用 token：`perkOfLevel`（词边界、大小写敏感）。
final RegExp _bypassToken = RegExp(r'\bperkOfLevel\b');

/// 已删除的图例常量：`lib/**` 内**零出现**（防复活）。
const String _kRemovedLegendConst = 'kLevelPerkLegendText';

/// 把绝对路径转成相对工程根的、以 `/` 分隔的路径。
String _rel(String root, String absPath) =>
    absPath.substring(root.length + 1).replaceAll('\\', '/');

void main() {
  final String root = _projectRoot();

  test('守卫自身非空：token 能命中一段典型的旁路代码（变异自检）', () {
    const String sample = 'final p = perkOfLevel(levelOfMinutes(m));';
    expect(_bypassToken.hasMatch(sample), isTrue,
        reason: '禁用词必须能命中旁路直连调用，否则守卫形同虚设');
    expect(_bypassToken.hasMatch('perkOfTitleNode(5)'), isFalse,
        reason: '不得误伤 perkOfTitleNode（节点级派生，非「当前属性」出口）');
    expect(_bypassToken.hasMatch('perkOfLevelX'), isFalse,
        reason: '词边界不得误命中前缀相近的标识符');
  });

  test('白名单文件真实存在（防拼写漂移使守卫失效）', () {
    for (final String rel in _whitelist) {
      expect(File('$root/$rel').existsSync(), isTrue,
          reason: '白名单文件不应缺失（缺失说明重构后守卫白名单失效）：$rel');
    }
    expect(_whitelist.length, 4, reason: '旁路白名单必须**恰好 4 文件**（新增需附合法用途）');
  });

  test('perkOfLevel 只允许出现在白名单文件内（lib/**.dart）', () {
    final Directory lib = Directory('$root/lib');
    expect(lib.existsSync(), isTrue, reason: '缺 lib 目录');

    final List<String> violations = <String>[];
    final List<File> dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    for (final File f in dartFiles) {
      final String rel = _rel(root, f.path);
      if (_whitelist.contains(rel)) continue;
      final List<String> lines = f.readAsStringSync().split('\n');
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        // 🔴 判据精度（与 entitlement_gate_guard 同纪律）：**整行注释**不计入违例 ——
        //    守卫拦的是「代码旁路直连 perkOfLevel 取当前属性」，文档/注释里**提到**该词
        //    （如 prd_params.dart 的公式说明）不是旁路点，不算违宪。
        if (line.trimLeft().startsWith('//')) continue;
        if (_bypassToken.hasMatch(line)) {
          violations.add('$rel:${i + 1} 出现「perkOfLevel」→ $line');
        }
      }
    }

    expect(violations, isEmpty,
        reason: '称号属性旁路：以下文件直连 `perkOfLevel` 取「当前属性」却不在白名单内。\n'
            '请改为读 `currentPlantPerkProvider` / 调 `PlantGrowthService.currentPerk()`'
            '（门控单点），或（若确为合法展示特例）加入本测试白名单：\n'
            '${violations.join('\n')}');
  });

  test('图例常量零残留：kLevelPerkLegendText 在 lib/** 零出现（C80 P0-1，防复活）', () {
    final Directory lib = Directory('$root/lib');
    final List<String> hits = <String>[];
    for (final File f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final String rel = _rel(root, f.path);
      final List<String> lines = f.readAsStringSync().split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains(_kRemovedLegendConst)) {
          hits.add('$rel:${i + 1} → ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty,
        reason: '详情卡图例区常量 `$_kRemovedLegendConst` 已删除（P0-1），不得复活：\n'
            '${hits.join('\n')}');
  });
}
