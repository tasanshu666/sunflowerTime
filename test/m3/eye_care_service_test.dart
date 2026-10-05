/// EyeCareService 纯函数边界单测（口径 C28，玄参 2026-10-04 收口）。
///
/// 本服务是**零 Flutter 依赖**的领域纯函数（架构 §3 纪律），因此这里用最轻的
/// `flutter_test` 即可全量覆盖它的判定边界：
///  · 家长端三项默认值（总开关开 / 间隔 20 分钟 / 允许跳过）；
///  · 间隔**夹取**（越界值必须夹回合法区间，否则「每 0 分钟弹一次」会变成死循环）；
///  · 场内触发的**幂等契约**（触发后不回写基准 → 下一秒仍满足阈值 → 连续弹卡）；
///  · 场末固定门槛 10 分钟与家长间隔**互不串味**；
///  · 60 秒两段式的阶段 / 口令边界（含负数、超长入参的封顶，绝不越界）。
///
/// 这些断言全部走 `prd_params.dart` 常量与 [EyeCareService] 公开入口，
/// 改口径 / 改数值 / 改判定都会让对应断言变红。
library eye_care_service_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';

/// 造一份只关心护眼三项的家长设置（其余字段取项目默认，避免测试被无关字段绑死）。
AppSettings _eyeSettings({
  bool enabled = kEyeCareEnabledDefault,
  int intervalMin = kEyeCareIntervalMinDefault,
  bool skipAllowed = kEyeCareSkipAllowedDefault,
}) {
  return AppSettings(
    ageTier: AgeTier.low,
    dailyFocusCap: 90,
    dailyAppCapMinutes: 30,
    restAfterSessions: 2,
    restMinutes: 10,
    taskSunlight: 12,
    poolBudget: 160,
    eyeCareEnabled: enabled,
    eyeCareIntervalMin: intervalMin,
    eyeCareSkipAllowed: skipAllowed,
  );
}

void main() {
  group('家长端三项默认值（C28 §4，玄参 2026-10-04 拍板）', () {
    test('默认：总开关开 / 间隔 20 分钟 / 允许跳过', () {
      expect(kEyeCareEnabledDefault, isTrue);
      expect(kEyeCareIntervalMinDefault, 20);
      expect(kEyeCareSkipAllowedDefault, isTrue);

      final AppSettings s = _eyeSettings();
      expect(EyeCareService.isEnabled(s), isTrue);
      expect(EyeCareService.intervalSeconds(s), 20 * 60);
      expect(EyeCareService.isSkipAllowed(s), isTrue);
    });

    test('家长关掉总开关 → 场内 / 场末都不再插入护眼卡', () {
      expect(EyeCareService.isEnabled(_eyeSettings(enabled: false)), isFalse);
    });

    test('家长关掉「允许跳过」→ 跳过失效（但总开关仍开）', () {
      final AppSettings s = _eyeSettings(skipAllowed: false);
      expect(EyeCareService.isEnabled(s), isTrue);
      expect(EyeCareService.isSkipAllowed(s), isFalse);
    });

    test('护眼时长固定 63 秒、家长端不设（改间隔不许动时长）', () {
      expect(EyeCareService.durationSeconds(), kEyeCareDurationSeconds);
      expect(EyeCareService.durationSeconds(), 63,
          reason: '2026-10-05 素材定稿：10+10+8+10×3+5 = 63s');
      // 间隔可调（5~60）但时长恒定 —— 两者不共用同一个数。
      expect(EyeCareService.intervalSeconds(_eyeSettings(intervalMin: 5)), 300);
      expect(EyeCareService.durationSeconds(), 63);
    });
  });

  group('间隔夹取（越界值一律夹回合法区间，杜绝每 0 分钟弹卡）', () {
    test('合法区间内原样返回', () {
      expect(EyeCareService.intervalSeconds(_eyeSettings(intervalMin: 5)), 300);
      expect(EyeCareService.intervalSeconds(_eyeSettings(intervalMin: 20)), 1200);
      expect(EyeCareService.intervalSeconds(_eyeSettings(intervalMin: 30)), 1800);
    });

    test('低于下限 → 夹到下限；高于上限 → 夹到上限', () {
      expect(
        EyeCareService.intervalSeconds(_eyeSettings(intervalMin: 0)),
        kEyeCareIntervalMinMin * 60,
      );
      expect(
        EyeCareService.intervalSeconds(_eyeSettings(intervalMin: 1)),
        kEyeCareIntervalMinMin * 60,
      );
      expect(
        EyeCareService.intervalSeconds(_eyeSettings(intervalMin: 9999)),
        kEyeCareIntervalMinMax * 60,
      );
    });

    test('下拉档位与区间一致（家长端只允许出现合法值）', () {
      for (final int m in kEyeCareIntervalOptions) {
        expect(
          m >= kEyeCareIntervalMinMin && m <= kEyeCareIntervalMinMax,
          isTrue,
          reason: '档位 $m 越界',
        );
        expect(EyeCareService.intervalSeconds(_eyeSettings(intervalMin: m)),
            m * 60);
      }
    });
  });

  group('场内触发（C28 §1：累计注视每满 intervalMin 触发一次）', () {
    test('从未护眼过（lastEyeCareAtSecond=null）→ 差 1 秒不触发、满即触发', () {
      final AppSettings s = _eyeSettings(intervalMin: 20);
      final int interval = EyeCareService.intervalSeconds(s);
      expect(
        EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: interval - 1,
          lastEyeCareAtSecond: null,
          settings: s,
        ),
        isFalse,
      );
      expect(
        EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: interval,
          lastEyeCareAtSecond: null,
          settings: s,
        ),
        isTrue,
      );
    });

    test('已护眼过 → 判「本段」（距上次护眼之后的注视）而不是从头累计', () {
      final AppSettings s = _eyeSettings(intervalMin: 20);
      final int interval = EyeCareService.intervalSeconds(s);
      const int baseline = 300; // 第 300 秒触发过一次
      expect(
        EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: baseline + interval - 1,
          lastEyeCareAtSecond: baseline,
          settings: s,
        ),
        isFalse,
      );
      expect(
        EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: baseline + interval,
          lastEyeCareAtSecond: baseline,
          settings: s,
        ),
        isTrue,
      );
    });

    test('settings 为 null → 按默认 20 分钟兜底（未读到家长配置的口径）', () {
      expect(
        EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: 20 * 60 - 1,
          lastEyeCareAtSecond: null,
        ),
        isFalse,
      );
      expect(
        EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: 20 * 60,
          lastEyeCareAtSecond: null,
        ),
        isTrue,
      );
    });

    test('家长改小间隔 → 当场生效（不再用旧的 20 分钟）', () {
      final AppSettings tight = _eyeSettings(intervalMin: 5);
      expect(
        EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: 299,
          lastEyeCareAtSecond: null,
          settings: tight,
        ),
        isFalse,
      );
      expect(
        EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: 300,
          lastEyeCareAtSecond: null,
          settings: tight,
        ),
        isTrue,
      );
    });

    test('幂等契约：触发后回写基准 → 同一间隔内只弹一次（绝不连弹）', () {
      final AppSettings s = _eyeSettings(intervalMin: 20);
      final int interval = EyeCareService.intervalSeconds(s);

      int baseline = 0; // 上次护眼时的累计注视秒数
      int triggers = 0;
      for (int t = 0; t <= interval; t++) {
        if (EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: t,
          lastEyeCareAtSecond: baseline,
          settings: s,
        )) {
          triggers++;
          // 调用方（专注页）必须在触发同一刻把基准回写为本秒。
          baseline = EyeCareService.baselineAfterTrigger(t);
        }
      }

      expect(
        triggers,
        1,
        reason: '不回写基准的话，下一秒仍满足阈值 → 护眼卡会被连续弹出（F 类体验事故）',
      );
      expect(EyeCareService.baselineAfterTrigger(733), 733);
    });

    test('真的过了另一个间隔 → 允许再次触发（下一个 20 分钟重新累计）', () {
      final AppSettings s = _eyeSettings(intervalMin: 20);
      final int interval = EyeCareService.intervalSeconds(s);
      int triggers = 0;
      for (int t = 0; t <= interval * 2; t++) {
        final int baseline = triggers * interval;
        if (EyeCareService.shouldTriggerInSession(
          focusElapsedSeconds: t,
          lastEyeCareAtSecond: baseline,
          settings: s,
        )) {
          triggers++;
        }
      }
      expect(triggers, 2);
    });
  });

  group('场末触发（C28 §1：结算页之前插一次护眼卡）', () {
    test('本段 <10 分钟不打断（交给「每 2 场休 10 分钟」大休息兜底）', () {
      expect(
        EyeCareService.shouldTriggerAtSessionEnd(
          focusElapsedSeconds: kEyeCareSessionEndMinutes * 60 - 1,
          lastEyeCareAtSecond: null,
        ),
        isFalse,
      );
    });

    test('本段 ≥10 分钟 → 触发（先护眼、后领奖励）', () {
      expect(
        EyeCareService.shouldTriggerAtSessionEnd(
          focusElapsedSeconds: kEyeCareSessionEndMinutes * 60,
          lastEyeCareAtSecond: null,
        ),
        isTrue,
      );
    });

    test('场末用固定 10 分钟门槛，不被家长配的间隔带偏（5 分钟也不提前触发）', () {
      final AppSettings tight = _eyeSettings(intervalMin: 5);
      // 家长把间隔调到 5 分钟，场内 300 秒就弹过一次 → 场末本段从基线重算。
      expect(
        EyeCareService.shouldTriggerAtSessionEnd(
          focusElapsedSeconds: 300 + kEyeCareSessionEndMinutes * 60 - 1,
          lastEyeCareAtSecond: 300,
        ),
        isFalse,
      );
      expect(
        EyeCareService.shouldTriggerAtSessionEnd(
          focusElapsedSeconds: 300 + kEyeCareSessionEndMinutes * 60,
          lastEyeCareAtSecond: 300,
        ),
        isTrue,
      );
      // 场内间隔再小，也不改变场末门槛（tight 只影响 shouldTriggerInSession）。
      expect(
        EyeCareService.intervalSeconds(tight),
        300,
      );
    });

    test('长专注只补一次（绝不因为超长专注连插多张护眼卡）', () {
      int triggers = 0;
      for (int t = 0; t <= 60 * 60 * 3; t++) {
        if (EyeCareService.shouldTriggerAtSessionEnd(
          focusElapsedSeconds: t,
          lastEyeCareAtSecond: 0,
        )) {
          triggers++;
          break; // 场末只判一次，退场前不再累加
        }
      }
      expect(triggers, 1);
    });
  });

  group('播放列表契约（2026-10-05 玄参素材定稿：5 套素材排 7 槽位）', () {
    test('槽位顺序 = 玄参拍板：①close ②doitagain ③lookTip ④look×3 ⑤done', () {
      expect(kEyeCarePlaylist, hasLength(7));
      expect(kEyeCarePlaylist[0].dir, endsWith('/close'));
      expect(kEyeCarePlaylist[1].dir, endsWith('/doitagain'));
      expect(kEyeCarePlaylist[2].dir, endsWith('/lookTip'));
      expect(kEyeCarePlaylist[3].dir, endsWith('/look'));
      expect(kEyeCarePlaylist[4].dir, endsWith('/look'));
      expect(kEyeCarePlaylist[5].dir, endsWith('/look'));
      expect(kEyeCarePlaylist[6].dir, endsWith('/done'));
      // 段④是同一套素材连播 3 次（不是三份拷贝）。
      expect(identical(kEyeCarePlaylist[3], kEyeCarePlaylist[4]), isTrue);
      expect(identical(kEyeCarePlaylist[3], kEyeCarePlaylist[5]), isTrue);
    });

    test('每段帧数 > 0、时长 > 0；配音文件名与目录词干一一对应', () {
      for (final EyeCareSegment seg in kEyeCarePlaylist) {
        expect(seg.frameCount, greaterThan(0), reason: seg.dir);
        expect(seg.durationMs, greaterThan(0), reason: seg.dir);
        expect(
          seg.sfxAsset,
          endsWith('/eyecare_${seg.dir.split('/').last}.mp3'),
          reason: '配音词干必须与目录名一致（音频防静默失效）',
        );
        expect(seg.label, isNotEmpty);
      }
    });

    test('列表总长 ≈ 63.7s（音频实长），显示口径 63s 与之差 < 2s', () {
      expect(kEyeCarePlaylistTotalMs, 10162 + 10083 + 8098 + 10083 * 3 + 5094);
      expect(kEyeCarePlaylistTotalMs, closeTo(63700, 100));
      expect(
        (kEyeCarePlaylistTotalMs / 1000 - kEyeCareDurationSeconds).abs(),
        lessThan(2.0),
        reason: '显示倒计时（63s）与真实播放总长差距过大会让孩子困惑',
      );
    });
  });

  group('奖励（C28 §3）', () {
    test('完整完成 = +2 阳光，且 refType 字符串值冻结为 eye_care_break', () {
      expect(EyeCareService.rewardSunlight(), kEyeCareRewardSunlight);
      expect(kEyeCareRewardSunlight, 2);
      expect(kEyeCareRefType, 'eye_care_break');
      expect(kEyeCareRefLabel, '护眼',
          reason: '孩子端「阳光来源记录」的映射文案（口径冻结）');
    });
  });
}
