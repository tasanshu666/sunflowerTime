/// 守卫战 v2 · **素材命名规范扫描**（B5a · 设计验收判据②）。
///
/// 真源：`docs/美术资源_序列帧与音频命名规范_v1.md`（玄参落盘契约）+
/// 守卫战设计文档 §7-B5「验收判据②」。
///
/// ## 扫描规则（`assets/guard/**` 全量）
///  · **序列帧**：`frame(\d{3})(@2x|@3x)?\.(png|webp)` —— `frame001` **起始**、
///    三位零填充、目录内**连续**编号；
///  · **密度变体成对**：目录里出现任一 `@2x` / `@3x` ⇒ 三档（基准 / @2x / @3x）
///    必须逐帧一一配对，不许有孤儿变体（漏一档 = 真机高分屏加载失败）；
///  · **静态图**（B5b 增补，玄参首批交付含 3 张静态）：`snake_case.(png|webp)`
///    —— 如 `soldier_attack.webp` / `house.webp`；
///  · **音频**：`snake_case.mp3`（全小写字母数字下划线）；
///  · **其他任何文件名 = 红**（列出违规文件全路径）。
///
/// ## 🔴 空目录 / 不存在 ⇒ skip 而不是红
/// 玄参素材尚未交付（B5b 才接素材，本批红线：`assets/` 不动）。skip 消息写明
/// 状态，素材到位后本护栏**自动生效** —— 首个乱名文件就会在 CI 上亮红。
library guard_asset_naming_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _kGuardAssetDir = 'assets/guard';

/// 目录存在且至少有一个文件（B5b 前恒 false ⇒ skip）。
bool _hasFiles() {
  final Directory dir = Directory(_kGuardAssetDir);
  if (!dir.existsSync()) return false;
  try {
    return dir.listSync(recursive: true).whereType<File>().isNotEmpty;
  } catch (_) {
    return false;
  }
}

void main() {
  final bool hasFiles = _hasFiles();

  test(
    'assets/guard 全量命名符合《美术资源_序列帧与音频命名规范_v1》',
    () {
      final Directory dir = Directory(_kGuardAssetDir);
      final List<File> files =
          dir.listSync(recursive: true).whereType<File>().toList();
      expect(files, isNotEmpty, reason: 'skip 判据已通过 ⇒ 目录里必须有文件');

      // 帧名：`frame(\d{3})(@2x|@3x)?\.(png|webp)`；静态图：snake_case 图；
      // 音频：snake_case.mp3。
      final RegExp frameRe =
          RegExp(r'^frame(\d{3})(@2x|@3x)?\.(png|webp)$');
      final RegExp staticRe = RegExp(r'^[a-z0-9_]+\.(png|webp)$');
      final RegExp audioRe = RegExp(r'^[a-z0-9_]+\.mp3$');

      // dirKey → (密度 → 帧号集合)。密度 '' = 基准、'@2x' / '@3x' = 高分档。
      final Map<String, Map<String, Set<int>>> frames =
          <String, Map<String, Set<int>>>{};
      final List<String> audioFiles = <String>[];
      final List<String> staticFiles = <String>[];

      final List<String> violations = <String>[];
      for (final File f in files) {
        final String rel = f.path
            .replaceAll('\\', '/')
            .replaceFirst('assets/guard/', '')
            .replaceFirst('assets/guard', '');
        final int slash = rel.lastIndexOf('/');
        final String dirKey =
            slash < 0 ? '(root)' : rel.substring(0, slash);
        final String name = slash < 0 ? rel : rel.substring(slash + 1);

        final RegExpMatch? m = frameRe.firstMatch(name);
        if (m != null) {
          final String density = m.group(2) ?? '';
          final int number = int.parse(m.group(1)!); // 三位零填充已由正则钉住
          frames.putIfAbsent(dirKey, () => <String, Set<int>>{})
              .putIfAbsent(density, () => <int>{})
              .add(number);
          continue;
        }
        if (staticRe.hasMatch(name)) {
          staticFiles.add(rel);
          continue;
        }
        if (audioRe.hasMatch(name)) {
          audioFiles.add(rel);
          continue;
        }
        violations.add(rel);
      }

      // ① 任何不合模式的文件名都算违规（首位就是规范本身）。
      expect(violations, isEmpty,
          reason: '🔴 以下文件不符合命名规范（序列帧必须 frameNNN 起始三位零填充'
              '、可带 @2x/@3x；静态图 / 音频必须 snake_case）：$violations');

      // ② 帧号从 001 起始且连续（每个 目录 × 密度 独立校验）。
      frames.forEach((String dirKey, Map<String, Set<int>> byDensity) {
        byDensity.forEach((String density, Set<int> numbers) {
          final List<int> sorted = numbers.toList()..sort();
          expect(sorted.first, 1,
              reason: '$dirKey/$density：序列帧必须从 frame001 起始');
          for (int i = 0; i < sorted.length; i++) {
            expect(sorted[i], sorted.first + i,
                reason: '$dirKey/$density：帧号必须连续（发现缺帧/跳号）');
          }
        });

        // ③ @2x / @3x 成对：出现任一密度变体 ⇒ 三档逐帧配对。
        final Set<int> plain = byDensity[''] ?? <int>{};
        final Set<int> x2 = byDensity['@2x'] ?? <int>{};
        final Set<int> x3 = byDensity['@3x'] ?? <int>{};
        if (x2.isNotEmpty || x3.isNotEmpty) {
          expect(x2, plain,
              reason: '$dirKey：@2x 与基准帧必须逐帧成对（缺 = 高分屏加载失败）');
          expect(x3, plain,
              reason: '$dirKey：@3x 与基准帧必须逐帧成对（缺 = 高分屏加载失败）');
        }
      });

      // ④ 分类登记回显（信息性断言：只要有文件就必须能被识别进三类之一）。
      // ignore: avoid_print
      print('guard assets: frames=${frames.values.fold<int>(0, (int n, Map<String, Set<int>> d) => n + d.values.fold<int>(0, (int m, Set<int> s) => m + s.length))} '
          'statics=${staticFiles.length} audio=${audioFiles.length}');
      expect(
          audioFiles.length +
              staticFiles.length +
              frames.values.fold<int>(
                0,
                (int n, Map<String, Set<int>> d) =>
                    n + d.values.fold<int>(0, (int m, Set<int> s) => m + s.length),
              ),
          files.length,
          reason: '全部文件都必须被归入「序列帧 / 静态图 / 音频」三类（①已兜底违规项）');
    },
    skip: hasFiles
        ? false
        : 'assets/guard 不存在或为空 —— 玄参素材未交付（B5b 前属正常），'
            '素材落盘后本护栏自动生效',
  );
}
