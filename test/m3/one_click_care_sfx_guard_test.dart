/// P0 源码守卫 · 一键护理补音效 + 图标与音效时长对齐（玄参 2026-10-07）。
///
/// 用户口径：「一键护理目前没有对应的音效，我建议使用除虫的音效吧，注意护理的图标和
/// 音效时长要对齐」。
///
/// 音频播放无法在 headless widget 测试里断言（无音频后端），沿用项目既有「源码守卫」
/// 手法，把三处硬口径钉死：
///  ① 一键护理成功分支按**实际护理内容**选音效（整批一次，不逐株叠加）：
///     存在任一害虫目标 → `carePest`；全是杂草 → `careWeed`（玄参 2026-10-07 口径，
///     取代旧的「一律 carePest」）。
///  ② 一键护理的轻脉冲清场时长 = `kCarePestDurationMs + 150`（与浇水/施肥同规则）；
///  ③ 轻脉冲（[CareEffectType.weed] / [CareEffectType.pest]）显示时长 = `kCarePestDurationMs`。
library one_click_care_sfx_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';

void main() {
  final String src =
      File('lib/presentation/child/pages/garden_page.dart').readAsStringSync();
  final String audioSrc =
      File('lib/platform/audio_service.dart').readAsStringSync();

  test('① 一键护理成功分支按实际内容选音效（有虫→carePest；全草→careWeed，整批一次）', () {
    // 玄参 2026-10-07：「如果只有杂草，就播放除草的音效；如果有除虫和除草，就播放除虫的
    // 音效」→ 成功分支必须**按 careTargets 内容**二选一，且整批只播一次（不在循环内）。
    expect(
      RegExp(r'if \(kind == PlantOneClickKind\.care\) \{[\s\S]{0,200}?'
              r'playSfx\(hasPest \? AudioCue\.carePest : AudioCue\.careWeed\)')
          .hasMatch(src),
      isTrue,
      reason: '一键护理应「有虫播 carePest、全草播 careWeed」，且整批只播一次（不在循环内）',
    );
    // 该分支必须由「是否存在害虫目标」驱动（防止退化为硬编码单音）。
    expect(
      RegExp(r'plan\.careTargets\.any\(\(t\) => !t\.weed\)').hasMatch(src),
      isTrue,
      reason: '选音依据必须是 plan.careTargets 是否存在害虫目标（content-based）',
    );
  });

  test('② 一键护理轻脉冲清场时长 = kCarePestDurationMs + 150', () {
    expect(
      RegExp(r'PlantOneClickKind\.care => kCarePestDurationMs \+ 150')
          .hasMatch(src),
      isTrue,
      reason: '一键护理图标显示时长必须与除虫音效等长 + 150ms 余量',
    );
  });

  test('③ 轻脉冲（草/虫）显示时长 = kCarePestDurationMs（与音效对齐）', () {
    expect(
      RegExp(r'CareEffectType\.weed \|\| CareEffectType\.pest => '
              r'kCarePestDurationMs')
          .hasMatch(src),
      isTrue,
      reason: '轻脉冲图标显示时长必须与除虫音效对齐（原写死 1s 与音效不齐）',
    );
  });

  test('④ carePest cue 的 mp3 真实存在', () {
    expect(audioSrc.contains("case AudioCue.carePest:"), isTrue);
    expect(kCarePestDurationMs, greaterThanOrEqualTo(3000),
        reason: 'sfx mp3 时长红线 ≥3s（iOS CoreAudio -11849）');
  });
}
